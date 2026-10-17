import Testing
@testable import PoseCore

@Suite struct PoseAlignerTests {
    private let template = Pose(joints: [
        .neck: Point2(x: 0.5, y: 0.2),
        .root: Point2(x: 0.5, y: 0.6),     // torso length 0.4
        .nose: Point2(x: 0.5, y: 0.1),
    ])

    @Test func rootMovesOntoLiveRoot() {
        let live = Pose(joints: [.neck: Point2(x: 0.3, y: 0.3), .root: Point2(x: 0.3, y: 0.7)])
        let aligned = PoseAligner.align(template, to: live)
        #expect(abs(aligned.joints[.root]!.x - 0.3) < 1e-9)
        #expect(abs(aligned.joints[.root]!.y - 0.7) < 1e-9)
    }

    @Test func torsoIsScaledToLiveTorso() {
        // Live torso 0.2 vs template 0.4 → scale 0.5; nose was 0.5 above root → 0.25 above.
        let live = Pose(joints: [.neck: Point2(x: 0.5, y: 0.4), .root: Point2(x: 0.5, y: 0.6)])
        let aligned = PoseAligner.align(template, to: live)
        #expect(abs(aligned.joints[.neck]!.y - 0.4) < 1e-9)
        #expect(abs(aligned.joints[.nose]!.y - 0.35) < 1e-9)
    }

    @Test func missingJointsLeaveTemplateUnchanged() {
        let noRoot = Pose(joints: [.neck: Point2(x: 0.5, y: 0.4)])
        #expect(PoseAligner.align(template, to: noRoot) == template)
        let noNeck = Pose(joints: [.root: Point2(x: 0.5, y: 0.6)])
        #expect(PoseAligner.align(template, to: noNeck) == template)
        let degenerate = Pose(joints: [.neck: Point2(x: 0.5, y: 0.5), .root: Point2(x: 0.5, y: 0.5)])
        #expect(PoseAligner.align(template, to: degenerate) == template)
    }
}
