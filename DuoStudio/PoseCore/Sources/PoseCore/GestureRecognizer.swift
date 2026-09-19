import Foundation

/// A photographer-facing control the model can currently adjust with a held hand shape.
public enum StudioParameter: String, CaseIterable, Sendable {
    case exposure, contrast, warmth
}

/// A control action decoded from a sequence of hand samples.
public enum GestureEvent: Hashable, Sendable {
    case nextFilter, previousFilter, zoom(factor: Double), nextParameter, adjust(step: Int)
}

/// One classified hand observation for one processed frame (~10 Hz).
public struct HandSample: Sendable {
    public var shape: HandShape?
    public var wrist: Point2?
    public var pinchDistance: Double?
    public var time: TimeInterval

    public init(shape: HandShape?, wrist: Point2?, pinchDistance: Double?, time: TimeInterval) {
        self.shape = shape
        self.wrist = wrist
        self.pinchDistance = pinchDistance
        self.time = time
    }
}

/// Turns a stream of `HandSample`s into discrete `GestureEvent`s. Feed one sample per processed
/// frame, in non-decreasing `time` order.
///
/// Rules (see PoseCore spec):
/// - Swipe: while `shape == .openPalm`, if `wrist.x` moves by more than 0.15 within a 0.6 s window
///   → `.nextFilter` or `.previousFilter`. `wrist` is reported in the upright, un-mirrored camera
///   image (see `Point2`), but the subject only ever watches a mirrored view (`SubjectView`
///   mirrors in both capture modes) — so a swipe to the subject's right moves the wrist towards
///   *smaller* x here. `dx < -0.15` → `.nextFilter`, `dx > 0.15` → `.previousFilter`. Then a 1.0 s
///   cooldown during which no further swipe fires.
/// - Pinch zoom: while `shape == .pinch` for consecutive samples, emit `.zoom(factor:)` — the
///   ratio of this sample's `pinchDistance` to a baseline — whenever `|factor - 1| > 0.03`. The
///   baseline is set on the first pinch sample and only moves to the current sample's distance
///   when a zoom event actually fires (not on every frame), so a slow, steady pinch that never
///   moves more than 3% frame-to-frame still accumulates towards a fire instead of resetting its
///   baseline every frame. The baseline resets whenever pinch ends.
/// - Fist held ≥ 0.8 s → `.nextParameter` once; the shape must stop being `.fist` before it can
///   fire again.
/// - pointUp/pointDown held ≥ 0.5 s → `.adjust(step: +1 / -1)`, then repeats every 0.4 s while
///   held continuously.
/// - A `nil` shape, or switching to a different shape, resets the hold timers belonging to every
///   *other* shape (the swipe cooldown is not a hold timer and is unaffected).
public struct GestureRecognizer: Sendable {
    private var swipeAnchor: (x: Double, time: TimeInterval)?
    private var swipeCooldownUntil: TimeInterval = -.infinity

    private var lastPinchDistance: Double?

    private var fistStart: TimeInterval?
    private var fistFired = false

    private var pointShape: HandShape?
    private var pointStart: TimeInterval?
    private var lastPointFire: TimeInterval?

    public init() {}

    public mutating func feed(_ sample: HandSample) -> GestureEvent? {
        guard let shape = sample.shape else {
            resetHoldTimers()
            return nil
        }

        if shape != .openPalm { swipeAnchor = nil }
        if shape != .pinch { lastPinchDistance = nil }
        if shape != .fist {
            fistStart = nil
            fistFired = false
        }
        if shape != .pointUp && shape != .pointDown {
            pointShape = nil
            pointStart = nil
            lastPointFire = nil
        }

        switch shape {
        case .openPalm: return feedSwipe(sample)
        case .pinch: return feedPinch(sample)
        case .fist: return feedFist(sample)
        case .pointUp, .pointDown: return feedPoint(sample, shape: shape)
        }
    }

    private mutating func feedSwipe(_ sample: HandSample) -> GestureEvent? {
        guard let wrist = sample.wrist else {
            swipeAnchor = nil
            return nil
        }

        guard sample.time >= swipeCooldownUntil else {
            swipeAnchor = nil
            return nil
        }

        guard let anchor = swipeAnchor else {
            swipeAnchor = (wrist.x, sample.time)
            return nil
        }

        guard sample.time - anchor.time <= 0.6 else {
            swipeAnchor = (wrist.x, sample.time)
            return nil
        }

        let dx = wrist.x - anchor.x
        guard abs(dx) > 0.15 else { return nil }

        swipeCooldownUntil = sample.time + 1.0
        swipeAnchor = nil
        // Mirrored subject view: smaller x = towards the subject's right = next filter.
        return dx < 0 ? .nextFilter : .previousFilter
    }

    private mutating func feedPinch(_ sample: HandSample) -> GestureEvent? {
        guard let distance = sample.pinchDistance else {
            lastPinchDistance = nil
            return nil
        }

        guard let baseline = lastPinchDistance, baseline > 0 else {
            lastPinchDistance = distance
            return nil
        }

        let factor = distance / baseline
        guard abs(factor - 1) > 0.03 else { return nil }
        // Only move the baseline when a zoom actually fires — not every frame — so a slow, steady
        // pinch still accumulates its drift instead of resetting each frame.
        lastPinchDistance = distance
        return .zoom(factor: factor)
    }

    private mutating func feedFist(_ sample: HandSample) -> GestureEvent? {
        if fistStart == nil { fistStart = sample.time }
        guard let start = fistStart, !fistFired, sample.time - start >= 0.8 else { return nil }
        fistFired = true
        return .nextParameter
    }

    private mutating func feedPoint(_ sample: HandSample, shape: HandShape) -> GestureEvent? {
        if pointShape != shape {
            pointShape = shape
            pointStart = sample.time
            lastPointFire = nil
        }
        guard let start = pointStart, sample.time - start >= 0.5 else { return nil }
        if let last = lastPointFire, sample.time - last < 0.4 { return nil }
        lastPointFire = sample.time
        return .adjust(step: shape == .pointUp ? 1 : -1)
    }

    private mutating func resetHoldTimers() {
        swipeAnchor = nil
        lastPinchDistance = nil
        fistStart = nil
        fistFired = false
        pointShape = nil
        pointStart = nil
        lastPointFire = nil
    }
}
