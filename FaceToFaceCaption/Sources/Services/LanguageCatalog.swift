import Foundation
import Speech

enum LanguageCatalog {
    /// BCP-47 identifiers of every locale on-device speech recognition supports, deduplicated
    /// and sorted by localized display name.
    static func speechLanguages() async -> [String] {
        // UNVERIFIED (2026-09-13, written on Windows): SpeechTranscriber.supportedLocales lives
        // in the Speech framework on iOS 26 and returns [Locale].
        let locales = await SpeechTranscriber.supportedLocales
        var seen = Set<String>()
        var result: [String] = []
        for locale in locales {
            let id = locale.identifier(.bcp47)
            guard seen.insert(id).inserted else { continue }
            result.append(id)
        }
        return result.sorted { displayName($0) < displayName($1) }
    }

    /// The language's name, localized into `localeID` (default: the device's current locale).
    static func displayName(_ id: String, in localeID: String? = nil) -> String {
        let locale = Locale(identifier: localeID ?? Locale.current.identifier)
        guard let name = locale.localizedString(forIdentifier: id) else { return id }
        return name.localizedCapitalized
    }

    /// The language's name written in that language itself.
    static func nativeName(_ id: String) -> String {
        let locale = Locale(identifier: id)
        guard let name = locale.localizedString(forIdentifier: id) else { return id }
        return name.localizedCapitalized
    }

    static func shortCode(_ id: String) -> String {
        Locale.Language(identifier: id).languageCode?.identifier.uppercased() ?? id.uppercased()
    }

    /// The supported identifier closest to `id`: same language + region first, then same language
    /// (preferring the first match in `candidates`). Nil if no candidate shares the language.
    static func bestMatch(_ id: String, in candidates: [String]) -> String? {
        let target = Locale.Language(identifier: id)
        guard let targetLanguageCode = target.languageCode else { return nil }

        if let regionMatch = candidates.first(where: { candidate in
            let language = Locale.Language(identifier: candidate)
            return language.languageCode == targetLanguageCode && language.region == target.region
        }) {
            return regionMatch
        }

        return candidates.first { candidate in
            Locale.Language(identifier: candidate).languageCode == targetLanguageCode
        }
    }
}
