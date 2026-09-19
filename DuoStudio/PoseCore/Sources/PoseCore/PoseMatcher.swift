import Foundation

/// The result of comparing a live skeleton against a template.
public struct PoseMatch: Hashable, Sendable {
    public let score: Double
    public let offBones: Set<Bone>

    public init(score: Double, offBones: Set<Bone>) {
        self.score = score
        self.offBones = offBones
    }
}

public enum PoseMatcher {
    public static let toleranceDegrees: Double = 20

    /// Compares bone DIRECTIONS only (translation/scale invariant): for every bone in `Pose.bones`
    /// with both endpoints present in both poses, the angle difference `d` (0...180°) between the
    /// two bone vectors is computed; per-bone score is `max(0, 1 - d / 60)`; the overall score is
    /// the mean per-bone score; `offBones` is the set of bones with `d > toleranceDegrees`.
    /// Returns `nil` if fewer than 4 bones are comparable.
    public static func match(live: Pose, template: Pose) -> PoseMatch? {
        var totalScore = 0.0
        var comparableCount = 0
        var offBones: Set<Bone> = []

        for bone in Pose.bones {
            guard
                let liveFrom = live.joints[bone.from], let liveTo = live.joints[bone.to],
                let templateFrom = template.joints[bone.from], let templateTo = template.joints[bone.to],
                let angle = angleDegrees(
                    from: (liveTo.x - liveFrom.x, liveTo.y - liveFrom.y),
                    to: (templateTo.x - templateFrom.x, templateTo.y - templateFrom.y)
                )
            else { continue }

            comparableCount += 1
            totalScore += max(0, 1 - angle / 60)
            if angle > toleranceDegrees {
                offBones.insert(bone)
            }
        }

        guard comparableCount >= 4 else { return nil }
        return PoseMatch(score: totalScore / Double(comparableCount), offBones: offBones)
    }

    /// Mirror horizontally (x → 1-x, and swap left*/right* joints). Used when the template is
    /// authored for the subject's (mirrored) view.
    public static func mirrored(_ pose: Pose) -> Pose {
        var joints: [Joint: Point2] = [:]
        joints.reserveCapacity(pose.joints.count)
        for (joint, point) in pose.joints {
            joints[mirroredJoint(joint)] = Point2(x: 1 - point.x, y: point.y)
        }
        return Pose(joints: joints)
    }

    /// The angle in degrees (0...180) between two vectors, via the dot-product formula — this
    /// avoids the wraparound bookkeeping an `atan2` difference would need. `nil` if either vector
    /// is zero-length (degenerate bone: both endpoints coincide).
    private static func angleDegrees(from a: (Double, Double), to b: (Double, Double)) -> Double? {
        let magnitudeA = (a.0 * a.0 + a.1 * a.1).squareRoot()
        let magnitudeB = (b.0 * b.0 + b.1 * b.1).squareRoot()
        guard magnitudeA > 0, magnitudeB > 0 else { return nil }
        let cosine = (a.0 * b.0 + a.1 * b.1) / (magnitudeA * magnitudeB)
        return acos(min(max(cosine, -1), 1)) * 180 / .pi
    }

    private static func mirroredJoint(_ joint: Joint) -> Joint {
        switch joint {
        case .leftShoulder: return .rightShoulder
        case .rightShoulder: return .leftShoulder
        case .leftElbow: return .rightElbow
        case .rightElbow: return .leftElbow
        case .leftWrist: return .rightWrist
        case .rightWrist: return .leftWrist
        case .leftHip: return .rightHip
        case .rightHip: return .leftHip
        case .leftKnee: return .rightKnee
        case .rightKnee: return .leftKnee
        case .leftAnkle: return .rightAnkle
        case .rightAnkle: return .leftAnkle
        case .nose, .neck, .root: return joint
        }
    }
}
