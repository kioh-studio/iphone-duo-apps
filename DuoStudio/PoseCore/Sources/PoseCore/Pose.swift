import Foundation

/// A normalized 2D point, origin top-left, in the upright (portrait, un-mirrored) camera image.
public struct Point2: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A body landmark. `root` is the hip centre (Vision's `.root` body-pose joint).
///
/// Conforms to `CodingKeyRepresentable` (on top of the `String` raw value the spec calls for) so
/// `[Joint: Point2]` dictionaries encode as a JSON *object* keyed by joint name. Without this,
/// `Dictionary`'s `Encodable` conformance only special-cases `String`/`Int` keys or
/// `CodingKeyRepresentable` keys for the keyed-container path; a plain `RawRepresentable` enum key
/// falls through to encoding as a flat `[key, value, key, value, ...]` array instead. The raw
/// value is `String`, so the compiler synthesizes the `CodingKeyRepresentable` conformance for us.
public enum Joint: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case nose, neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist,
         leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle, root
}

/// One skeleton edge, e.g. neck→nose. Undirected in meaning; `from`/`to` fix a direction only so a
/// bone's vector (`to` − `from`) is well defined for angle comparisons.
public struct Bone: Hashable, Sendable {
    public let from: Joint
    public let to: Joint

    public init(from: Joint, to: Joint) {
        self.from = from
        self.to = to
    }
}

/// A full-body skeleton: normalized joint positions, keyed by `Joint`. Not every joint need be
/// present (e.g. a live Vision pose only reports joints above its confidence threshold).
public struct Pose: Codable, Hashable, Sendable {
    public var joints: [Joint: Point2]

    public init(joints: [Joint: Point2]) {
        self.joints = joints
    }

    /// The fixed set of bones compared for pose matching and drawn by the skeleton overlay.
    public static let bones: [Bone] = [
        Bone(from: .neck, to: .nose),
        Bone(from: .neck, to: .leftShoulder),
        Bone(from: .neck, to: .rightShoulder),
        Bone(from: .leftShoulder, to: .leftElbow),
        Bone(from: .rightShoulder, to: .rightElbow),
        Bone(from: .leftElbow, to: .leftWrist),
        Bone(from: .rightElbow, to: .rightWrist),
        Bone(from: .neck, to: .root),
        Bone(from: .root, to: .leftHip),
        Bone(from: .root, to: .rightHip),
        Bone(from: .leftHip, to: .leftKnee),
        Bone(from: .rightHip, to: .rightKnee),
        Bone(from: .leftKnee, to: .leftAnkle),
        Bone(from: .rightKnee, to: .rightAnkle),
    ]
}
