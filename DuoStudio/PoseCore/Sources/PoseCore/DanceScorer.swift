import Foundation

/// Running average of how well a dancer follows a `DanceRoutine`.
public struct DanceScorer: Hashable, Sendable {
    /// Dancers react after the beat, so the live pose at `t` is compared against the routine's
    /// frames in `[t - lagTolerance, t]` and the best one counts.
    public static let lagTolerance: Double = 0.35

    public private(set) var sampleCount = 0
    private var total = 0.0

    public init() {}

    /// Best `PoseMatcher.match` of `live` over the routine's poses in `max(0, t - lagTolerance)...t`
    /// (falling back to `routine.pose(at: t)` if that window holds no pose). The best score is added
    /// to the running total and its `PoseMatch` returned; `nil` (and not counted) if nothing was
    /// comparable.
    public mutating func record(live: Pose, at t: Double, routine: DanceRoutine) -> PoseMatch? {
        let upper = max(0, t)
        var candidates = routine.poses(in: max(0, upper - Self.lagTolerance)...upper)
        if candidates.isEmpty, let single = routine.pose(at: t) {
            candidates = [single]
        }

        var best: PoseMatch?
        for candidate in candidates {
            guard let match = PoseMatcher.match(live: live, template: candidate) else { continue }
            if best == nil || match.score > best!.score { best = match }
        }
        guard let best else { return nil }
        total += best.score
        sampleCount += 1
        return best
    }

    /// Mean of the recorded scores (0...1), `nil` if none.
    public var average: Double? {
        sampleCount > 0 ? total / Double(sampleCount) : nil
    }

    public mutating func reset() {
        sampleCount = 0
        total = 0
    }
}
