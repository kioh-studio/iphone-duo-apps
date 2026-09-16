import Foundation
import Observation
import Translation
import AVFAudio
import CaptionCore

/// Owned by `LanguageSetupView` as `@State`; drives the setup screen's readiness checks and
/// downloads without the view touching any service directly.
@MainActor
@Observable
final class SetupModel {
    enum Readiness: Equatable {
        case checking, ready, needsDownload, downloading(Double), unavailable
    }

    private let conversation: ConversationModel

    private(set) var availableLanguages: [String] = []
    private(set) var mineSpeech: Readiness = .checking
    private(set) var partnerSpeech: Readiness = .checking
    private(set) var translation: Readiness = .checking
    private(set) var micDenied = false
    var translationDownloadConfig: TranslationSession.Configuration?

    init(conversation: ConversationModel) {
        self.conversation = conversation
    }

    var pair: LanguagePair {
        get { conversation.pair }
        set { conversation.pair = newValue }
    }

    var canStart: Bool {
        mineSpeech == .ready && partnerSpeech == .ready && translation == .ready
    }

    var needsDownload: Bool {
        mineSpeech == .needsDownload || partnerSpeech == .needsDownload || translation == .needsDownload
    }

    var isSpeechUnavailable: Bool {
        mineSpeech == .unavailable || partnerSpeech == .unavailable
    }

    var isTranslationUnavailable: Bool {
        translation == .unavailable
    }

    var isUnsupportedPair: Bool {
        isSpeechUnavailable || isTranslationUnavailable
    }

    func refresh() async {
        if availableLanguages.isEmpty {
            availableLanguages = await LanguageCatalog.speechLanguages()
        }
        if !availableLanguages.isEmpty {
            normalizePairToSupportedLocales()
        }
        async let mine = speechReadiness(pair.mine)
        async let partner = speechReadiness(pair.partner)
        async let translationReadiness = translationReadiness()
        mineSpeech = await mine
        partnerSpeech = await partner
        translation = await translationReadiness
    }

    /// Device locales like "en-VN" may not be in `availableLanguages` even though the base
    /// language is supported — swap in the closest supported identifier so readiness checks
    /// (and `pair`'s persistence) use one that actually resolves.
    private func normalizePairToSupportedLocales() {
        var next = pair
        if !availableLanguages.contains(next.mine), let match = LanguageCatalog.bestMatch(next.mine, in: availableLanguages) {
            next.mine = match
        }
        if !availableLanguages.contains(next.partner), let match = LanguageCatalog.bestMatch(next.partner, in: availableLanguages) {
            next.partner = match
        }
        if next != pair {
            pair = next
        }
    }

    private func speechReadiness(_ localeID: String) async -> Readiness {
        guard await SpeechService.isSupported(localeID) else { return .unavailable }
        return await SpeechService.isInstalled(localeID) ? .ready : .needsDownload
    }

    private func translationReadiness() async -> Readiness {
        switch await TranslationService.status(source: pair.mine, target: pair.partner) {
        case .installed: return .ready
        case .supported: return .needsDownload
        case .unsupported: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func downloadMissing() async {
        if mineSpeech == .needsDownload {
            await downloadSpeech(localeID: pair.mine) { [weak self] fraction in
                self?.mineSpeech = .downloading(fraction)
            }
        }
        if partnerSpeech == .needsDownload {
            await downloadSpeech(localeID: pair.partner) { [weak self] fraction in
                self?.partnerSpeech = .downloading(fraction)
            }
        }
        if translation == .needsDownload {
            let source = Locale.Language(identifier: pair.mine)
            let target = Locale.Language(identifier: pair.partner)
            // UNVERIFIED (2026-09-13, written on Windows): re-triggering a `.translationTask` by
            // calling `Configuration.invalidate()` on an already-set configuration, versus
            // needing a fresh `Configuration` instance assigned to `translationDownloadConfig`.
            if let config = translationDownloadConfig, config.source == source, config.target == target {
                translationDownloadConfig?.invalidate()
            } else {
                translationDownloadConfig = TranslationSession.Configuration(source: source, target: target)
            }
        }
        await refresh()
    }

    private func downloadSpeech(localeID: String, progress: @escaping @MainActor @Sendable (Double) -> Void) async {
        try? await SpeechService.install(localeIdentifier: localeID, progress: progress)
        // Any failure just leaves this side as `.needsDownload` after `refresh()` below.
    }

    /// Called from `LanguageSetupView`'s `.translationTask` when the download config triggers a
    /// session — downloads the translation model, then re-checks readiness.
    func prepare(_ session: TranslationSession) async {
        // UNVERIFIED (2026-09-13, written on Windows): TranslationSession.prepareTranslation()
        // triggers the system's language-download UI/flow as intended here.
        try? await session.prepareTranslation()
        await refresh()
    }

    func start() async {
        // UNVERIFIED (2026-09-13, written on Windows): AVAudioApplication.requestRecordPermission()
        // as an async, non-completion-handler static function on the iOS 26 SDK.
        let granted = await AVAudioApplication.requestRecordPermission()
        if granted {
            conversation.startConversation()
        } else {
            micDenied = true
        }
    }

    func swap() {
        conversation.pair = conversation.pair.swapped
        Task { await refresh() }
    }
}
