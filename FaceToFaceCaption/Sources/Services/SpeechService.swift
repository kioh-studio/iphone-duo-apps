import Foundation
import AVFoundation
import Speech

enum SpeechEvent: Sendable {
    case volatile(String)
    case final(String)
    case level(Double)
}

enum SpeechServiceError: Error {
    case unsupportedLocale
    case modelNotInstalled
    case noAudioFormat
    case converterUnavailable
}

/// Everything the realtime audio tap touches, boxed so the tap closure captures one Sendable value.
/// Safe because the tap is the only user after `start()` hands these over, and it runs serially.
private final class TapContext: @unchecked Sendable {
    let converter: AVAudioConverter
    let micFormat: AVAudioFormat
    let analyzerFormat: AVAudioFormat
    let input: AsyncStream<AnalyzerInput>.Continuation
    let events: AsyncThrowingStream<SpeechEvent, Error>.Continuation

    init(converter: AVAudioConverter, micFormat: AVAudioFormat, analyzerFormat: AVAudioFormat,
         input: AsyncStream<AnalyzerInput>.Continuation, events: AsyncThrowingStream<SpeechEvent, Error>.Continuation) {
        self.converter = converter
        self.micFormat = micFormat
        self.analyzerFormat = analyzerFormat
        self.input = input
        self.events = events
    }
}

/// One-shot flag for AVAudioConverter's input block (which may be @Sendable, so no captured `var`).
private final class DeliveryFlag: @unchecked Sendable {
    var delivered = false
}

/// One instance is used per turn; `start()` and `finish()` are called sequentially by
/// `ConversationModel` (never concurrently). `@unchecked Sendable` because the audio tap runs on
/// a realtime audio thread outside any actor — but the tap closure only ever touches the
/// converter/format/builder/continuation it captures locally, never `self`'s stored properties,
/// so there is no shared mutable state for it to race with `start()`/`finish()` on.
final class SpeechService: @unchecked Sendable {
    private let localeIdentifier: String
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?

    init(localeIdentifier: String) {
        self.localeIdentifier = localeIdentifier
    }

    static func isSupported(_ id: String) async -> Bool {
        let target = Locale(identifier: id).identifier(.bcp47)
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { $0.identifier(.bcp47) == target }
    }

    static func isInstalled(_ id: String) async -> Bool {
        let target = Locale(identifier: id).identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == target }
    }

    // UNVERIFIED (2026-09-13, written on Windows): AssetInventory.assetInstallationRequest(
    // supporting:) and Progress.fractionCompleted polling — confirm this is the intended way to
    // report download progress, and that fractionCompleted is safe to read off the main actor.
    static func install(localeIdentifier: String, progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
        let locale = Locale(identifier: localeIdentifier)
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            await progress(1)
            return
        }
        let poll = Task {
            while !Task.isCancelled && request.progress.fractionCompleted < 1 {
                await progress(request.progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { poll.cancel() }
        try await request.downloadAndInstall()
        await progress(1)
    }

    func start() async throws -> AsyncThrowingStream<SpeechEvent, Error> {
        guard await Self.isInstalled(localeIdentifier) else { throw SpeechServiceError.modelNotInstalled }

        var eventsContinuation: AsyncThrowingStream<SpeechEvent, Error>.Continuation?
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)

            let locale = Locale(identifier: localeIdentifier)
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw SpeechServiceError.noAudioFormat
            }

            let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
            self.inputBuilder = inputBuilder
            try await analyzer.start(inputSequence: inputSequence)

            let engine = AVAudioEngine()
            self.engine = engine
            let micFormat = engine.inputNode.outputFormat(forBus: 0)
            guard let converter = AVAudioConverter(from: micFormat, to: format) else {
                throw SpeechServiceError.converterUnavailable
            }

            let (events, continuation) = AsyncThrowingStream<SpeechEvent, Error>.makeStream()
            eventsContinuation = continuation

            let context = TapContext(
                converter: converter,
                micFormat: micFormat,
                analyzerFormat: format,
                input: inputBuilder,
                events: continuation
            )

            // UNVERIFIED (2026-09-13, written on Windows): AVAudioConverter conversion — the
            // single-shot input block pattern below (yield the buffer once, then `.noDataNow`) and
            // whether one `convert(to:error:withInputFrom:)` call per tap buffer is the right shape.
            // Pitfall (per brief): the mic's native format does not match `format` — buffers must be
            // converted with AVAudioConverter, or the analyzer silently produces no text.
            engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
                Self.process(buffer, context: context)
            }

            engine.prepare()
            try engine.start()

            Task {
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        continuation.yield(result.isFinal ? .final(text) : .volatile(text))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            return events
        } catch {
            await finish()
            eventsContinuation?.finish(throwing: error)
            throw error
        }
    }

    /// Runs on the realtime audio thread via the tap; touches only `context`, never `self`.
    private static func process(_ buffer: AVAudioPCMBuffer, context: TapContext) {
        if let channelData = buffer.floatChannelData {
            let frameCount = Int(buffer.frameLength)
            let samples = channelData[0]
            var sum: Float = 0
            for i in 0..<frameCount { sum += samples[i] * samples[i] }
            let rms = frameCount > 0 ? sqrtf(sum / Float(frameCount)) : 0
            let db = 20 * log10f(max(rms, 0.000_001))
            let level = min(1, max(0, (db + 50) / 50))
            context.events.yield(.level(Double(level)))
        }

        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * context.analyzerFormat.sampleRate / context.micFormat.sampleRate) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: context.analyzerFormat, frameCapacity: capacity) else { return }
        let flag = DeliveryFlag()
        nonisolated(unsafe) let source = buffer
        var conversionError: NSError?
        _ = context.converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if flag.delivered {
                status.pointee = .noDataNow
                return nil
            }
            flag.delivered = true
            status.pointee = .haveData
            return source
        }
        if conversionError == nil {
            context.input.yield(AnalyzerInput(buffer: outputBuffer))
        }
    }

    func finish() async {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        inputBuilder?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        engine = nil
        inputBuilder = nil
        analyzer = nil
    }
}
