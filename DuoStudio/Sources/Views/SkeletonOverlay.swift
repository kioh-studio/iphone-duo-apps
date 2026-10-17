import SwiftUI
import PoseCore

/// Draws the template ("ghost") skeleton and the live Vision skeleton over the preview, aligned
/// via `PreviewLayout` so both sit on the subject regardless of the preview's aspect ratio. Off
/// bones are drawn in `Theme.Palette.overlayDanger` at the thicker `offBone` width - color is never
/// the only cue, per the a11y note in the spec. Always drawn over video, so it uses the `overlay*`
/// tokens (readable in every skin).
struct SkeletonOverlay: View {
    let livePose: Pose?
    let template: Pose?
    let match: PoseMatch?
    let imageSize: CGSize

    var body: some View {
        // UNVERIFIED (2026-10-18, written on Windows): the isolation of `Canvas`'s renderer closure
        // (main actor or not) - written to compile either way.
        // Resolved here (main actor) and captured by value, so the `Canvas` renderer closure never
        // touches the `@MainActor` Theme lookups.
        let ghost = Theme.Palette.ghost
        let live = Theme.Palette.overlayAccent
        let danger = Theme.Palette.overlayDanger
        return Canvas { context, size in
            let rect = PreviewLayout.aspectFillRect(imageSize: imageSize, in: CGRect(origin: .zero, size: size))
            if let template {
                Self.draw(
                    template, into: context, rect: rect,
                    color: ghost, danger: danger, width: Theme.Stroke.ghostBone, dash: Theme.Stroke.ghostDash, offBones: []
                )
            }
            if let livePose {
                Self.draw(
                    livePose, into: context, rect: rect,
                    color: live, danger: danger, width: Theme.Stroke.liveBone, dash: [], offBones: match?.offBones ?? []
                )
            }
        }
        .allowsHitTesting(false)
    }

    nonisolated private static func draw(
        _ pose: Pose, into context: GraphicsContext, rect: CGRect,
        color: Color, danger: Color, width: CGFloat, dash: [CGFloat], offBones: Set<Bone>
    ) {
        for bone in Pose.bones {
            guard let from = pose.joints[bone.from], let to = pose.joints[bone.to] else { continue }
            var path = Path()
            path.move(to: PreviewLayout.point(from, in: rect))
            path.addLine(to: PreviewLayout.point(to, in: rect))

            let isOff = offBones.contains(bone)
            let style = StrokeStyle(lineWidth: isOff ? Theme.Stroke.offBone : width, lineCap: .round, dash: dash)
            context.stroke(path, with: .color(isOff ? danger : color), style: style)
        }

        for (_, joint) in pose.joints {
            let center = PreviewLayout.point(joint, in: rect)
            let dotRect = CGRect(
                x: center.x - Theme.Stroke.jointDot / 2, y: center.y - Theme.Stroke.jointDot / 2,
                width: Theme.Stroke.jointDot, height: Theme.Stroke.jointDot
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
    }
}
