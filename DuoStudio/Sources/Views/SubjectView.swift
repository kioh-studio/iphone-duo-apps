import SwiftUI
import PoseCore

/// The subject-facing experience: mirrored live preview, template + live skeleton, big match %,
/// gesture toast and legend. Non-interactive by design - no buttons, since the Duo's outer
/// display has no touch. Also used as the preview of `StudioView` for Selfie and Solo video
/// (`isOuterDisplay: false`), where `StudioView` overlays its top bar on it.
///
/// Everything here is drawn over live video (or on the outer display, which is always dark), so it
/// uses the skin's `overlay*` tokens and `scrim`, never `ink` / `accent` (dark on the light skins).
///
/// Photo modes show the pose-template experience above. Video modes swap the top readout and the
/// overlay for the chosen guide - Frame (safe box + hint), Script (teleprompter) or Dance (ghost
/// skeleton + match %, then the routine score) - plus the pre-recording countdown and a REC badge.
struct SubjectView: View {
    /// `true` on the Duo's outer accessory; `false` when this is the inner preview (Selfie, Solo
    /// video). Only affects layout - top space for `StudioView`'s top bar, and the colour scheme
    /// (the outer display is always dark) - never the content itself.
    var isOuterDisplay: Bool = true

    @Environment(StudioModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var matchPercent: Int? {
        guard let match = model.match else { return nil }
        return Int((match.score * 100).rounded())
    }

    var body: some View {
        ZStack {
            Theme.Palette.overlayBase.ignoresSafeArea()
            mirroredPreview.ignoresSafeArea()

            Group {
                switch model.shootKind {
                case .photo: photoHUD
                case .video: videoHUD
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, isOuterDisplay ? Theme.Space.lg : Theme.Layout.topBarClearance)
            .padding(.bottom, Theme.Space.lg)

            countdown
        }
        // UNVERIFIED (2026-10-18, written on Windows): `nil` here leaves the window's scheme (the skin's)
        // alone when this view is the inner preview; the outer display forces dark.
        .preferredColorScheme(isOuterDisplay ? .dark : nil)
        .accessibilityElement(children: .combine)
    }

    private var photoHUD: some View {
        VStack {
            scoreReadout
            Spacer()
            if let toast = model.lastGesture {
                toastView(toast)
            }
            Spacer()
            hud
        }
    }

    /// Video kind. Gesture toast and HUD/legend are hidden while counting down or recording
    /// (gestures are off then); shown otherwise, including while saving.
    private var videoHUD: some View {
        VStack(spacing: Theme.Space.md) {
            recordingBadge
            videoReadout
            Spacer()
            if !model.isRecordingActive {
                if let toast = model.lastGesture {
                    toastView(toast)
                }
                hud
            }
        }
    }

    @ViewBuilder
    private var videoReadout: some View {
        switch model.videoGuide {
        case .frame:
            let hint = model.frameHint ?? .noPerson
            Text(hint.message)
                .font(Theme.TypeFace.outerLabel)
                .foregroundStyle(hint == .inFrame ? Theme.Palette.overlayAccent : Theme.Palette.overlayInk)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, Theme.Space.md)
                .background(Theme.Palette.scrim, in: Capsule())
                .accessibilityLabel("Framing")
                .accessibilityValue(hint.message)
        case .script:
            TeleprompterView()
        case .dance:
            if let score = model.lastRoutineScore {
                routineScore(score)
            } else {
                scoreReadout
            }
        case .interview:
            // The guest just sees themselves (plus countdown and REC): no skeleton, no match %.
            EmptyView()
        }
    }

    private func routineScore(_ score: Int) -> some View {
        VStack(spacing: Theme.Space.xs) {
            Text("\(score)%")
                .font(Theme.TypeFace.outerScore)
                .foregroundStyle(Theme.Palette.overlayAccent)
                .monospacedDigit()
            Text("ROUTINE SCORE")
                .font(Theme.TypeFace.outerLegend)
                .tracking(Theme.TypeFace.labelTracking)
                .foregroundStyle(Theme.Palette.overlayMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Routine score")
        .accessibilityValue("\(score) percent")
    }

    /// "REC 00:12", top-trailing, only while recording.
    private var recordingBadge: some View {
        HStack {
            Spacer()
            if model.recordingPhase == .recording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(model.elapsedLabel(at: ProcessInfo.processInfo.systemUptime))
                        .font(Theme.TypeFace.outerLabel)
                        .foregroundStyle(Theme.Palette.overlayInk)
                        .monospacedDigit()
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.vertical, Theme.Space.sm)
                        .background(Theme.Palette.scrim, in: Capsule())
                }
            }
        }
    }

    /// Centred 3-2-1, crossfading per number (no animation under Reduce Motion).
    private var countdown: some View {
        ZStack {
            if let number = model.countdownValue {
                Text("\(number)")
                    .font(Theme.TypeFace.outerCountdown)
                    .foregroundStyle(Theme.Palette.overlayAccent)
                    .id(number)
                    .transition(.opacity)
                    .accessibilityLabel("Recording starts in \(number)")
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.crossfade(reduceMotion: false), value: model.countdownValue)
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
                    if !model.isInterviewVideo {
                        SkeletonOverlay(
                            livePose: model.livePose,
                            template: model.displayTemplate,
                            match: model.match,
                            imageSize: CGSize(width: image.width, height: image.height)
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    if model.shootKind == .video, model.videoGuide == .frame {
                        FrameGuideOverlay(hint: model.frameHint, imageSize: CGSize(width: image.width, height: image.height))
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                } else {
                    Theme.Palette.overlayBase
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
            .foregroundStyle(Theme.Palette.overlayAccent)
            .monospacedDigit()
            .accessibilityLabel("Pose match")
            .accessibilityValue(matchPercent.map { "\($0) percent" } ?? "No pose detected")
    }

    private func toastView(_ toast: GestureToast) -> some View {
        Label(toast.text, systemImage: toast.symbol)
            .font(Theme.TypeFace.outerToast)
            .foregroundStyle(Theme.Palette.overlayInk)
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
                .foregroundStyle(Theme.Palette.overlayInk)
            Text(model.state.adjustments.formatted(model.state.selectedParameter))
                .font(Theme.TypeFace.outerLabel)
                .foregroundStyle(Theme.Palette.overlayMuted)
            legend
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.scrim, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }

    // UNVERIFIED (2026-09-20, written on Windows): SF Symbols has no confirmed literal
    // "fist"/"OK sign" glyph — `hand.raised.fill` and `hand.pinch` are best-guess stand-ins pending
    // a symbol picker check on a Mac; the words alongside them carry the real meaning either way.
    private var legend: some View {
        HStack(spacing: Theme.Space.lg) {
            legendItem(symbol: "hand.raised", text: "swipe = filter")
            // `HandClassifier.classify` only reads `.pinch` when the other three fingers are
            // extended (an OK sign) — an ordinary pinch with the rest of the hand curled reads as
            // `.fist` instead. The symbol stays; the word matches what the classifier actually
            // requires.
            legendItem(symbol: "hand.pinch", text: "OK sign = zoom")
            legendItem(symbol: "hand.raised.fill", text: "fist = setting")
            legendItem(symbol: "hand.point.up.left.fill", text: "point = adjust")
        }
        .font(Theme.TypeFace.outerLegend)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func legendItem(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Theme.Palette.overlayMuted)
    }
}
