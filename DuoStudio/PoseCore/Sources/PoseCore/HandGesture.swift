import Foundation

/// A hand landmark (Vision's `VNHumanHandPoseObservation.JointName` subset we use).
public enum HandJoint: String, CaseIterable, Sendable {
    case wrist, thumbTip, thumbIP, indexTip, indexPIP, middleTip, middlePIP, ringTip, ringPIP,
         littleTip, littlePIP
}

/// A recognised hand shape.
public enum HandShape: Hashable, Sendable {
    case openPalm, fist, pinch, pointUp, pointDown
}

public enum HandClassifier {
    /// Rule-based classification from raw joint positions (normalized, origin top-left).
    ///
    /// `handSize` = distance(wrist, middlePIP). A finger is "extended" when
    /// distance(wrist, tip) > distance(wrist, pip) * 1.25.
    /// - pinch: distance(thumbTip, indexTip) < 0.35 * handSize AND middle/ring/little extended.
    /// - openPalm: all four (index/middle/ring/little) fingers extended.
    /// - fist: none of the four extended.
    /// - pointUp/pointDown: only index extended; up if indexTip.y < wrist.y (top-left origin),
    ///   else down.
    ///
    /// Returns `nil` if any required joint is missing or no rule fires.
    public static func classify(_ hand: [HandJoint: Point2]) -> HandShape? {
        guard
            let wrist = hand[.wrist],
            let middlePIP = hand[.middlePIP],
            let thumbTip = hand[.thumbTip],
            let indexTip = hand[.indexTip], let indexPIP = hand[.indexPIP],
            let middleTip = hand[.middleTip],
            let ringTip = hand[.ringTip], let ringPIP = hand[.ringPIP],
            let littleTip = hand[.littleTip], let littlePIP = hand[.littlePIP]
        else { return nil }

        let handSize = distance(wrist, middlePIP)
        guard handSize > 0 else { return nil }

        let indexExtended = isExtended(tip: indexTip, pip: indexPIP, wrist: wrist)
        let middleExtended = isExtended(tip: middleTip, pip: middlePIP, wrist: wrist)
        let ringExtended = isExtended(tip: ringTip, pip: ringPIP, wrist: wrist)
        let littleExtended = isExtended(tip: littleTip, pip: littlePIP, wrist: wrist)

        let pinchDistance = distance(thumbTip, indexTip)
        if pinchDistance < 0.35 * handSize && middleExtended && ringExtended && littleExtended {
            return .pinch
        }

        if indexExtended && middleExtended && ringExtended && littleExtended {
            return .openPalm
        }

        if !indexExtended && !middleExtended && !ringExtended && !littleExtended {
            return .fist
        }

        if indexExtended && !middleExtended && !ringExtended && !littleExtended {
            return indexTip.y < wrist.y ? .pointUp : .pointDown
        }

        return nil
    }

    private static func isExtended(tip: Point2, pip: Point2, wrist: Point2) -> Bool {
        distance(wrist, tip) > distance(wrist, pip) * 1.25
    }

    private static func distance(_ a: Point2, _ b: Point2) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
