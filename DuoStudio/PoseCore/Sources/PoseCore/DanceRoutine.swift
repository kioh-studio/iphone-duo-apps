import Foundation

/// One sampled skeleton on a dance routine's timeline. `pose == nil` means Vision found nobody in
/// that frame (kept, rather than dropped, so a gap isn't silently interpolated across).
public struct TimedPose: Codable, Hashable, Sendable {
    public var time: Double
    public var pose: Pose?

    public init(time: Double, pose: Pose?) {
        self.time = time
        self.pose = pose
    }
}

/// A reference dance video reduced to a skeleton timeline (sampled ~10 fps by the app's
/// `RoutineImporter`), plus the metadata to find the video file again.
public struct DanceRoutine: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// Seconds.
    public var duration: Double
    /// Sorted ascending by `time`.
    public var frames: [TimedPose]
    /// Flip left/right — for tutorials filmed mirrored. Applied on read, never baked into `frames`.
    public var isMirrored: Bool
    /// File name inside the app's Routines directory.
    public var mediaFileName: String

    /// A gap (`pose == nil`) is bridged by the nearest real pose only within this many seconds.
    public static let gapTolerance: Double = 0.25

    public init(
        id: UUID = UUID(), name: String, duration: Double, frames: [TimedPose],
        isMirrored: Bool = false, mediaFileName: String
    ) {
        self.id = id
        self.name = name
        self.duration = duration
        self.frames = frames
        self.isMirrored = isMirrored
        self.mediaFileName = mediaFileName
    }

    /// Pose at time `t`: `nil` if `t < 0`, `t > duration` or there are no frames. Between two real
    /// frames each joint is linearly interpolated when it exists in both, else taken from the
    /// nearer frame (if it has it). A `pose == nil` frame breaks interpolation: the nearest real
    /// neighbour within `gapTolerance` seconds is used as-is, otherwise `nil`. Mirrored when
    /// `isMirrored`.
    public func pose(at t: Double) -> Pose? {
        guard t >= 0, t <= duration, !frames.isEmpty else { return nil }

        let upper = firstIndex(where: { $0.time > t })   // first frame strictly after t
        let lower = upper - 1                             // last frame at or before t

        let result: Pose?
        if lower >= 0, upper < frames.count, let before = frames[lower].pose, let after = frames[upper].pose {
            let span = frames[upper].time - frames[lower].time
            let u = span > 0 ? (t - frames[lower].time) / span : 0
            result = Self.interpolate(before, after, u)
        } else {
            result = nearestRealPose(around: t, lower: lower, upper: upper)
        }
        guard let result else { return nil }
        return isMirrored ? PoseMatcher.mirrored(result) : result
    }

    /// Real (non-nil) poses whose time falls in `window`, mirrored if `isMirrored`.
    public func poses(in window: ClosedRange<Double>) -> [Pose] {
        var index = firstIndex(where: { $0.time >= window.lowerBound })
        var result: [Pose] = []
        while index < frames.count, frames[index].time <= window.upperBound {
            if let pose = frames[index].pose {
                result.append(isMirrored ? PoseMatcher.mirrored(pose) : pose)
            }
            index += 1
        }
        return result
    }

    // MARK: - Private

    /// Binary search: index of the first frame satisfying `predicate` (monotone over the sorted
    /// frames), or `frames.count` if none does.
    private func firstIndex(where predicate: (TimedPose) -> Bool) -> Int {
        var low = 0
        var high = frames.count
        while low < high {
            let mid = (low + high) / 2
            if predicate(frames[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// Walks outwards from `t` (backwards from `lower`, forwards from `upper`) for the closest
    /// frame that has a pose, staying within `gapTolerance` seconds.
    private func nearestRealPose(around t: Double, lower: Int, upper: Int) -> Pose? {
        var best: (distance: Double, pose: Pose)?
        var index = lower
        while index >= 0, t - frames[index].time <= Self.gapTolerance {
            if let pose = frames[index].pose {
                best = (t - frames[index].time, pose)
                break
            }
            index -= 1
        }
        index = upper
        while index < frames.count, frames[index].time - t <= Self.gapTolerance {
            if let pose = frames[index].pose {
                let distance = frames[index].time - t
                if best == nil || distance < best!.distance { best = (distance, pose) }
                break
            }
            index += 1
        }
        return best?.pose
    }

    private static func interpolate(_ a: Pose, _ b: Pose, _ u: Double) -> Pose {
        var joints: [Joint: Point2] = [:]
        let nearer = u < 0.5 ? a : b
        for joint in Set(a.joints.keys).union(b.joints.keys) {
            if let pa = a.joints[joint], let pb = b.joints[joint] {
                joints[joint] = Point2(x: pa.x + (pb.x - pa.x) * u, y: pa.y + (pb.y - pa.y) * u)
            } else if let point = nearer.joints[joint] {
                joints[joint] = point
            }
        }
        return Pose(joints: joints)
    }
}
