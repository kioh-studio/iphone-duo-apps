import AVFoundation
import CoreImage
import os

enum MovieRecorderError: Error {
    case noFrames
    case writerFailed
}

/// Writes processed frames (and optionally microphone audio) to an `.mp4` with `AVAssetWriter`.
/// Fed by `FrameProcessor` from the capture `videoQueue` (or the Simulator's `timerQueue`).
///
/// `@unchecked Sendable`: every piece of writer state (`pending`, `writer`, the inputs, the
/// adaptor, `startTime`, `outputURL`) lives on the private serial `queue` and is only touched from
/// blocks running on it — every entry point hops onto `queue` before reading or writing it, the same
/// "re-enter your own queue" discipline `CameraService` uses for `sessionQueue`. The one exception
/// is `isActive`, an `OSAllocatedUnfairLock<Bool>` that lets the per-frame entry points bail out
/// without a queue hop while nothing is recording. `ciContext` is documented thread-safe and is
/// only used on `queue` anyway.
final class MovieRecorder: @unchecked Sendable {
    private struct Request {
        let url: URL
        let includeAudio: Bool
    }

    private let queue = DispatchQueue(label: "tech.kioh.duostudio.recorder")
    private let isActive = OSAllocatedUnfairLock(initialState: false)
    private let ciContext = CIContext()

    // queue-confined:
    private var pending: Request?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var startTime: CMTime = .zero
    private var outputURL: URL?

    /// Arms the recorder. The `AVAssetWriter` is created lazily on the first video frame after this
    /// call, because the output dimensions come from that frame.
    func start(url: URL, includeAudio: Bool) {
        queue.sync {
            pending = Request(url: url, includeAudio: includeAudio)
            isActive.withLock { $0 = true }
        }
    }

    /// `time` is the frame's presentation time in seconds (capture clock on device, a monotonic
    /// uptime in the Simulator); it must be non-decreasing.
    func appendVideo(_ image: CIImage, time: Double) {
        guard isActive.withLock({ $0 }) else { return }
        queue.sync {
            if writer == nil {
                guard let request = pending else { return }
                guard beginWriting(request, image: image, time: time) else { return }
            }
            guard
                let writer, writer.status == .writing, let videoInput, let adaptor,
                videoInput.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool
            else { return }  // ponytail: a frame the encoder isn't ready for is dropped; add buffering only if device testing shows visible stutter

            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return }
            let extent = image.extent
            let origin = image.transformed(by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y))
            ciContext.render(origin, to: buffer)
            _ = adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
        }
    }

    /// Microphone audio; only buffers stamped at or after the session's start are written (the
    /// writer session can't take earlier ones).
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isActive.withLock({ $0 }) else { return }
        queue.sync {
            guard
                let writer, writer.status == .writing, let audioInput, audioInput.isReadyForMoreMediaData,
                CMSampleBufferGetPresentationTimeStamp(sampleBuffer) >= startTime
            else { return }
            _ = audioInput.append(sampleBuffer)
        }
    }

    /// Finishes the file and returns its URL. Throws `noFrames` if no video frame ever arrived.
    /// Resets all state, so the recorder can be started again straight away.
    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                isActive.withLock { $0 = false }
                let finishedWriter = writer
                let finishedURL = outputURL
                let finishedVideoInput = videoInput
                let finishedAudioInput = audioInput
                resetState()

                guard let finishedWriter, let finishedURL else {
                    continuation.resume(throwing: MovieRecorderError.noFrames)
                    return
                }
                // The writer can have failed mid-recording (disk full, encoder error). Marking
                // inputs finished or finishing a non-writing writer is invalid, so clean up and
                // report the failure instead.
                let status = finishedWriter.status
                guard status == .writing else {
                    if status == .writing || status == .unknown { finishedWriter.cancelWriting() }
                    try? FileManager.default.removeItem(at: finishedURL)
                    continuation.resume(throwing: finishedWriter.error ?? MovieRecorderError.writerFailed)
                    return
                }
                finishedVideoInput?.markAsFinished()
                finishedAudioInput?.markAsFinished()
                // `AVAssetWriter` isn't `Sendable`; this reference is no longer reachable from
                // `queue` (state was reset above) and is touched only by the completion block.
                nonisolated(unsafe) let unsafeWriter = finishedWriter
                // UNVERIFIED (2026-10-18, written on Windows): `finishWriting(completionHandler:)`
                // (the callback form) is assumed still available alongside the async overload.
                unsafeWriter.finishWriting {
                    if unsafeWriter.status == .completed {
                        continuation.resume(returning: finishedURL)
                    } else {
                        try? FileManager.default.removeItem(at: finishedURL)
                        continuation.resume(throwing: unsafeWriter.error ?? MovieRecorderError.writerFailed)
                    }
                }
            }
        }
    }

    // MARK: - queue-confined helpers

    private func resetState() {
        pending = nil
        writer = nil
        videoInput = nil
        adaptor = nil
        audioInput = nil
        outputURL = nil
        startTime = .zero
    }

    /// Builds the writer from the first frame's size and starts the session at that frame's time.
    /// On any failure, disarms the recorder (`finish()` then reports `noFrames`).
    private func beginWriting(_ request: Request, image: CIImage, time: Double) -> Bool {
        // H.264 wants even dimensions.
        let width = Int(image.extent.width) & ~1
        let height = Int(image.extent.height) & ~1

        guard
            width > 0, height > 0,
            let newWriter = try? AVAssetWriter(outputURL: request.url, fileType: .mp4)
        else {
            disarm()
            return false
        }

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        video.expectsMediaDataInRealTime = true
        // UNVERIFIED (2026-10-18, written on Windows): adaptor + pool usage — assumes the pool is
        // non-nil right after `startWriting()` when `sourcePixelBufferAttributes` is supplied.
        let newAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: video,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        guard newWriter.canAdd(video) else {
            disarm()
            return false
        }
        newWriter.add(video)

        var audio: AVAssetWriterInput?
        if request.includeAudio {
            // UNVERIFIED (2026-10-18, written on Windows): handing the capture output's raw mic
            // buffers to an AAC-configured input (the writer converts) is the common pattern but
            // wasn't checked against the current SDK.
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = true
            if newWriter.canAdd(input) {
                newWriter.add(input)
                audio = input
            }
        }

        guard newWriter.startWriting() else {
            disarm()
            return false
        }
        let start = CMTime(seconds: time, preferredTimescale: 600)
        newWriter.startSession(atSourceTime: start)

        writer = newWriter
        videoInput = video
        adaptor = newAdaptor
        audioInput = audio
        startTime = start
        outputURL = request.url
        return true
    }

    private func disarm() {
        pending = nil
        isActive.withLock { $0 = false }
    }
}
