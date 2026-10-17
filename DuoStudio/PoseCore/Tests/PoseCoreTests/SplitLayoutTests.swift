import Testing
@testable import PoseCore

@Suite struct SplitLayoutTests {
    @Test func halvesTileTheCanvas() {
        #expect(SplitLayout.guest.y == SplitLayout.interviewer.y + SplitLayout.interviewer.height)
        #expect(SplitLayout.guest.width == 1080)
        #expect(SplitLayout.guest.height == 960)
    }

    @Test func portraitSourceIsScaledToWidthAndCroppedVertically() {
        // 1080x1920 into 1080x960: scale 1, 960 rows overflow, centred (offset -480 below the rect).
        let p = SplitLayout.aspectFill(sourceWidth: 1080, sourceHeight: 1920, into: SplitLayout.interviewer)
        #expect(p.scale == 1)
        #expect(p.tx == 0)
        #expect(p.ty == -480)
    }

    @Test func landscapeSourceIsScaledToHeightAndCroppedHorizontally() {
        // 1920x1080 into 1080x960: height governs (960/1080), width overflows and is centred.
        let p = SplitLayout.aspectFill(sourceWidth: 1920, sourceHeight: 1080, into: SplitLayout.guest)
        #expect(abs(p.scale - 960.0 / 1080.0) < 1e-9)
        #expect(abs(p.tx - (540 - 1920 * p.scale / 2)) < 1e-9)
        #expect(abs(p.ty - 960) < 1e-9)
    }

    @Test func placedSourceAlwaysCoversTarget() {
        for (w, h) in [(640.0, 480.0), (1080.0, 1920.0), (3000.0, 500.0), (500.0, 3000.0)] {
            let p = SplitLayout.aspectFill(sourceWidth: w, sourceHeight: h, into: SplitLayout.guest)
            #expect(w * p.scale >= SplitLayout.guest.width - 1e-9)
            #expect(h * p.scale >= SplitLayout.guest.height - 1e-9)
            #expect(p.tx <= SplitLayout.guest.x + 1e-9)
            #expect(p.ty <= SplitLayout.guest.y + 1e-9)
            #expect(p.tx + w * p.scale >= SplitLayout.guest.x + SplitLayout.guest.width - 1e-9)
            #expect(p.ty + h * p.scale >= SplitLayout.guest.y + SplitLayout.guest.height - 1e-9)
        }
    }

    @Test func degenerateSourceDoesNotCrash() {
        let p = SplitLayout.aspectFill(sourceWidth: 0, sourceHeight: 0, into: SplitLayout.guest)
        #expect(p.scale == 1)
    }
}
