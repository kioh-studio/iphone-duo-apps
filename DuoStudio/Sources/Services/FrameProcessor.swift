import AVFoundation
import CoreImage
@preconcurrency import Vision
import os
import PoseCore

/// `@unchecked Sendable`: `image` is a freshly rendered, immutable `CGImage` snapshot from a
/// private `CIContext` that's never mutated or read again afterwards, and `pose`/`hand` are plain
/// value types — nothing here is shared mutable state, so crossing the actor hop below is safe even
/// though `CGImage`'s own `Sendable` conformance isn't confirmed on the iOS 26 SDK.
struct FrameResult: @unchecked Sendable {
    let image: CGImage
    let pose: Pose?
    /// `nil` when this frame wasn't a Vision-detection frame at all; non-`nil` (possibly with all
    /// `nil` fields, meaning "no hand seen") on every detection frame, so `GestureRecognizer` gets
    /// a steady ~10 Hz feed and can reset its hold timers on hand loss per its own contract.
    let hand: HandSample?
    /// True on every 3rd frame (see `poseFrameInterval`), the ones `pose`/`hand` actually came from
    /// Vision on. `StudioModel.receive(_:)` only updates `livePose`/`match` on these — updating them
    /// on every frame (most of which have `pose == nil`) is what caused the skeleton to flicker.
    let isDetectionFrame: Bool
    /// Interview guide only (dual-camera mode): the downscaled 1080x1920 split-screen composite
    /// that is being recorded, for the inner display's preview. `nil` in every other mode.
    let compositePreview: CGImage?
}

