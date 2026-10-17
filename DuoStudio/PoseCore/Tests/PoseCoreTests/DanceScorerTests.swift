import Testing
@testable import PoseCore

/// Five bones are comparable (neck-nose, neck-shoulders x2, neck-root, + left arm); `armUp`
/// swings the left arm so the pose differs from the straight-down one.
private func pose(armUp: Bool) -> Pose {
    Pose(joints: [
        .neck: Point2(x: 0.5, y: 0.3),
        .nose: Point2(x: 0.5, y: 0.2),
        .leftShoulder: Point2(x: 0.4, y: 0.3),
        .rightShoulder: Point2(x: 0.6, y: 0.3),
        .leftElbow: armUp ? Point2(x: 0.3, y: 0.2) : Point2(x: 0.4, y: 0.45),
        .leftWrist: armUp ? Point2(x: 0.2, y: 0.1) : Point2(x: 0.4, y: 0.6),
        .root: Point2(x: 0.5, y: 0.55),
    ])
}

@Suite struct DanceScorerTests {
    private let routine = DanceRoutine(
        name: "t", duration: 2,
        frames: [
            TimedPose(time: 0.0, pose: pose(armUp: false)),
            TimedPose(time: 0.5, pose: pose(armUp: true)),
            TimedPose(time: 1.0, pose: pose(armUp: true)),
        ],
        mediaFileName: "t.mp4"
    )

    @Test func lagWindowPicksTheBestFrame() {
        var scorer = DanceScorer()
        // At t = 0.6 the window is [0.25, 0.6] → only the armUp frame at 0.5. A dancer still
        // holding armUp scores 1.
        let match = scorer.record(live: pose(armUp: true), at: 0.6, routine: routine)!
        #expect(abs(match.score - 1) < 1e-9)

        // At t = 0.7 the window is [0.35, 0.7] → still only armUp at 0.5; a dancer who is
        // late (armDown) scores below 1.
        let worse = scorer.record(live: pose(armUp: false), at: 0.7, routine: routine)!
        #expect(worse.score < 1)

        // At t = 0.3 the window [0, 0.3] holds the armDown frame: the dancer who hasn't moved yet
        // still scores 1 against it — the lag tolerance.
        let lagged = scorer.record(live: pose(armUp: false), at: 0.3, routine: routine)!
        #expect(abs(lagged.score - 1) < 1e-9)
    }

    @Test func averageAndSampleCount() {
        var scorer = DanceScorer()
        #expect(scorer.average == nil)
        _ = scorer.record(live: pose(armUp: true), at: 0.6, routine: routine)   // 1.0
        let second = scorer.record(live: pose(armUp: false), at: 0.7, routine: routine)!
        #expect(scorer.sampleCount == 2)
        #expect(abs(scorer.average! - (1 + second.score) / 2) < 1e-9)
    }

    @Test func nothingComparableIsNotCounted() {
        // t = 1.5 is within duration 2 but 0.5 s past the last frame: the window [1.15, 1.5] is
        // empty and pose(at:) finds no neighbour within its gap tolerance → nil, not counted.
        var scorer = DanceScorer()
        #expect(scorer.record(live: pose(armUp: true), at: 1.5, routine: routine) == nil)
        #expect(scorer.sampleCount == 0)
    }

    @Test func resetClearsEverything() {
        var scorer = DanceScorer()
        _ = scorer.record(live: pose(armUp: true), at: 0.6, routine: routine)
        scorer.reset()
        #expect(scorer.sampleCount == 0)
        #expect(scorer.average == nil)
    }
}
