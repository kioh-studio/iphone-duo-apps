import Testing
@testable import CaptionCore

@Suite struct OKLCHTests {
    @Test func whiteAtFullLightnessZeroChroma() {
        let (r, g, b) = OKLCH.linearSRGB(l: 1, c: 0, h: 0)
        #expect(abs(r - 1) < 0.0001)
        #expect(abs(g - 1) < 0.0001)
        #expect(abs(b - 1) < 0.0001)
    }

    @Test func blackAtZeroLightness() {
        let (r, g, b) = OKLCH.linearSRGB(l: 0, c: 0, h: 0)
        #expect(r == 0)
        #expect(g == 0)
        #expect(b == 0)
    }

    @Test func approximatesPureRed() {
        let (r, g, b) = OKLCH.linearSRGB(l: 0.6279554, c: 0.2576833, h: 29.2338851)
        #expect(abs(r - 1) < 0.002)
        #expect(abs(g - 0) < 0.002)
        #expect(abs(b - 0) < 0.002)
    }
}
