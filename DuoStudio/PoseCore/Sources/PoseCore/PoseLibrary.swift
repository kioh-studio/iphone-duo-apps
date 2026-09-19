import Foundation

/// A named, reusable pose — either one of the built-ins or a photographer-authored custom one.
public struct PoseTemplate: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var pose: Pose
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, pose: Pose, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.pose = pose
        self.isBuiltIn = isBuiltIn
    }
}

/// The built-in template library: 8 full-body standing/sitting poses, hand-authored with plausible
/// proportions. Coordinates are normalized 0...1, origin top-left, figure roughly centred on
/// x ≈ 0.5, spanning y ≈ 0.15 (head) … 0.9 (feet) — seated poses sit a little higher.
public enum PoseLibrary {
    public static let builtIn: [PoseTemplate] = [
        PoseTemplate(
            id: UUID(uuidString: "D0505000-0000-4000-8000-000000000001")!,
            name: "Straight on",
            pose: Pose(joints: [
                .nose: Point2(x: 0.50, y: 0.15),
                .neck: Point2(x: 0.50, y: 0.22),
                .leftShoulder: Point2(x: 0.43, y: 0.24),
                .rightShoulder: Point2(x: 0.57, y: 0.24),
                .leftElbow: Point2(x: 0.40, y: 0.38),
                .rightElbow: Point2(x: 0.60, y: 0.38),
                .leftWrist: Point2(x: 0.38, y: 0.52),
                .rightWrist: Point2(x: 0.62, y: 0.52),
                .root: Point2(x: 0.50, y: 0.55),
                .leftHip: Point2(x: 0.45, y: 0.56),
                .rightHip: Point2(x: 0.55, y: 0.56),
                .leftKnee: Point2(x: 0.44, y: 0.73),
                .rightKnee: Point2(x: 0.56, y: 0.73),
                .leftAnkle: Point2(x: 0.43, y: 0.90),
                .rightAnkle: Point2(x: 0.57, y: 0.90),
            ]),
            isBuiltIn: true
        ),
        PoseTemplate(
            id: UUID(uuidString: "D0505000-0000-4000-8000-000000000002")!,
            name: "Hand on hip",
            pose: Pose(joints: [
                .nose: Point2(x: 0.50, y: 0.15),
                .neck: Point2(x: 0.50, y: 0.22),
                .leftShoulder: Point2(x: 0.43, y: 0.24),
                .rightShoulder: Point2(x: 0.57, y: 0.24),
                .leftElbow: Point2(x: 0.39, y: 0.37),
                .rightElbow: Point2(x: 0.63, y: 0.33),
                .leftWrist: Point2(x: 0.37, y: 0.51),
                .rightWrist: Point2(x: 0.58, y: 0.47),
                .root: Point2(x: 0.50, y: 0.55),
                .leftHip: Point2(x: 0.45, y: 0.56),
                .rightHip: Point2(x: 0.55, y: 0.56),
                .leftKnee: Point2(x: 0.44, y: 0.73),
                .rightKnee: Point2(x: 0.56, y: 0.73),
                .leftAnkle: Point2(x: 0.43, y: 0.90),
                .rightAnkle: Point2(x: 0.57, y: 0.90),
            ]),
            isBuiltIn: true
        ),
        PoseTemplate(
            id: UUID(uuidString: "D0505000-0000-4000-8000-000000000003")!,
            name: "Arms crossed",
            pose: Pose(joints: [
                .nose: Point2(x: 0.50, y: 0.15),
                .neck: Point2(x: 0.50, y: 0.22),
                .leftShoulder: Point2(x: 0.43, y: 0.24),
                .rightShoulder: Point2(x: 0.57, y: 0.24),
                .leftElbow: Point2(x: 0.38, y: 0.34),
                .rightElbow: Point2(x: 0.62, y: 0.34),
                .leftWrist: Point2(x: 0.57, y: 0.40),
                .rightWrist: Point2(x: 0.43, y: 0.42),
                .root: Point2(x: 0.50, y: 0.55),
                .leftHip: Point2(x: 0.45, y: 0.56),
                .rightHip: Point2(x: 0.55, y: 0.56),
                .leftKnee: Point2(x: 0.44, y: 0.73),
                .rightKnee: Point2(x: 0.56, y: 0.73),
                .leftAnkle: Point2(x: 0.43, y: 0.90),
                .rightAnkle: Point2(x: 0.57, y: 0.90),
            ]),
            isBuiltIn: true
        ),
        PoseTemplate(
            id: UUID(uuidString: "D0505000-0000-4000-8000-000000000004")!,
            name: "Lean",
            pose: Pose(joints: [
                .nose: Point2(x: 0.54, y: 0.16),
                .neck: Point2(x: 0.53, y: 0.23),
                .leftShoulder: Point2(x: 0.46, y: 0.25),
                .rightShoulder: Point2(x: 0.60, y: 0.24),
                .leftElbow: Point2(x: 0.42, y: 0.39),
                .rightElbow: Point2(x: 0.65, y: 0.36),
                .leftWrist: Point2(x: 0.40, y: 0.53),
                .rightWrist: Point2(x: 0.68, y: 0.48),
                .root: Point2(x: 0.51, y: 0.56),
                .leftHip: Point2(x: 0.46, y: 0.57),
                .rightHip: Point2(x: 0.56, y: 0.57),
                .leftKnee: Point2(x: 0.42, y: 0.74),
                .rightKnee: Point2(x: 0.60, y: 0.72),
                .leftAnkle: Point2(x: 0.41, y: 0.90),
                .rightAnkle: Point2(x: 0.62, y: 0.88),
            ]),
            isBuiltIn: true
        ),
        PoseTemplate(
            id: UUID(uuidString: "D0505000-0000-4000-8000-000000000005")!,
            name: "Walking",
            pose: Pose(joints: [
                .nose: Point2(x: 0.50, y: 0.15),
                .neck: Point2(x: 0.50, y: 0.22),
                .leftShoulder: Point2(x: 0.43, y: 0.24),
                .rightShoulder: Point2(x: 0.57, y: 0.24),
                .leftElbow: Point2(x: 0.37, y: 0.36),
                .rightElbow: Point2(x: 0.63, y: 0.40),
                .leftWrist: Point2(x: 0.34, y: 0.48),
                .rightWrist: Point2(x: 0.66, y: 0.52),
                .root: Point2(x: 0.50, y: 0.55),
                .leftHip: Point2(x: 0.45, y: 0.56),
                .rightHip: Point2(x: 0.55, y: 0.56),
                .leftKnee: Point2(x: 0.38, y: 0.72),
                .rightKnee: Point2(x: 0.60, y: 0.75),
                .leftAnkle: Point2(x: 0.35, y: 0.88),
                .rightAnkle: Point2(x: 0.62, y: 0.91),
            ]),
            isBuiltIn: true
        ),
        PoseTemplate(
            id: UUID(uuidString: "D0505000-0000-4000-8000-000000000006")!,
            name: "Over the shoulder",
            pose: Pose(joints: [
                .nose: Point2(x: 0.46, y: 0.16),
                .neck: Point2(x: 0.49, y: 0.23),
                .leftShoulder: Point2(x: 0.41, y: 0.26),
                .rightShoulder: Point2(x: 0.58, y: 0.22),
                .leftElbow: Point2(x: 0.37, y: 0.39),
                .rightElbow: Point2(x: 0.62, y: 0.37),
                .leftWrist: Point2(x: 0.35, y: 0.53),
                .rightWrist: Point2(x: 0.64, y: 0.51),
                .root: Point2(x: 0.50, y: 0.55),
                .leftHip: Point2(x: 0.45, y: 0.56),
                .rightHip: Point2(x: 0.56, y: 0.55),
                .leftKnee: Point2(x: 0.44, y: 0.73),
                .rightKnee: Point2(x: 0.57, y: 0.73),
                .leftAnkle: Point2(x: 0.43, y: 0.90),
                .rightAnkle: Point2(x: 0.58, y: 0.90),
            ]),
            isBuiltIn: true
        ),
        PoseTemplate(
            id: UUID(uuidString: "D0505000-0000-4000-8000-000000000007")!,
            name: "Seated",
            pose: Pose(joints: [
                .nose: Point2(x: 0.50, y: 0.20),
                .neck: Point2(x: 0.50, y: 0.27),
                .leftShoulder: Point2(x: 0.44, y: 0.29),
                .rightShoulder: Point2(x: 0.56, y: 0.29),
                .leftElbow: Point2(x: 0.40, y: 0.42),
                .rightElbow: Point2(x: 0.60, y: 0.42),
                .leftWrist: Point2(x: 0.42, y: 0.54),
                .rightWrist: Point2(x: 0.58, y: 0.54),
                .root: Point2(x: 0.50, y: 0.58),
                .leftHip: Point2(x: 0.44, y: 0.59),
                .rightHip: Point2(x: 0.56, y: 0.59),
                .leftKnee: Point2(x: 0.38, y: 0.60),
                .rightKnee: Point2(x: 0.62, y: 0.60),
                .leftAnkle: Point2(x: 0.37, y: 0.82),
                .rightAnkle: Point2(x: 0.63, y: 0.82),
            ]),
            isBuiltIn: true
        ),
        PoseTemplate(
            id: UUID(uuidString: "D0505000-0000-4000-8000-000000000008")!,
            name: "Arms up",
            pose: Pose(joints: [
                .nose: Point2(x: 0.50, y: 0.15),
                .neck: Point2(x: 0.50, y: 0.22),
                .leftShoulder: Point2(x: 0.43, y: 0.24),
                .rightShoulder: Point2(x: 0.57, y: 0.24),
                .leftElbow: Point2(x: 0.38, y: 0.14),
                .rightElbow: Point2(x: 0.62, y: 0.14),
                .leftWrist: Point2(x: 0.35, y: 0.04),
                .rightWrist: Point2(x: 0.65, y: 0.04),
                .root: Point2(x: 0.50, y: 0.55),
                .leftHip: Point2(x: 0.45, y: 0.56),
                .rightHip: Point2(x: 0.55, y: 0.56),
                .leftKnee: Point2(x: 0.44, y: 0.73),
                .rightKnee: Point2(x: 0.56, y: 0.73),
                .leftAnkle: Point2(x: 0.43, y: 0.90),
                .rightAnkle: Point2(x: 0.57, y: 0.90),
            ]),
            isBuiltIn: true
        ),
    ]
}