/// Turns raw camera frames into: (0) while recording, a frame for `MovieRecorder` (full-res,
/// filtered, never dropped), (1) a filtered, downscaled preview image, and (2) — every third
/// frame — a `Pose`/`HandSample` pair from Vision (run on the unfiltered upright image, since a
/// filter like Noir or a contrast push hurts detection). Runs entirely on `CameraService`'s
/// private `videoQueue` via the `AVCaptureVideoDataOutputSampleBufferDelegate` callback. If the
/// main actor is still processing the previous `FrameResult`, the current frame is dropped
/// entirely (no preview render, no detection — but the recorder has already been fed) rather than queued — see `CameraState.isDelivering` and
/// `plan.md`'s frame drop policy.
///
/// `@unchecked Sendable`: `recorder` is internally queue-confined, and `frameCount` and `ciContext` are only ever touched from the single
/// serial queue that drives this processor — `CameraService`'s `videoQueue` on device, or
/// `SimulatedFrameSource`'s `timerQueue` in the Simulator — so there's no concurrent access to
/// guard against. `cameraState` is the one piece of state written from elsewhere (`StudioModel` on
/// `MainActor`, for filter/contrast) and read here, so it goes through `OSAllocatedUnfairLock`
/// instead of being a plain stored property.
final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Writes every processed frame (and, when enabled, microphone audio) to a movie file. Fed from
    /// `process(upright:time:)` BEFORE the main-actor frame-drop guard, so recording never loses
    /// frames to a busy main actor. Internally queue-confined — see `MovieRecorder`.
    let recorder = MovieRecorder()

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
        /// True from the moment a `FrameResult` is handed to the `Task { @MainActor in ... }`
        /// below until `StudioModel.receive(_:)` returns, so a busy main actor can't accumulate an
        /// unbounded queue of pending deliveries.
        var isDelivering = false
        /// Non-nil while the Interview guide records both cameras: the recorded frame is the
        /// guest + interviewer split-screen composite (see `composite(guest:interviewer:)`).
        var interviewSink: SecondaryFrameSink?
    }
    private let cameraState = OSAllocatedUnfairLock(initialState: CameraState())

    private static let longEdge: CGFloat = 1440
    private static let poseFrameInterval = 3
    /// Long edge of `FrameResult.compositePreview`.
    private static let compositePreviewLongEdge: CGFloat = 960

    /// Called by `StudioModel` whenever the filter or contrast changes, from gestures or the
    /// inner UI alike, so the next frame picks it up without needing to touch `MainActor` state.
    func updateFilter(_ filter: StudioFilter, contrast: Double) {
        cameraState.withLock {
            $0.filter = filter
            $0.contrast = contrast
        }
    }

    /// Switches the recorded frame between the plain guest frame (`nil`) and the Interview
    /// split-screen composite (the sink supplies the interviewer half). Called by `CameraService` /
    /// `SimulatedFrameSource` when the Interview session is (re)built.
    func setInterviewSink(_ sink: SecondaryFrameSink?) {
        cameraState.withLock { $0.interviewSink = sink }
    }

    // ponytail: CGImage per frame via one shared CIContext; move to MTKView if the live preview
    // measurably drops frames on device.
    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        // One selector serves both the video and the audio data output delegate protocols;
        // `CameraService` points both outputs at this processor on the same `videoQueue`, so audio
        // and video reach the recorder in capture order.
        if output is AVCaptureAudioDataOutput {
            recorder.appendAudio(sampleBuffer)
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // Already upright and un-mirrored: `CameraService.configureConnections()` sets the video
        // data output connection's `videoRotationAngle`/`isVideoMirrored` to match PoseCore's
        // "upright, un-mirrored" coordinate convention (see `Pose.swift`), so no per-frame
        // orientation guess is needed here.
        process(upright: CIImage(cvPixelBuffer: pixelBuffer), time: time)
    }

    /// Everything after frame capture: filter/contrast, frame counting, delivery guard, Vision,
    /// render, and the `MainActor` hop. `upright` must already be upright and un-mirrored
    /// (PoseCore's convention). `time` must be monotonic across calls — `GestureRecognizer`
    /// compares it. Shared by `captureOutput` and the Simulator's video-backed
    /// `SimulatedFrameSource`; call it from a single serial queue only (see the class doc).
    func process(upright: CIImage, time: TimeInterval) {
        let (filter, contrast, sink) = cameraState.withLock { ($0.filter, $0.contrast, $0.interviewSink) }
        let ciImage = Self.look(upright, filter: filter, contrast: contrast)

        // Interview: filter the interviewer half the same way, then stack both halves. (Filters are
        // per-pixel, so this equals filtering the composite - without filtering the guest twice.)
        var composite: CIImage?
        if let sink {
            let interviewer = sink.latest.map { Self.look($0, filter: filter, contrast: contrast) }
            composite = Self.composite(guest: ciImage, interviewer: interviewer)
        }

        // Recording bakes in the same filter + contrast the subject sees (like `PhotoWriter` does
        // for photos) at full resolution, and runs before the delivery guard below: a dropped
        // preview frame must never be a dropped video frame. Cheap early return when not recording.
        recorder.appendVideo(composite ?? ciImage, time: time)

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

        var compositePreview: CGImage?
        if let composite {
            let previewScale = Self.compositePreviewLongEdge / max(composite.extent.width, composite.extent.height)
            compositePreview = ciContext.createCGImage(
                composite.transformed(by: CGAffineTransform(scaleX: previewScale, y: previewScale)),
                from: CGRect(
                    x: 0, y: 0,
                    width: composite.extent.width * previewScale, height: composite.extent.height * previewScale
                )
            )
        }

        let result = FrameResult(
            image: cgImage, pose: pose, hand: hand, isDetectionFrame: isDetectionFrame,
            compositePreview: compositePreview
        )
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

    // MARK: - Look + Interview composite

    private static func look(_ image: CIImage, filter: StudioFilter, contrast: Double) -> CIImage {
        var result = image
        if let filterName = filter.coreImageName {
            result = result.applyingFilter(filterName)
        }
        return result.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: contrast])
    }

    /// The Studio skin's `Theme.Palette.paper` (OKLCH 0.13 / 0.004 / 260) - Services can't import `Theme`
    /// (SwiftUI) and must not depend on the runtime skin, so the Studio triple is repeated (as
    /// `SimulatedFrameSource` does) and the recorded file looks the same whatever skin is active. Fills the interviewer half until
    /// the second camera delivers its first frame.
    // UNVERIFIED (2026-10-18, written on Windows): `CIColor(red:green:blue:alpha:colorSpace:)` with
    // a linear sRGB `CGColorSpace` (the OKLCH conversion yields linear values).
    nonisolated(unsafe) private static let paper: CIColor = {
        let rgb = OKLCH.linearSRGB(l: 0.13, c: 0.004, h: 260)
        if let space = CGColorSpace(name: CGColorSpace.linearSRGB),
           let color = CIColor(red: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: 1, colorSpace: space) {
            return color
        }
        return CIColor(red: 0.05, green: 0.05, blue: 0.05)
    }()

    /// Guest in the top half, interviewer in the bottom half of a 1080x1920 canvas, each
    /// aspect-filled and centre-cropped into its half (geometry: `SplitLayout`, y-up).
    private static func composite(guest: CIImage, interviewer: CIImage?) -> CIImage {
        let canvas = CGRect(x: 0, y: 0, width: SplitLayout.canvasWidth, height: SplitLayout.canvasHeight)
        var result = CIImage(color: paper).cropped(to: canvas)
        if let placed = place(guest, into: SplitLayout.guest) { result = placed.composited(over: result) }
        if let interviewer, let placed = place(interviewer, into: SplitLayout.interviewer) {
            result = placed.composited(over: result)
        }
        return result
    }

    private static func place(_ image: CIImage, into rect: SplitLayout.Rect) -> CIImage? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0, extent.width.isFinite, extent.height.isFinite else { return nil }
        let placement = SplitLayout.aspectFill(sourceWidth: extent.width, sourceHeight: extent.height, into: rect)
        let transform = CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
            .concatenating(CGAffineTransform(scaleX: placement.scale, y: placement.scale))
            .concatenating(CGAffineTransform(translationX: placement.tx, y: placement.ty))
        return image.transformed(by: transform)
            .cropped(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
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

        let pose = (bodyRequest.results?.first).flatMap(VisionPose.bodyPose(from:))
        let hand = (handRequest.results?.first).map { handSample(from: $0, time: time) }
            ?? HandSample(shape: nil, wrist: nil, pinchDistance: nil, time: time)
        return (pose, hand)
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
            guard let point = try? observation.recognizedPoint(vnJoint), point.confidence > VisionPose.minConfidence else { continue }
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
