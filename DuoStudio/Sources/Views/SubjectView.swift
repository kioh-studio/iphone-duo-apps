import SwiftUI
import PoseCore

/// The subject-facing experience: mirrored live preview, template + live skeleton, big match %,
/// gesture toast and legend. Non-interactive by design — no buttons, since the Duo's outer
/// display has no touch. Reused verbatim as the main screen's backdrop in self-portrait mode
/// (`isOuterDisplay: false`), where `StudioView` overlays a thin interactive control layer on top.
struct SubjectView: View {
    /// `true` on the Duo's outer accessory; `false` when this is reused as the main screen's
    /// content in self-portrait mode. Only affects layout — enough bottom padding to clear the
    /// overlaid control bar — never the content itself ("the legend stays" per the spec).
    var isOuterDisplay: Bool = true

    @Environment(StudioModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var matchPercent: Int? {
        guard let match = model.match else { return nil }
        return Int((match.score * 100).rounded())
    }

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()
            mirroredPreview.ignoresSafeArea()

            VStack {
                scoreReadout
                Spacer()
                if let toast = model.lastGesture {
                    toastView(toast)
                }
                Spacer()
                hud
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.lg)
            .padding(.bottom, isOuterDisplay ? Theme.Space.lg : Theme.Space.xxl)
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
    }

    /// Preview + overlay mirrored together, then scaled by `outerZoom` around the centre — zoom
    /// only inspects detail on this display, it never affects the photo that gets captured.
    private var mirroredPreview: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = model.previewImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    SkeletonOverlay(
                        livePose: model.livePose,
                        template: model.displayTemplate,
                        match: model.match,
                        imageSize: CGSize(width: image.width, height: image.height)
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    Color.black
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .scaleEffect(x: -1, y: 1)
        .scaleEffect(model.state.outerZoom)
        .clipped()
        .animation(reduceMotion ? nil : Theme.Motion.easeOut(Theme.Motion.short), value: model.state.outerZoom)
    }

    private var scoreReadout: some View {
        Text(matchPercent.map { "\($0)%" } ?? "—")
            .font(Theme.TypeFace.outerScore)
            .foregroundStyle(Theme.Palette.accent)
            .monospacedDigit()
            .accessibilityLabel("Pose match")
            .accessibilityValue(matchPercent.map { "\($0) percent" } ?? "No pose detected")
    }

    private func toastView(_ toast: GestureToast) -> some View {
        Label(toast.text, systemImage: toast.symbol)
            .font(Theme.TypeFace.outerToast)
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.md)
            .background(Theme.Palette.scrim, in: Capsule())
            .id(toast.id)
            .transition(.opacity)
            .animation(Theme.Motion.crossfade(reduceMotion: reduceMotion), value: toast.id)
    }

    private var hud: some View {
        VStack(spacing: Theme.Space.sm) {
            Text(model.state.filter.displayName)
                .font(Theme.TypeFace.outerLabel)
                .foregroundStyle(Theme.Palette.ink)
            Text(model.state.adjustments.formatted(model.state.selectedParameter))
                .font(Theme.TypeFace.outerLabel)
                .foregroundStyle(Theme.Palette.muted)
            legend
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.scrim, in: RoundedRectangle(cornerRadius: Theme.Space.sm))
    }

    // UNVERIFIED (2026-09-20, written on Windows): SF Symbols has no confirmed literal
    // "fist"/"pinch" glyph — `hand.raised.fill` and `hand.pinch` are best-guess stand-ins pending
    // a symbol picker check on a Mac; the words alongside them carry the real meaning either way.
    private var legend: some View {
        HStack(spacing: Theme.Space.lg) {
            legendItem(symbol: "hand.raised", text: "swipe = filter")
            legendItem(symbol: "hand.pinch", text: "pinch = zoom")
            legendItem(symbol: "hand.raised.fill", text: "fist = setting")
            legendItem(symbol: "hand.point.up.left.fill", text: "point = adjust")
        }
        .font(Theme.TypeFace.label)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func legendItem(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Theme.Palette.neutral)
    }
}
