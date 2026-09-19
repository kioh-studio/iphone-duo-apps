import AVFoundation
import PoseCore

enum CameraServiceError: Error {
    case captureFailed
}

/// Wraps the `AVCaptureSession` that feeds the live preview, the pose/hand pipeline (via
/// `FrameProcessor`) and photo capture.
///
/// `@unchecked Sendable`: every stored mutable property (`session`, `videoDeviceInput`, `mode`,
/// `isConfigured`, `activePhotoCapture`, `directionCoordinator`, `lastAppliedAdjustments`) is only
/// ever touched from `sessionQueue`, a private serial queue — never from `MainActor` or from
/// `videoQueue` (which only ever sees the already-configured, effectively-immutable
/// `AVCaptureVideoDataOutput`). Every public method re-enters `sessionQueue` before touching
/// state, so nothing here is read concurrently with a write.
final class CameraService: NSObject, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "tech.kioh.duostudio.session")
    private let videoQueue = DispatchQueue(label: "tech.kioh.duostudio.video")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let frameProcessor: FrameProcessor

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var mode: CaptureMode = .partner
    private var isConfigured = false
    private var activePhotoCapture: PhotoCaptureDelegate?
    /// Untyped so the property itself doesn't need an `@available` annotation; the only place that
    /// touches it (`selectDuoDevice`) is already `@available(iOS 27.1, *)` and casts back. Created
    /// once and reused — a local `let` would be deallocated (and its change handler with it)
    /// before it could ever fire.
    private var directionCoordinator: AnyObject?
    /// The last `Adjustments` actually pushed to a device, so `apply(_:)` only touches the hardware
    /// knob that changed (see `apply(_:)`) and `reconfigureInput()` knows whether warmth was ever
    /// touched away from its default.
    private var lastAppliedAdjustments = Adjustments()

    init(frameProcessor: FrameProcessor) {
        self.frameProcessor = frameProcessor
        super.init()
    }

    static func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func start() {
        sessionQueue.async { [self] in
            if !isConfigured {
                configureSession()
                isConfigured = true
            }
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    /// Switches between the partner-facing camera and the self-portrait camera. Safe to call
    /// before `start()` — it just records the mode, and `configureSession()` picks it up when the
    /// session is first built; after that it swaps the live input in place.
    func setMode(_ mode: CaptureMode) {
        sessionQueue.async { [self] in
            guard self.mode != mode else { return }
            self.mode = mode
            guard isConfigured else { return }
            reconfigureInput()
        }
    }

    // MARK: - Session configuration (sessionQueue only)

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        addInput(for: mode)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(frameProcessor, queue: videoQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }

    private func addInput(for mode: CaptureMode) {
        guard let device = selectDevice(for: mode), let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
        }
        frameProcessor.updatePosition(device.position)
    }

    /// Swaps the active input for the device the current `mode` wants, without touching outputs.
    /// Also used as the direction coordinator's change handler, so posture changes (partner mode)
    /// re-run the same "which device does this mode want" logic.
    private func reconfigureInput() {
        guard let device = selectDevice(for: mode), let input = try? AVCaptureDeviceInput(device: device) else { return }
        guard device.uniqueID != videoDeviceInput?.device.uniqueID else { return }
        session.beginConfiguration()
        if let current = videoDeviceInput { session.removeInput(current) }
        if session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
        }
        session.commitConfiguration()
        frameProcessor.updatePosition(device.position)

        // The new device starts on its own hardware defaults, so re-push exposure unconditionally;
        // white balance only if warmth was ever actually touched away from its default (otherwise
        // the new device should stay on auto WB too, same as `apply(_:)`'s own rule).
        let warmthTouched = lastAppliedAdjustments.warmthKelvin != Adjustments().warmthKelvin
        applyToDevice(device, adjustments: lastAppliedAdjustments, setExposure: true, setWarmth: warmthTouched)
    }

    /// Partner mode wants the camera facing the subject (away from the photographer's inner-display
    /// view), so the outer display mirrors what the lens sees. Self-portrait mode wants the camera
    /// facing the same screen the user is looking at — the classic "selfie" camera. iOS 27.1+ Duo
    /// hardware exposes a direction coordinator that knows which ultrawide faces which side;
    /// everything else (non-Duo iPhones, or pre-27.1 SDKs) falls back to the classic wide cameras.
    private func selectDevice(for mode: CaptureMode) -> AVCaptureDevice? {
        if #available(iOS 27.1, *), let device = selectDuoDevice(for: mode) {
            return device
        }
        switch mode {
        case .partner:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .selfPortrait:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    // UNVERIFIED (2026-09-20, written on Windows): `AVCaptureDeviceDirectionCoordinator`'s
    // initializer signature per the spec is `(view:deviceTypes:changeHandler:)`. The `view:`
    // parameter presumably wants the UIView hosting the live preview, so the coordinator can
    // reason about the view's screen (inner vs. outer); `CameraService` owns no view, so `nil` is
    // passed here. If the real SDK requires a non-optional view, this construction needs to move
    // to wherever the preview `UIView`/`AVCaptureVideoPreviewLayer` lives instead.
    @available(iOS 27.1, *)
    private func selectDuoDevice(for mode: CaptureMode) -> AVCaptureDevice? {
        let coordinator: AVCaptureDeviceDirectionCoordinator
        if let existing = directionCoordinator as? AVCaptureDeviceDirectionCoordinator {
            coordinator = existing
        } else {
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera, .builtInDualWideCamera,
            ]
            // `[weak self]`: the coordinator is now owned by `self`, so a strong capture here
            // would cycle.
            coordinator = AVCaptureDeviceDirectionCoordinator(view: nil, deviceTypes: deviceTypes) { [weak self] _ in
                self?.sessionQueue.async { self?.reconfigureInput() }
            }
            directionCoordinator = coordinator
        }
        return selectDevice(from: coordinator, mode: mode)
    }

    // UNVERIFIED (2026-09-20, written on Windows): the shape of whatever map the direction
    // coordinator exposes from device → facing side, and the `.away`/`.toward` case names.
    // Isolated in this one method (per the spec) so the rest of the class doesn't depend on the
    // exact API once it's checked against the real SDK. `.away` = faces away from the inner
    // display the photographer looks at (partner mode); `.toward` = faces toward it (self mode).
    @available(iOS 27.1, *)
    private func selectDevice(from coordinator: AVCaptureDeviceDirectionCoordinator, mode: CaptureMode) -> AVCaptureDevice? {
        let wanted: AVCaptureDeviceDirectionCoordinator.Facing = mode == .partner ? .away : .toward
        return coordinator.devices.first { coordinator.facing(for: $0) == wanted }
    }

    // MARK: - Adjustments

    /// Exposure and white balance are hardware knobs, applied here. Contrast has no device
    /// equivalent — it's applied downstream in `FrameProcessor`/`PhotoWriter` via Core Image.
    ///
    /// Only the knob that actually changed since the last call is touched: a filter-only change
    /// (say) still calls this with the same `exposureEV`/`warmthKelvin` as before, and locking
    /// white balance unconditionally on every call would knock the camera from auto WB to a fixed
    /// 5500 K the moment *anything* changed, not just warmth.
    func apply(_ adjustments: Adjustments) {
        sessionQueue.async { [self] in
            guard let device = videoDeviceInput?.device else { return }
            let setExposure = adjustments.exposureEV != lastAppliedAdjustments.exposureEV
            let setWarmth = adjustments.warmthKelvin != lastAppliedAdjustments.warmthKelvin
            lastAppliedAdjustments = adjustments
            applyToDevice(device, adjustments: adjustments, setExposure: setExposure, setWarmth: setWarmth)
        }
    }

    /// sessionQueue-confined. `setWarmth` locks white balance to `adjustments.warmthKelvin`;
    /// leaving it `false` keeps the device on whatever WB mode (typically auto) it already has.
    private func applyToDevice(_ device: AVCaptureDevice, adjustments: Adjustments, setExposure: Bool, setWarmth: Bool) {
        guard setExposure || setWarmth else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if setExposure {
                device.setExposureTargetBias(Float(adjustments.exposureEV), completionHandler: nil)
            }

            if setWarmth {
                let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: Float(adjustments.warmthKelvin), tint: 0
                )
                var gains = device.deviceWhiteBalanceGains(for: values)
                gains.redGain = min(max(gains.redGain, 1), device.maxWhiteBalanceGain)
                gains.greenGain = min(max(gains.greenGain, 1), device.maxWhiteBalanceGain)
                gains.blueGain = min(max(gains.blueGain, 1), device.maxWhiteBalanceGain)
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            }
        } catch {
            // Best-effort: a device that can't be locked right now just keeps its last values.
        }
    }

    // MARK: - Capture

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                let settings = AVCapturePhotoSettings()
                let delegate = PhotoCaptureDelegate { [self] result in
                    sessionQueue.async { activePhotoCapture = nil }
                    continuation.resume(with: result)
                }
                activePhotoCapture = delegate
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

/// One-shot `AVCapturePhotoCaptureDelegate` adapter so `capturePhoto()` can be `async`.
/// `@unchecked Sendable`: `completion` fires exactly once, from AVFoundation's own photo-capture
/// callback, and touches no shared mutable state besides its own captured `let`.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            completion(.success(data))
        } else {
            completion(.failure(CameraServiceError.captureFailed))
        }
    }
}
