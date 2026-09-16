import Foundation
import Translation

enum TranslationServiceError: Error {
    case notInstalled
}

/// MainActor-isolated because it's only ever used from `ConversationModel`, which is MainActor.
@MainActor
final class TranslationService {
    private let source: String
    private let target: String
    private var session: TranslationSession?

    init(source: String, target: String) {
        self.source = source
        self.target = target
    }

    func translate(_ text: String) async throws -> String {
        let session = try await resolvedSession()
        return try await session.translate(text).targetText
    }

    private func resolvedSession() async throws -> TranslationSession {
        if let session { return session }
        let sourceLanguage = Locale.Language(identifier: source)
        let targetLanguage = Locale.Language(identifier: target)
        // UNVERIFIED (2026-09-13, written on Windows): LanguageAvailability().status(from:to:) is
        // async, and TranslationSession(installedSource:target:) needs no attached SwiftUI view
        // as long as the pair is already installed — confirm both on-device.
        let status = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
        guard status == .installed else { throw TranslationServiceError.notInstalled }
        let newSession = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        session = newSession
        return newSession
    }

    static func status(source: String, target: String) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(
            from: Locale.Language(identifier: source),
            to: Locale.Language(identifier: target)
        )
    }
}
