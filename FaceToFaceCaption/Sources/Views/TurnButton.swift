import SwiftUI
import CaptionCore

/// Capsule mic button for one speaker's turn. `useNativeName` shows the language name written in
/// itself (for the partner's own button, who may not read the app's UI language) instead of the
/// name localized into the device's current locale.
struct TurnButton: View {
    let speaker: Speaker
    var useNativeName: Bool = false

    @Environment(ConversationModel.self) private var model

    private var languageID: String { model.pair.spoken(by: speaker) }

    private var languageLabel: String {
        useNativeName ? LanguageCatalog.nativeName(languageID) : LanguageCatalog.displayName(languageID)
    }

    private var isListening: Bool {
        if case .listening(let current) = model.turn { return current == speaker }
        return false
    }

    private var isFinishing: Bool {
        if case .finishing(let current) = model.turn { return current == speaker }
        return false
    }

    /// Disabled while any turn is finishing — a new turn can't start mid-handoff.
    private var isDisabled: Bool {
        if case .finishing = model.turn { return true }
        return false
    }

    var body: some View {
        Button {
            model.toggleTurn(speaker)
        } label: {
            HStack(spacing: Theme.Space.sm) {
                if isFinishing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finishing")
                } else if isListening {
                    Text("Done")
                    LevelMeter(level: model.level)
                } else {
                    Image(systemName: "mic")
                    Text("Speak \(languageLabel)")
                }
            }
            .lineLimit(1)
            .font(Theme.TypeFace.body)
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.Palette.paper3, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Theme.Palette.accent, lineWidth: isListening ? 1.5 : 0)
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if isFinishing { return "Finishing \(languageLabel)" }
        if isListening { return "Done speaking \(languageLabel)" }
        return "Speak \(languageLabel)"
    }
}
