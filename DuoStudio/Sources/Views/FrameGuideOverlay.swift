import SwiftUI
import PoseCore

/// The TikTok-safe framing box (video kind, Frame guide), drawn with `PreviewLayout` so it lands on
/// the same pixels as the preview image. Sits inside whatever mirrors the preview (`SubjectView`),
/// so it mirrors with the image — the box's right-hand dead zone (TikTok's buttons) therefore
/// appears on the subject's left, exactly as in their mirrored view. `overlayMuted` normally (visible
/// on a dark scene in every skin), `overlayAccent` once the subject is in frame.
struct FrameGuideOverlay: View {
    let hint: FrameHint?
    let imageSize: CGSize

    var body: some View {
        // Resolved on the main actor and captured by value (the renderer closure stays token-free).
        let inFrame = Theme.Palette.overlayAccent
        let idle = Theme.Palette.overlayMuted
        return Canvas { context, size in
            let rect = PreviewLayout.aspectFillRect(imageSize: imageSize, in: CGRect(origin: .zero, size: size))
            let topLeft = PreviewLayout.point(Point2(x: FrameGuide.safeMinX, y: FrameGuide.safeMinY), in: rect)
            let bottomRight = PreviewLayout.point(Point2(x: FrameGuide.safeMaxX, y: FrameGuide.safeMaxY), in: rect)
            let box = CGRect(
                x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y
            )
            context.stroke(
                Path(box),
                with: .color(hint == .inFrame ? inFrame : idle),
                lineWidth: Theme.Stroke.frameGuide
            )
        }
        .allowsHitTesting(false)
    }
}

extension FrameHint {
    /// Spoken-to-the-subject copy for the outer display (left/right already from their point of
    /// view — see `FrameGuide.hint(for:)`).
    var message: String {
        switch self {
        case .noPerson: return "Step into frame"
        case .stepBack: return "Step back"
        case .moveCloser: return "Come closer"
        case .moveLeft: return "Move left"
        case .moveRight: return "Move right"
        case .inFrame: return "In frame"
        }
    }
}
