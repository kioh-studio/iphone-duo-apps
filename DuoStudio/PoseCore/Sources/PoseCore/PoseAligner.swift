import Foundation

public enum PoseAligner {
    /// Moves and scales `template` so its root sits on `live`'s root and its torso length
    /// (neck→root distance) equals live's. Returns `template` unchanged if either pose lacks neck or
    /// root, or either torso length is ~0. Used only to *draw* the dance ghost over the dancer —
    /// matching is already translation/scale invariant.
    public static func align(_ template: Pose, to live: Pose) -> Pose {
        guard
            let liveNeck = live.joints[.neck], let liveRoot = live.joints[.root],
            let templateNeck = template.joints[.neck], let templateRoot = template.joints[.root]
        else { return template }

        let liveTorso = distance(liveNeck, liveRoot)
        let templateTorso = distance(templateNeck, templateRoot)
        guard liveTorso > 1e-6, templateTorso > 1e-6 else { return template }

        let scale = liveTorso / templateTorso
        var joints: [Joint: Point2] = [:]
        joints.reserveCapacity(template.joints.count)
        for (joint, point) in template.joints {
            joints[joint] = Point2(
                x: liveRoot.x + (point.x - templateRoot.x) * scale,
                y: liveRoot.y + (point.y - templateRoot.y) * scale
            )
        }
        return Pose(joints: joints)
    }

    private static func distance(_ a: Point2, _ b: Point2) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
