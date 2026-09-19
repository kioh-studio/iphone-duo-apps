import Testing
@testable import PoseCore

/// A hand-picked 15-joint pose with simple bone vectors, used as the baseline for match tests.
private func referencePose() -> Pose {
    Pose(joints: [
        .neck: Point2(x: 0.5, y: 0.3),
        .nose: Point2(x: 0.5, y: 0.2),
        .leftShoulder: Point2(x: 0.4, y: 0.3),
        .rightShoulder: Point2(x: 0.6, y: 0.3),
        .leftElbow: Point2(x: 0.3, y: 0.45),
        .rightElbow: Point2(x: 0.7, y: 0.45),
        .leftWrist: Point2(x: 0.25, y: 0.6),
        .rightWrist: Point2(x: 0.75, y: 0.6),
        .root: Point2(x: 0.5, y: 0.55),
        .leftHip: Point2(x: 0.45, y: 0.56),
        .rightHip: Point2(x: 0.55, y: 0.56),
        .leftKnee: Point2(x: 0.43, y: 0.72),
        .rightKnee: Point2(x: 0.57, y: 0.72),
        .leftAnkle: Point2(x: 0.42, y: 0.88),
        .rightAnkle: Point2(x: 0.58, y: 0.88),
    ])
}

@Suite struct PoseMatcherTests {
    @Test func identicalPosesScoreOneNoOffBones() {
        let pose = referencePose()
        let match = PoseMatcher.match(live: pose, template: pose)!
        #expect(abs(match.score - 1) < 0.0001)
        #expect(match.offBones.isEmpty)
    }

    @Test func scaledAndTranslatedCopyStillScoresOne() {
        let template = referencePose()
        var scaledJoints: [Joint: Point2] = [:]
        for (joint, point) in template.joints {
            scaledJoints[joint] = Point2(x: point.x * 1.2 + 0.05, y: point.y * 1.2 - 0.02)
        }
        let live = Pose(joints: scaledJoints)

        let match = PoseMatcher.match(live: live, template: template)!
        #expect(abs(match.score - 1) < 0.0001)
        #expect(match.offBones.isEmpty)
    }

    @Test func rotatedForearmIsOffBoneAndLowersScore() {
        let template = referencePose()
        var liveJoints = template.joints
        // Rotate the rightElbow→rightWrist bone vector (0.05, 0.15) by 90° to (-0.15, 0.05):
        // exactly orthogonal to the template's vector (dot product 0), so d == 90°.
        liveJoints[.rightWrist] = Point2(x: 0.7 - 0.15, y: 0.45 + 0.05)
        let live = Pose(joints: liveJoints)

        let match = PoseMatcher.match(live: live, template: template)!
        #expect(match.offBones == [Bone(from: .rightElbow, to: .rightWrist)])
        // 13 of 14 bones score 1, the rotated one scores 0: (13 + 0) / 14.
        #expect(abs(match.score - 13.0 / 14.0) < 0.0001)
    }

    @Test func fewerThanFourComparableBonesReturnsNil() {
        let live = Pose(joints: [
            .neck: Point2(x: 0.5, y: 0.3),
            .nose: Point2(x: 0.5, y: 0.2),
            .leftShoulder: Point2(x: 0.4, y: 0.3),
        ])
        let template = Pose(joints: [
            .neck: Point2(x: 0.5, y: 0.4),
            .nose: Point2(x: 0.5, y: 0.25),
            .leftShoulder: Point2(x: 0.35, y: 0.4),
        ])
        // Only neck-nose and neck-leftShoulder have both endpoints in both poses: 2 comparable
        // bones, below the 4-bone minimum.
        #expect(PoseMatcher.match(live: live, template: template) == nil)
    }

    @Test func mirroredTwiceIsOriginal() {
        let pose = referencePose()
        let mirroredOnce = PoseMatcher.mirrored(pose)
        // Left/right swapped, x flipped.
        #expect(mirroredOnce.joints[.rightShoulder]!.x == pose.joints[.leftShoulder]!.x)
        #expect(abs(mirroredOnce.joints[.leftShoulder]!.x - (1 - pose.joints[.rightShoulder]!.x)) < 1e-9)

        let mirroredTwice = PoseMatcher.mirrored(mirroredOnce)
        #expect(Set(mirroredTwice.joints.keys) == Set(pose.joints.keys))
        for (joint, point) in pose.joints {
            let roundTripped = mirroredTwice.joints[joint]!
            #expect(abs(roundTripped.x - point.x) < 1e-9)
            #expect(abs(roundTripped.y - point.y) < 1e-9)
        }
    }
}
