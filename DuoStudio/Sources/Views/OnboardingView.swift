import SwiftUI

/// First launch only: value -> six modes -> pick a skin. The camera permission is requested after
/// this (by `RootView`), not before. `onFinish` sets the "hasOnboarded" flag.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    private let lastPage = 2

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            ScrollView {
                pageContent
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.top, Theme.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            pageDots

            Button {
                if page < lastPage {
                    page += 1
                } else {
                    onFinish()
                }
            } label: {
                Text(page < lastPage ? "Continue" : "Start shooting")
                    .font(Theme.TypeFace.body)
                    .frame(maxWidth: .infinity, minHeight: Theme.Space.hitTarget)
                    .foregroundStyle(Theme.Palette.onAccent)
                    .background(Theme.Palette.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.lg)
        }
        .background(Theme.Palette.paper.ignoresSafeArea())
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0: valuePage
        case 1: modesPage
        default: SkinPickerView()
        }
    }

    private var pageDots: some View {
        HStack(spacing: Theme.Space.sm) {
            ForEach(0...lastPage, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.Palette.accent : Theme.Palette.rule)
                    .frame(width: Theme.Space.sm, height: Theme.Space.sm)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(lastPage + 1)")
    }

    // MARK: - Pages

    private var valuePage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("DUO STUDIO")
                .font(Theme.TypeFace.label)
                .tracking(Theme.TypeFace.labelTracking)
                .foregroundStyle(Theme.Palette.accent)
            Text("Your subject finally sees the shot.")
                .font(Theme.TypeFace.display)
                .foregroundStyle(Theme.Palette.ink)
            Text("You frame on the inside. The person you’re shooting watches the outer screen and gets into position on their own.")
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.muted)
            illustration
        }
    }

    /// Two rounded rectangles: the inner display (you frame) and the outer one (they watch).
    private var illustration: some View {
        HStack(spacing: Theme.Space.md) {
            screenCard(title: "INSIDE", caption: "You frame", isOuter: false)
            screenCard(title: "OUTSIDE", caption: "They watch", isOuter: true)
        }
        .frame(height: Theme.Layout.illustrationHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Inside screen: you frame. Outside screen: they watch.")
    }

    private func screenCard(title: String, caption: String, isOuter: Bool) -> some View {
        VStack(spacing: Theme.Space.xs) {
            Text(title)
                .font(Theme.TypeFace.label)
                .tracking(Theme.TypeFace.labelTracking)
                .foregroundStyle(isOuter ? Theme.Palette.accent : Theme.Palette.neutral)
            Text(caption)
                .font(Theme.TypeFace.control)
                .foregroundStyle(Theme.Palette.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(isOuter ? Theme.Palette.accent : Theme.Palette.rule, lineWidth: Theme.Stroke.selection)
        )
    }

    private var modesPage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("Six modes. Two groups.")
                .font(Theme.TypeFace.title)
                .foregroundStyle(Theme.Palette.ink)
            modeGroup("PHOTO", modes: StudioMode.modes(in: .photo))
            modeGroup("VIDEO", modes: StudioMode.modes(in: .video))
        }
    }

    private func modeGroup(_ title: String, modes: [StudioMode]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title)
                .font(Theme.TypeFace.label)
                .tracking(Theme.TypeFace.labelTracking)
                .foregroundStyle(Theme.Palette.neutral)
            VStack(spacing: Theme.Space.sm) {
                ForEach(modes, id: \.self) { mode in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(mode.title)
                            .font(Theme.TypeFace.body)
                            .foregroundStyle(Theme.Palette.ink)
                        Text(mode.tagline)
                            .font(Theme.TypeFace.control)
                            .foregroundStyle(Theme.Palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.md)
                    .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
