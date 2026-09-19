import AVFoundation
import CoreImage
import Vision
import os
import PoseCore

// UNVERIFIED (2026-09-20, written on Windows): CGImage's Sendable conformance in the iOS 26 SDK.
// Treated as safe to cross the actor hop below because each `CGImage` here is a freshly rendered,
// immutable snapshot from a private `CIContext` that's never mutated or read again afterwards.
struct FrameResult: Sendable {
    let image: CGImage
    let pose: Pose?
    /// `nil` when this frame wasn't a Vision-detection frame at all; non-`nil` (possibly with all
    /// `nil` fields, meaning "no hand seen") on every detection frame, so `GestureRecognizer` gets
    /// a steady ~10 Hz feed and can reset its hold timers on hand loss per its own contract.
    let hand: HandSample?
}

/// Turns raw camera frames into: (1) a filtered, downscaled preview image, and (2) — every third
/// frame — a `Pose`/`HandSample` pair from Vision (run on the unfiltered upright image, since a
/// filter like Noir or a contrast push hurts detection). Runs entirely on `CameraService`'s
/// private `videoQueue` via the `AVCaptureVideoDataOutputSampleBufferDelegate` callback. If the
/// main actor is still processing the previous `FrameResult`, the current frame is dropped
/// entirely (no render, no detection) rather than queued — see `CameraState.isDelivering` and
/// `plan.md`'s frame drop policy.
///
/// `@unchecked Sendable`: `frameCount` and `ciContext` are only ever touched from `videoQueue`
/// (the queue `CameraService` registers this delegate on), so there's no concurrent access to
/// guard against. `cameraState` is the one piece of state written from elsewhere (`StudioModel`
/// on `MainActor` for filter/contrast, `CameraService` on `sessionQueue` for camera position) and
/// read here, so it goes through `OSAllocatedUnfairLock` instead of being a plain stored property.
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Set once by `StudioModel` right after both are constructed (see `StudioModel.init`).
    /// `weak` because `StudioModel` owns `CameraService`, which owns this processor — a strong
    /// reference back would cycle. Only ever read here to snapshot into a local `let` that is then
    /// handed to a `Task { @MainActor in ... }`; never touched from `captureOutput` afterwards, so
    /// there's nothing left to race with `MainActor`'s use of it.
    weak var model: StudioModel?

    private let ciContext = CIContext()
    private var frameCount = 0

    private struct CameraState {
        var filter: StudioFilter = .none
        var contrast: Double = 1
        var position: AVCaptureDevice.Position = .back
        /// True from the moment a `FrameResult` is handed to the `Task { @MainActor in ... }`
        /// below until `StudioModel.receive(_:)` returns, so a busy main actor can't accumulate an
        /// unbounded queue of pending deliveries.
        var isDelivering = false
    }
    private let cameraState = OSAllocatedUnfairLock(initialState: CameraState())

    private static let longEdge: CGFloat = 1440
    private static let poseFrameInterval = 3
    private static let minConfidence: Float = 0.3

    /// Called by `StudioModel` whenever the filter or contrast changes, from gestures or the
    /// inner UI alike, so the next frame picks it up without needing to touch `MainActor` state.
    func updateFilter(_ filter: StudioFilter, contrast: Double) {
        cameraState.withLock {
            $0.filter = filter
            $0.contrast = contrast
        }
    }

    /// Called by `CameraService` (from `sessionQueue`) whenever the active device changes, so
    /// orientation handling matches whichever physical camera is now feeding frames.
    func updatePosition(_ position: AVCaptureDevice.Position) {
        cameraState.withLock { $0.position = position }
    }

    // ponytail: CGImage per frame via one shared CIContext; move to MTKView if the live preview
    // measurably drops frames on device.
    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        let (filter, contrast, position) = cameraState.withLock { ($0.filter, $0.contrast, $0.position) }

        // UNVERIFIED (2026-09-20, written on Windows): orientation needed to reach the canonical
        // "upright, un-mirrored" image PoseCore's coordinate convention assumes (see Pose.swift).
        // `.right` puts the back camera's native landscape sensor output upright for portrait.
        // The front sensor's raw buffer is mirrored left-right relative to the back sensor's, so
        // `.leftMirrored` is used instead, to rotate to portrait-upright *and* undo that mirror in
        // one step — unconfirmed on a real device, and unconfirmed for the Duo's inner ultrawide
        // used in self-portrait mode, which may not share the classic front camera's mount.
        let orientation: CGImagePropertyOrientation = position == .front ? .leftMirrored : .right
        let upright = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        var ciImage = upright

        if let filterName = filter.coreImageName {
            ciImage = ciImage.applyingFilter(filterName)
        }
        ciImage = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: contrast])

        frameCount += 1
        let isDetectionFrame = frameCount % Self.poseFrameInterval == 0
        // Frame pile-up guard: if the last delivered `FrameResult` hasn't finished reaching
        // `StudioModel` on the main actor yet, skip rendering/delivering this one rather than
        // queuing an unbounded pile of `Task { @MainActor in ... }`s behind a busy main actor.
        // `frameCount` still advances above so detection cadence stays regular either way.
        let shouldDeliver = cameraState.withLock { state -> Bool in
            guard !state.isDelivering else { return false }
            state.isDelivering = true
            return true
        }
        guard shouldDeliver else { return }

        // Vision runs on `upright` (unfiltered) rather than `ciImage`: filters like Noir or a
        // contrast push hurt body/hand detection, and detection never needs to look like the
        // photo the subject sees.
        var pose: Pose?
        var hand: HandSample?
        if isDetectionFrame {
            let detection = detectPose(in: upright, time: time)
            pose = detection.pose
            hand = detection.hand
        }

        let extent = ciImage.extent
        let scale = min(1, Self.longEdge / max(extent.width, extent.height))
        let scaled = scale < 1 ? ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : ciImage

        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else {
            cameraState.withLock { $0.isDelivering = false }
            return
        }

        let result = FrameResult(image: cgImage, pose: pose, hand: hand)
        // Snapshot the weak reference to a local `let` first: a single, disconnected reference is
        // what Swift 6's `sending` closure on `Task.init` needs to hand `model` (non-`Sendable`,
        // `@MainActor`-isolated) over to the main actor without a data race.
        guard let model else {
            cameraState.withLock { $0.isDelivering = false }
            return
        }
        Task { @MainActor [cameraState] in
            model.receive(result)
            cameraState.withLock { $0.isDelivering = false }
        }
    }

    // MARK: - Vision

    private func detectPose(in image: CIImage, time: TimeInterval) -> (pose: Pose?, hand: HandSample) {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let bodyRequest = VNDetectHumanBodyPoseRequest()
        let handRequest = VNDetectHumanHandPoseRequest()
        handRequest.maximumHandCount = 1
        do {
            try handler.perform([bodyRequest, handRequest])
        } catch {
            return (nil, HandSample(shape: nil, wrist: nil, pinchDistance: nil, time: time))
        }

        let pose = (bodyRequest.results?.first).flatMap(bodyPose(from:))
        let hand = (handRequest.results?.first).map { handSample(from: $0, time: time) }
            ?? HandSample(shape: nil, wrist: nil, pinchDistance: nil, time: time)
        return (pose, hand)
    }

    private static let bodyJointMap: [(Joint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.neck, .neck),
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
        (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
        (.root, .root),
    ]

    /// Vision's normalized points have their origin bottom-left; `PoseCore.Point2` (and the whole
    /// app) uses top-left, so `y` is flipped on the way in.
    private func bodyPose(from observation: VNHumanBodyPoseObservation) -> Pose? {
        var joints: [Joint: Point2] = [:]
        for (poseJoint, vnJoint) in Self.bodyJointMap {
            guard let point = try? observation.recognizedPoint(vnJoint), point.confidence > Self.minConfidence else { continue }
            joints[poseJoint] = Point2(x: Double(point.location.x), y: 1 - Double(point.location.y))
        }
        guard !joints.isEmpty else { return nil }
        return Pose(joints: joints)
    }

    private static func vnJoint(for handJoint: HandJoint) -> VNHumanHandPoseObservation.JointName {
        switch handJoint {
        case .wrist: return .wrist
        case .thumbTip: return .thumbTip
        case .thumbIP: return .thumbIP
        case .indexTip: return .indexTip
        case .indexPIP: return .indexPIP
        case .middleTip: return .middleTip
        case .middlePIP: return .middlePIP
        case .ringTip: return .ringTip
        case .ringPIP: return .ringPIP
        case .littleTip: return .littleTip
        case .littlePIP: return .littlePIP
        }
    }

    private func handSample(from observation: VNHumanHandPoseObservation, time: TimeInterval) -> HandSample {
        var points: [HandJoint: Point2] = [:]
        for handJoint in HandJoint.allCases {
            let vnJoint = Self.vnJoint(for: handJoint)
            guard let point = try? observation.recognizedPoint(vnJoint), point.confidence > Self.minConfidence else { continue }
            points[handJoint] = Point2(x: Double(point.location.x), y: 1 - Double(point.location.y))
        }
        return HandSample(
            shape: HandClassifier.classify(points),
            wrist: points[.wrist],
            pinchDistance: pinchDistance(points),
            time: time
        )
    }

    /// Mirrors `HandClassifier`'s own `handSize` definition so the ratio the gesture recognizer
    /// compares frame-to-frame is on the same scale the classifier uses for its pinch threshold.
    private func pinchDistance(_ points: [HandJoint: Point2]) -> Double? {
        guard let thumbTip = points[.thumbTip], let indexTip = points[.indexTip],
              let wrist = points[.wrist], let middlePIP = points[.middlePIP] else { return nil }
        let handSize = distance(wrist, middlePIP)
        guard handSize > 0 else { return nil }
        return distance(thumbTip, indexTip) / handSize
    }

    private func distance(_ a: Point2, _ b: Point2) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
