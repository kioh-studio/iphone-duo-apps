import Testing
@testable import PoseCore

private let wrist = Point2(x: 0.5, y: 0.5)
private let middlePIP = Point2(x: 0.5, y: 0.35) // distance to wrist == 0.15 == handSize

// "Extended" tip/pip pairs: distance(wrist, tip) > 1.25 * distance(wrist, pip).
private let indexPIPUp = Point2(x: 0.45, y: 0.35)
private let indexTipUp = Point2(x: 0.40, y: 0.20) // extended, above the wrist (pointUp)
private let indexPIPDown = Point2(x: 0.45, y: 0.65)
private let indexTipDown = Point2(x: 0.40, y: 0.80) // extended, below the wrist (pointDown)
private let middleTipExtended = Point2(x: 0.5, y: 0.20)
private let ringPIP = Point2(x: 0.55, y: 0.35)
private let ringTipExtended = Point2(x: 0.60, y: 0.20)
private let littlePIP = Point2(x: 0.58, y: 0.37)
private let littleTipExtended = Point2(x: 0.66, y: 0.24)

// "Curled" tip/pip pairs: tip stays close to the wrist (not extended).
private let indexTipCurled = Point2(x: 0.46, y: 0.40)
private let middleTipCurled = Point2(x: 0.5, y: 0.40)
private let ringTipCurled = Point2(x: 0.54, y: 0.40)
private let littleTipCurled = Point2(x: 0.57, y: 0.42)

private func hand(
    indexPIP: Point2, indexTip: Point2,
    middleTip: Point2, ringTip: Point2, littleTip: Point2,
    thumbTip: Point2
) -> [HandJoint: Point2] {
    [
        .wrist: wrist,
        .middlePIP: middlePIP,
        .indexPIP: indexPIP, .indexTip: indexTip,
        .middleTip: middleTip,
        .ringPIP: ringPIP, .ringTip: ringTip,
        .littlePIP: littlePIP, .littleTip: littleTip,
        .thumbTip: thumbTip,
    ]
}

@Suite struct GestureRecognizerTests {
    // MARK: HandClassifier

    @Test func classifiesOpenPalm() {
        let openHand = hand(
            indexPIP: indexPIPUp, indexTip: indexTipUp,
            middleTip: middleTipExtended, ringTip: ringTipExtended, littleTip: littleTipExtended,
            thumbTip: Point2(x: 0.35, y: 0.55)
        )
        #expect(HandClassifier.classify(openHand) == .openPalm)
    }

    @Test func classifiesFist() {
        let fistHand = hand(
            indexPIP: indexPIPUp, indexTip: indexTipCurled,
            middleTip: middleTipCurled, ringTip: ringTipCurled, littleTip: littleTipCurled,
            thumbTip: Point2(x: 0.30, y: 0.55)
        )
        #expect(HandClassifier.classify(fistHand) == .fist)
    }

    @Test func classifiesPinch() {
        let pinchHand = hand(
            indexPIP: indexPIPUp, indexTip: Point2(x: 0.50, y: 0.47),
            middleTip: middleTipExtended, ringTip: ringTipExtended, littleTip: littleTipExtended,
            thumbTip: Point2(x: 0.49, y: 0.48)
        )
        #expect(HandClassifier.classify(pinchHand) == .pinch)
    }

    @Test func classifiesPointUp() {
        let pointUpHand = hand(
            indexPIP: indexPIPUp, indexTip: indexTipUp,
            middleTip: middleTipCurled, ringTip: ringTipCurled, littleTip: littleTipCurled,
            thumbTip: Point2(x: 0.35, y: 0.55)
        )
        #expect(HandClassifier.classify(pointUpHand) == .pointUp)
    }

    @Test func classifiesPointDown() {
        let pointDownHand = hand(
            indexPIP: indexPIPDown, indexTip: indexTipDown,
            middleTip: middleTipCurled, ringTip: ringTipCurled, littleTip: littleTipCurled,
            thumbTip: Point2(x: 0.35, y: 0.55)
        )
        #expect(HandClassifier.classify(pointDownHand) == .pointDown)
    }

    // MARK: GestureRecognizer.feed

    // Wrist coordinates are in the upright, un-mirrored camera image, but the subject only ever
    // watches a mirrored view — so a swipe towards the subject's right moves the wrist to
    // *smaller* x here (0.70 → 0.50), and that's what should emit `.nextFilter`.
    @Test func swipeTowardsSubjectsRightEmitsNextFilterOnceThenCooldown() {
        var recognizer = GestureRecognizer()
        #expect(recognizer.feed(HandSample(shape: .openPalm, wrist: Point2(x: 0.70, y: 0.5), pinchDistance: nil, time: 0.0)) == nil)
        #expect(recognizer.feed(HandSample(shape: .openPalm, wrist: Point2(x: 0.50, y: 0.5), pinchDistance: nil, time: 0.2)) == .nextFilter)
        // Still within the 1.0 s cooldown: no second event even though the hand kept moving.
        #expect(recognizer.feed(HandSample(shape: .openPalm, wrist: Point2(x: 0.30, y: 0.5), pinchDistance: nil, time: 0.3)) == nil)
        #expect(recognizer.feed(HandSample(shape: .openPalm, wrist: Point2(x: 0.30, y: 0.5), pinchDistance: nil, time: 1.3)) == nil)
    }

