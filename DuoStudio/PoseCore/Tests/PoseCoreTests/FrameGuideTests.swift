import Testing
@testable import PoseCore

/// A six-joint body whose bounding box is exactly the given extents.
private func body(minX: Double, maxX: Double, minY: Double, maxY: Double) -> Pose {
    let midX = (minX + maxX) / 2
    let midY = (minY + maxY) / 2
    return Pose(joints: [
        .nose: Point2(x: midX, y: minY),
        .leftShoulder: Point2(x: minX, y: midY),
        .rightShoulder: Point2(x: maxX, y: midY),
        .root: Point2(x: midX, y: midY),
        .leftAnkle: Point2(x: minX, y: maxY),
        .rightAnkle: Point2(x: maxX, y: maxY),
    ])
}

@Suite struct FrameGuideTests {
    @Test func noPersonWhenNilOrTooFewJoints() {
        #expect(FrameGuide.hint(for: nil) == .noPerson)
        let few = Pose(joints: [.nose: Point2(x: 0.5, y: 0.2), .neck: Point2(x: 0.5, y: 0.3)])
        #expect(FrameGuide.hint(for: few) == .noPerson)
    }

    @Test func stepBackWhenTallerThanSafeBand() {
        #expect(FrameGuide.hint(for: body(minX: 0.3, maxX: 0.6, minY: 0.05, maxY: 0.95)) == .stepBack)
    }

    @Test func stepBackWhenOnlyFeetCrossBottom() {
        #expect(FrameGuide.hint(for: body(minX: 0.3, maxX: 0.6, minY: 0.3, maxY: 0.9)) == .stepBack)
    }

    @Test func stepBackWhenOnlyHeadCrossesTop() {
        #expect(FrameGuide.hint(for: body(minX: 0.3, maxX: 0.6, minY: 0.02, maxY: 0.6)) == .stepBack)
    }

    @Test func moveCloserWhenBodyIsSmall() {
        #expect(FrameGuide.hint(for: body(minX: 0.4, maxX: 0.5, minY: 0.3, maxY: 0.5)) == .moveCloser)
    }

    @Test func moveLeftWhenLeavingImageLeftEdge() {
        // Image-left edge = the subject's right side; they fix it by stepping to their own left.
        #expect(FrameGuide.hint(for: body(minX: 0.02, maxX: 0.4, minY: 0.2, maxY: 0.7)) == .moveLeft)
    }

    @Test func moveRightWhenLeavingImageRightEdge() {
        #expect(FrameGuide.hint(for: body(minX: 0.5, maxX: 0.9, minY: 0.2, maxY: 0.7)) == .moveRight)
    }

    @Test func inFrameWhenInsideSafeBox() {
        #expect(FrameGuide.hint(for: body(minX: 0.3, maxX: 0.6, minY: 0.15, maxY: 0.75)) == .inFrame)
    }
}
