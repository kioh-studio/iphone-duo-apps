import SwiftUI
import CaptionCore

struct BannerView: View {
    let banner: ConversationModel.Banner

    @Environment(ConversationModel.self) private var model

    private var message: String {
        switch banner {
        case .speechMissing(let speaker):
            let language = LanguageCatalog.displayName(model.pair.spoken(by: speaker))
            return "\(language) speech isn't downloaded. Captions need it to hear this side."
        case .micStopped:
            return "The microphone stopped. Another app may be using it. Tap Speak to try again."
        case .translationMissing:
            let mine = LanguageCatalog.displayName(model.pair.mine)
            let partner = LanguageCatalog.displayName(model.pair.partner)
            return "\(mine) ↔ \(partner) translation isn't downloaded."
        }
    }

    private var actionTitle: String? {
        switch banner {
        case .speechMissing, .translationMissing: return "Set up languages"
        case .micStopped: return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.Palette.danger)
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(message)
                    .font(Theme.TypeFace.body)
                    .foregroundStyle(Theme.Palette.ink)
                if let actionTitle {
                    Button(actionTitle) {
                        model.banner = nil
                        model.openSetupSheet()
                    }
                    .font(Theme.TypeFace.secondary)
                    .foregroundStyle(Theme.Palette.accent)
                }
            }
            Spacer(minLength: 0)
            Button {
                model.banner = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(Theme.Palette.neutral)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, Theme.Space.md)
        .background(Theme.Palette.paper2)
    }
}
