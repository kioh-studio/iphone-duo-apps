import Foundation

public enum FrameHint: String, Hashable, Sendable {
    case noPerson, stepBack, moveCloser, moveLeft, moveRight, inFrame
}

/// TikTok-safe framing advice from a live pose.
public enum FrameGuide {
    /// The safe region in the upright, UN-mirrored camera image (normalized, top-left origin):
    /// clear of TikTok's right-side buttons and bottom caption area in the finished video.
    public static let safeMinX = 0.08, safeMaxX = 0.82, safeMinY = 0.08, safeMaxY = 0.82
    /// Fewer joints than this is too little body to judge.
    public static let minimumJoints = 6
    /// Body bounding-box height below this (fraction of the image) means the subject is too far away.
    public static let minimumHeight = 0.35

    /// Priority: `noPerson` (nil or < `minimumJoints`) → `stepBack` → `moveCloser` → horizontal →
    /// `inFrame`.
    ///
    /// `stepBack`: the body's bounding box is taller than the safe band, or crosses the safe
    /// region's top and/or bottom edge (a head or feet cut off needs distance, not a sidestep), or
    /// spans past BOTH side edges (too wide for the box).
    ///
    /// Left/right is from the SUBJECT's point of view. The subject faces the camera, so their own
    /// left is +x in the un-mirrored camera image, and they watch a mirrored view (`SubjectView`
    /// mirrors in both capture modes) in which their left is also screen-left. A body poking out of
    /// the image's left edge (`minX < safeMinX`) is therefore their right side leaving frame, and
    /// they fix it by moving toward image +x — their own left → `.moveLeft`. Likewise
    /// `maxX > safeMaxX` → `.moveRight`. (Same reasoning as `GestureRecognizer`'s swipe direction.)
    public static func hint(for pose: Pose?) -> FrameHint {
        guard let pose, pose.joints.count >= minimumJoints else { return .noPerson }

        let xs = pose.joints.values.map(\.x)
        let ys = pose.joints.values.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return .noPerson
        }

        let height = maxY - minY
        let crossesTop = minY < safeMinY
        let crossesBottom = maxY > safeMaxY
        if height > safeMaxY - safeMinY || crossesTop || crossesBottom
            || (minX < safeMinX && maxX > safeMaxX) {
            return .stepBack
        }
        if height < minimumHeight { return .moveCloser }
        if minX < safeMinX { return .moveLeft }
        if maxX > safeMaxX { return .moveRight }
        return .inFrame
    }
}
