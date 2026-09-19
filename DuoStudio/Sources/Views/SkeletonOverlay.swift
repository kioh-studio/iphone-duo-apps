import SwiftUI
import PoseCore

/// Draws the template ("ghost") skeleton and the live Vision skeleton over the preview, aligned
/// via `PreviewLayout` so both sit on the subject regardless of the preview's aspect ratio. Off
/// bones are drawn in `Theme.Palette.danger` at the thicker `offBone` width — color is never the
/// only cue, per the a11y note in the spec.
struct SkeletonOverlay: View {
    let livePose: Pose?
    let template: Pose?
    let match: PoseMatch?
    let imageSize: CGSize

    var body: some View {
        Canvas { context, size in
            let rect = PreviewLayout.aspectFillRect(imageSize: imageSize, in: CGRect(origin: .zero, size: size))
            if let template {
                draw(
                    template, into: context, rect: rect,
                    color: Theme.Palette.ghost, width: Theme.Stroke.ghostBone, dash: Theme.Stroke.ghostDash, offBones: []
                )
            }
            if let livePose {
                draw(
                    livePose, into: context, rect: rect,
                    color: Theme.Palette.accent, width: Theme.Stroke.liveBone, dash: [], offBones: match?.offBones ?? []
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(
        _ pose: Pose, into context: GraphicsContext, rect: CGRect,
        color: Color, width: CGFloat, dash: [CGFloat], offBones: Set<Bone>
    ) {
        for bone in Pose.bones {
            guard let from = pose.joints[bone.from], let to = pose.joints[bone.to] else { continue }
            var path = Path()
            path.move(to: PreviewLayout.point(from, in: rect))
            path.addLine(to: PreviewLayout.point(to, in: rect))

            let isOff = offBones.contains(bone)
            let style = StrokeStyle(lineWidth: isOff ? Theme.Stroke.offBone : width, lineCap: .round, dash: dash)
            context.stroke(path, with: .color(isOff ? Theme.Palette.danger : color), style: style)
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
