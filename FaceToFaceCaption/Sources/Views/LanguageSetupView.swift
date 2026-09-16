import SwiftUI
import UIKit
import Translation
import CaptionCore

struct LanguageSetupView: View {
    enum Mode: Equatable { case launch, sheet }

    let mode: Mode

    @State private var setup = SetupModel(conversation: .shared)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                header
                languageRows
                readinessRows
                if setup.isSpeechUnavailable {
                    speechUnavailableNotice
                }
                if setup.isTranslationUnavailable {
                    translationUnavailableNotice
                }
                if setup.micDenied {
                    micDeniedNotice
                }
            }
            .padding(Theme.Space.xl)
        }
        .background(Theme.Palette.paper)
        .safeAreaInset(edge: .bottom) {
            primaryButton.padding(Theme.Space.xl)
        }
        .task { await setup.refresh() }
        .onChange(of: setup.pair) { _, _ in
            Task { await setup.refresh() }
        }
        .translationTask(setup.translationDownloadConfig) { session in
            await setup.prepare(session)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Across")
                .font(Theme.TypeFace.wordmark)
                .foregroundStyle(Theme.Palette.ink)
            Text("Two languages, one table. Everything stays on this iPhone.")
                .font(Theme.TypeFace.secondary)
                .foregroundStyle(Theme.Palette.muted)
        }
    }

    private var languageRows: some View {
        VStack(spacing: 0) {
            LanguageRow(title: "You speak", selection: mineBinding, options: setup.availableLanguages)
            hairline
            Button {
                setup.swap()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Swap languages")
            hairline
            LanguageRow(title: "They speak", selection: partnerBinding, options: setup.availableLanguages)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.Palette.rule)
            .frame(height: 1)
    }

    private var mineBinding: Binding<String> {
        Binding(get: { setup.pair.mine }, set: { setup.pair.mine = $0 })
    }

    private var partnerBinding: Binding<String> {
        Binding(get: { setup.pair.partner }, set: { setup.pair.partner = $0 })
    }

    private var readinessRows: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            ReadinessRow(title: "\(LanguageCatalog.displayName(setup.pair.mine)) speech", readiness: setup.mineSpeech)
            ReadinessRow(title: "\(LanguageCatalog.displayName(setup.pair.partner)) speech", readiness: setup.partnerSpeech)
            ReadinessRow(
                title: "\(LanguageCatalog.displayName(setup.pair.mine)) ↔ \(LanguageCatalog.displayName(setup.pair.partner)) translation",
                readiness: setup.translation
            )
        }
    }

    private var speechUnavailableNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.danger)
            Text(
                "\(unavailableSpeechLanguageName) speech isn't available on this iPhone. Pick another language."
            )
            .font(Theme.TypeFace.secondary)
            .foregroundStyle(Theme.Palette.ink)
        }
    }

    /// Whichever side is unavailable; if both are, names the "You speak" side.
    private var unavailableSpeechLanguageName: String {
        LanguageCatalog.displayName(setup.mineSpeech == .unavailable ? setup.pair.mine : setup.pair.partner)
    }

    private var translationUnavailableNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.danger)
            Text(
                "\(LanguageCatalog.displayName(setup.pair.mine)) ↔ \(LanguageCatalog.displayName(setup.pair.partner)) can't be translated on this iPhone yet. Pick another language."
            )
            .font(Theme.TypeFace.secondary)
            .foregroundStyle(Theme.Palette.ink)
        }
    }

    private var micDeniedNotice: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.danger)
                Text("Microphone access is off. Across needs it to hear the conversation.")
                    .font(Theme.TypeFace.secondary)
                    .foregroundStyle(Theme.Palette.ink)
            }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundStyle(Theme.Palette.accent)
        }
    }

    private var primaryButton: some View {
        Button {
            Task {
                if setup.needsDownload {
                    await setup.downloadMissing()
                } else {
                    await setup.start()
                    if setup.canStart, mode == .sheet {
                        dismiss()
                    }
                }
            }
        } label: {
            Text(primaryButtonTitle)
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.Palette.paper3, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Palette.accent, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
        .disabled(setup.isUnsupportedPair || !(setup.needsDownload || setup.canStart))
        .opacity(setup.isUnsupportedPair || !(setup.needsDownload || setup.canStart) ? 0.4 : 1)
    }

    private var primaryButtonTitle: String {
        if setup.needsDownload { return "Download languages" }
        return mode == .sheet ? "Done" : "Start conversation"
    }
}

private struct LanguageRow: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { id in
                    Button(LanguageCatalog.displayName(id)) { selection = id }
                }
            } label: {
                Text(LanguageCatalog.displayName(selection))
                    .foregroundStyle(Theme.Palette.neutral)
            }
        }
        .padding(.vertical, Theme.Space.md)
    }
}

private struct ReadinessRow: View {
    let title: String
    let readiness: SetupModel.Readiness

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            icon
            Text(title)
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Text(statusText)
                .font(Theme.TypeFace.secondary)
                .foregroundStyle(Theme.Palette.neutral)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch readiness {
        case .checking:
            ProgressView().controlSize(.small)
        case .ready:
            Image(systemName: "checkmark").foregroundStyle(Theme.Palette.accent)
        case .needsDownload:
            Image(systemName: "arrow.down.circle").foregroundStyle(Theme.Palette.neutral)
        case .downloading:
            ProgressView().controlSize(.small)
        case .unavailable:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.Palette.danger)
        }
    }

    private var statusText: String {
        switch readiness {
        case .checking: return ""
        case .ready: return "Ready"
        case .needsDownload: return "Needs download"
        case .downloading(let fraction): return "Downloading \(Int(fraction * 100))%"
        case .unavailable: return "Not available"
        }
    }
}
