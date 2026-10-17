import Testing
@testable import PoseCore

private func pose(shiftX: Double = 0, joints: [Joint: Point2]? = nil) -> Pose {
    let base: [Joint: Point2] = joints ?? [
        .neck: Point2(x: 0.5, y: 0.3),
        .nose: Point2(x: 0.5, y: 0.2),
        .leftShoulder: Point2(x: 0.4, y: 0.3),
        .rightShoulder: Point2(x: 0.6, y: 0.3),
        .root: Point2(x: 0.5, y: 0.55),
    ]
    return Pose(joints: base.mapValues { Point2(x: $0.x + shiftX, y: $0.y) })
}

@Suite struct DanceRoutineTests {
    private func routine(frames: [TimedPose], duration: Double = 1, isMirrored: Bool = false) -> DanceRoutine {
        DanceRoutine(name: "t", duration: duration, frames: frames, isMirrored: isMirrored, mediaFileName: "t.mp4")
    }

    @Test func interpolatesMidpointBetweenFrames() {
        let r = routine(frames: [TimedPose(time: 0, pose: pose()), TimedPose(time: 0.5, pose: pose(shiftX: 0.2))])
        let mid = r.pose(at: 0.25)!
        #expect(abs(mid.joints[.nose]!.x - 0.6) < 1e-9)
        #expect(abs(mid.joints[.nose]!.y - 0.2) < 1e-9)
    }

    @Test func nilOutsideRangeOrWithoutFrames() {
        let r = routine(frames: [TimedPose(time: 0, pose: pose()), TimedPose(time: 1, pose: pose())])
        #expect(r.pose(at: -0.01) == nil)
        #expect(r.pose(at: 1.01) == nil)
        #expect(r.pose(at: 0.5) != nil)
        #expect(routine(frames: []).pose(at: 0.5) == nil)
    }

    @Test func mirroredFlipsJoints() {
        let source = pose()
        let r = routine(frames: [TimedPose(time: 0, pose: source), TimedPose(time: 1, pose: source)], isMirrored: true)
        let result = r.pose(at: 0.5)!
        #expect(abs(result.joints[.rightShoulder]!.x - (1 - source.joints[.leftShoulder]!.x)) < 1e-9)
        #expect(abs(result.joints[.nose]!.x - 0.5) < 1e-9)
    }

    @Test func nilFrameGapUsesNearNeighbourOnlyWithinTolerance() {
        // Gap 0.2...0.8: t = 0.3 is 0.1 s from the real frame at 0.2 → use it as-is.
        // t = 0.5 is 0.3 s from both neighbours (> 0.25) → nil.
        let r = routine(frames: [
            TimedPose(time: 0.2, pose: pose()),
            TimedPose(time: 0.5, pose: nil),
            TimedPose(time: 0.8, pose: pose(shiftX: 0.2)),
        ])
        let near = r.pose(at: 0.3)!
        #expect(abs(near.joints[.nose]!.x - 0.5) < 1e-9)   // not interpolated toward the other frame
        #expect(r.pose(at: 0.5) == nil)
    }

    @Test func posesInWindowSkipsNilAndRespectsBounds() {
        let r = routine(frames: [
            TimedPose(time: 0.0, pose: pose()),
            TimedPose(time: 0.1, pose: nil),
            TimedPose(time: 0.2, pose: pose(shiftX: 0.1)),
            TimedPose(time: 0.3, pose: pose(shiftX: 0.2)),
            TimedPose(time: 0.4, pose: pose(shiftX: 0.3)),
        ])
        #expect(r.poses(in: 0.05...0.3).count == 2)   // 0.2 and 0.3; the nil at 0.1 is skipped
        #expect(r.poses(in: 0.5...0.9).isEmpty)
    }

    @Test func posesInWindowIsMirroredWhenRoutineIs() {
        let r = routine(frames: [TimedPose(time: 0, pose: pose(shiftX: 0.1))], isMirrored: true)
        let result = r.poses(in: 0...0).first!
        #expect(abs(result.joints[.nose]!.x - (1 - 0.6)) < 1e-9)
    }
}
