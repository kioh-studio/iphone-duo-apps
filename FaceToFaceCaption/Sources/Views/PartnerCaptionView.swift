import SwiftUI
import CaptionCore

struct PartnerCaptionView: View {
    let showsTurnButton: Bool

    @Environment(ConversationModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var captionSize = Theme.TypeFace.captionBase

    private var caption: PartnerCaption { model.partnerCaption }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            content
            if showsTurnButton {
                TurnButton(speaker: .partner, useNativeName: true)
                    .padding(.top, Theme.Space.lg)
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(Theme.Palette.paper)
    }

    @ViewBuilder
    private var content: some View {
        if caption.current == nil && caption.previous == nil {
            idleContent
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                if let previous = caption.previous {
                    Text(previous)
                        .font(Theme.TypeFace.previousCaption)
                        .foregroundStyle(Theme.Palette.neutral)
                        .lineLimit(2)
                }
                if caption.isAwaitingTranslation {
                    PendingDots()
                }
                if let current = caption.current {
                    Text(current)
                        .id(current)
                        .font(Theme.TypeFace.caption(size: captionSize))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineLimit(5)
                        .minimumScaleFactor(0.5)
                        .transition(.opacity)
                }
            }
            .animation(Theme.Motion.crossfade(reduceMotion: reduceMotion), value: caption.current)
            .accessibilityElement(children: .combine)
        }
    }

    private var idleContent: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "waveform")
                .foregroundStyle(Theme.Palette.neutral)
            Text(LanguageCatalog.nativeName(model.pair.partner))
                .font(Theme.TypeFace.wordmark)
                .foregroundStyle(Theme.Palette.neutral)
        }
    }
}
