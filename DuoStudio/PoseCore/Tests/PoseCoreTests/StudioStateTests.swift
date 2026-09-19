import Testing
@testable import PoseCore

@Suite struct StudioStateTests {
    @Test func filterWrapsForwardPastLastCase() {
        var state = StudioState()
        state.filter = .transfer // last case of StudioFilter.allCases
        state.apply(.nextFilter)
        #expect(state.filter == .none) // wraps to the first case
    }

    @Test func filterWrapsBackwardPastFirstCase() {
        var state = StudioState()
        state.filter = .none // first case
        state.apply(.previousFilter)
        #expect(state.filter == .transfer) // wraps to the last case
    }

    @Test func zoomMultipliesAndClampsToRange() {
        var state = StudioState()
        state.apply(.zoom(factor: 10))
        #expect(abs(state.outerZoom - 4) < 0.0001) // clamped to the 1...4 max

        state.apply(.zoom(factor: 0.1))
        #expect(abs(state.outerZoom - 1) < 0.0001) // clamped to the 1...4 min
    }

    @Test func nextParameterCyclesThroughAllCases() {
        var state = StudioState()
        #expect(state.selectedParameter == .exposure)
        state.apply(.nextParameter)
        #expect(state.selectedParameter == .contrast)
        state.apply(.nextParameter)
        #expect(state.selectedParameter == .warmth)
        state.apply(.nextParameter)
        #expect(state.selectedParameter == .exposure)
    }

    @Test func adjustStepsSelectedParameterAndClamps() {
        var state = StudioState()
        state.apply(.adjust(step: 1))
        #expect(abs(state.adjustments.exposureEV - 0.3) < 0.0001)

        // Clamp at the top of the exposure range.
        state.apply(.adjust(step: 100))
        #expect(abs(state.adjustments.exposureEV - 2) < 0.0001)

        // Clamp at the bottom.
        state.apply(.adjust(step: -100))
        #expect(abs(state.adjustments.exposureEV - (-2)) < 0.0001)

        state.selectedParameter = .warmth
        state.apply(.adjust(step: -1))
        #expect(abs(state.adjustments.warmthKelvin - 5250) < 0.0001)
    }

    @Test func adjustmentsFormattedReadouts() {
        var adjustments = Adjustments()
        #expect(adjustments.formatted(.exposure) == "+0.0 EV")
        #expect(adjustments.formatted(.contrast) == "1.00×")
        #expect(adjustments.formatted(.warmth) == "5500 K")

        adjustments.step(.exposure, by: 1)
        #expect(adjustments.formatted(.exposure) == "+0.3 EV")
    }
}
