import CoreImage
@preconcurrency import Vision
import PoseCore

/// Vision → `PoseCore` body-pose conversion, shared by `FrameProcessor` (live camera frames) and
/// `RoutineImporter` (frames of an imported reference video) so both read joints identically.
enum VisionPose {
    static let minConfidence: Float = 0.3

    static func vnJoint(for bodyJoint: PoseCore.Joint) -> VNHumanBodyPoseObservation.JointName {
        switch bodyJoint {
        case .nose: return .nose
        case .neck: return .neck
        case .leftShoulder: return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftElbow: return .leftElbow
        case .rightElbow: return .rightElbow
        case .leftWrist: return .leftWrist
        case .rightWrist: return .rightWrist
        case .leftHip: return .leftHip
        case .rightHip: return .rightHip
        case .leftKnee: return .leftKnee
        case .rightKnee: return .rightKnee
        case .leftAnkle: return .leftAnkle
        case .rightAnkle: return .rightAnkle
        case .root: return .root
        }
    }

    /// Vision's normalized points have their origin bottom-left; `PoseCore.Point2` (and the whole
    /// app) uses top-left, so `y` is flipped on the way in.
    static func bodyPose(from observation: VNHumanBodyPoseObservation) -> Pose? {
        var joints: [PoseCore.Joint: Point2] = [:]
        for poseJoint in PoseCore.Joint.allCases {
            let jointName = vnJoint(for: poseJoint)
            guard let point = try? observation.recognizedPoint(jointName), point.confidence > minConfidence else { continue }
            joints[poseJoint] = Point2(x: Double(point.location.x), y: 1 - Double(point.location.y))
        }
        guard !joints.isEmpty else { return nil }
        return Pose(joints: joints)
    }

    /// Body pose only (no hand request) in an upright image — used on imported reference video
    /// frames. `nil` when Vision throws or finds nobody.
    static func detectBody(in image: CIImage) -> Pose? {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let request = VNDetectHumanBodyPoseRequest()
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        return request.results?.first.flatMap(bodyPose(from:))
    }
}