    @Test func swipeTowardsSubjectsLeftEmitsPreviousFilter() {
        var recognizer = GestureRecognizer()
        #expect(recognizer.feed(HandSample(shape: .openPalm, wrist: Point2(x: 0.30, y: 0.5), pinchDistance: nil, time: 0.0)) == nil)
        #expect(recognizer.feed(HandSample(shape: .openPalm, wrist: Point2(x: 0.50, y: 0.5), pinchDistance: nil, time: 0.2)) == .previousFilter)
    }

    @Test func pinchSpreadingEmitsZoomGreaterThanOne() {
        var recognizer = GestureRecognizer()
        #expect(recognizer.feed(HandSample(shape: .pinch, wrist: nil, pinchDistance: 0.10, time: 0.0)) == nil)
        let event = recognizer.feed(HandSample(shape: .pinch, wrist: nil, pinchDistance: 0.14, time: 0.1))
        guard case .zoom(let factor) = event else {
            Issue.record("expected a zoom event, got \(String(describing: event))")
            return
        }
        #expect(factor > 1)
    }

    // The baseline only moves when a zoom actually fires, not on every frame — so each of these
    // samples fires against the distance left by the *previous fire*, not the previous frame.
    @Test func slowSteadySpreadKeepsFiringAgainstLastFiredBaseline() {
        var recognizer = GestureRecognizer()
        let samples: [(time: TimeInterval, distance: Double)] = [
            (0.0, 0.10), (0.1, 0.11), (0.2, 0.12), (0.3, 0.13),
        ]
        var factors: [Double] = []
        for sample in samples {
            if case .zoom(let factor)? = recognizer.feed(
                HandSample(shape: .pinch, wrist: nil, pinchDistance: sample.distance, time: sample.time)
            ) {
                factors.append(factor)
            }
        }
        #expect(factors.count == 3)
        #expect(abs(factors[0] - 1.10) < 1e-9) // 0.11 / 0.10
        #expect(abs(factors[1] - 0.12 / 0.11) < 1e-9)
        #expect(abs(factors[2] - 0.13 / 0.12) < 1e-9)
    }

    // A pinch too slow to clear 3% in any single frame (0.100 → 0.102 is only +2%) must still fire
    // once the drift from the *fixed* baseline clears 3% (0.104 / 0.100 = +4%) — the bug this
    // guards against reset the baseline to 0.102 every frame regardless of whether a zoom fired,
    // so the drift never accumulated and no event was ever emitted.
    @Test func slowSpreadBelowPerFrameThresholdFiresOnceBaselineDriftExceedsIt() {
        var recognizer = GestureRecognizer()
        #expect(recognizer.feed(HandSample(shape: .pinch, wrist: nil, pinchDistance: 0.100, time: 0.0)) == nil)
        #expect(recognizer.feed(HandSample(shape: .pinch, wrist: nil, pinchDistance: 0.102, time: 0.1)) == nil)
        guard case .zoom(let factor)? = recognizer.feed(HandSample(shape: .pinch, wrist: nil, pinchDistance: 0.104, time: 0.2)) else {
            Issue.record("expected a zoom event at t=0.2")
            return
        }
        #expect(abs(factor - 1.04) < 1e-9)
    }

    @Test func fistHeldPointNineSecondsEmitsNextParameterOnce() {
        var recognizer = GestureRecognizer()
        var events: [GestureEvent] = []
        for t in [0.0, 0.3, 0.6, 0.9] {
            if let event = recognizer.feed(HandSample(shape: .fist, wrist: nil, pinchDistance: nil, time: t)) {
                events.append(event)
            }
        }
        #expect(events == [.nextParameter])
    }

    @Test func pointUpHeldOnePointFourSecondsFiresThreeTimes() {
        var recognizer = GestureRecognizer()
        var events: [GestureEvent] = []
        for t in [0.0, 0.5, 0.9, 1.3, 1.4] {
            if let event = recognizer.feed(HandSample(shape: .pointUp, wrist: nil, pinchDistance: nil, time: t)) {
                events.append(event)
            }
        }
        #expect(events == [.adjust(step: 1), .adjust(step: 1), .adjust(step: 1)])
    }
}
