import AVFoundation
import PoseCore

enum CameraServiceError: Error {
    case captureFailed
}

/// Wraps the `AVCaptureSession` that feeds the live preview, the pose/hand pipeline (via
/// `FrameProcessor`) and photo capture.
///
/// `@unchecked Sendable`: every stored mutable property (`session`, `videoDeviceInput`, `mode`,
/// `isConfigured`, `activePhotoCapture`, `forwardDeviceIDs`, `backwardDeviceIDs`,
/// `rotationCoordinator`, `lastAppliedAdjustments`) is only ever touched from `sessionQueue`, a
/// private serial queue — never from `MainActor` or from `videoQueue` (which only ever sees the
/// already-configured, effectively-immutable `AVCaptureVideoDataOutput`). Every public method
/// re-enters `sessionQueue` before touching state, so nothing here is read concurrently with a
/// write.
final class CameraService: NSObject, CaptureSource, @unchecked Sendable {
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
    /// Device unique IDs reported by the direction coordinator (see `CameraDirectionAnchor`,
    /// gated behind `DUO_DIRECTION_COORDINATOR`): "forward" faces the same view the photographer
    /// looks at, "backward" faces away from it. Empty until the flag is enabled and the
    /// coordinator's change handler has fired at least once — `selectDevice(for:)` falls back to
    /// the classic wide-angle cameras until then.
    private var forwardDeviceIDs: [String] = []
    private var backwardDeviceIDs: [String] = []
    /// Horizon-level rotation for photo capture only — the live preview instead gets a fixed
    /// `videoRotationAngle` (see `configureConnections()`). Tied to one device, so it's recreated
    /// alongside `videoDeviceInput` in `addInput(for:)` and `reconfigureInput()`.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
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

    /// Called by `CameraDirectionAnchor`'s coordinator change handler with the Duo's current
    /// forward/backward-facing device IDs. `configureSession()` may already have picked a fallback
    /// device before the coordinator had a live view to report from, so a `reconfigureInput()`
    /// re-evaluates the pick once real IDs arrive.
    func setDirectionalDevices(forwardIDs: [String], backwardIDs: [String]) {
        sessionQueue.async { [self] in
            forwardDeviceIDs = forwardIDs
            backwardDeviceIDs = backwardIDs
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

        configureConnections()
    }

    private func addInput(for mode: CaptureMode) {
        guard let device = selectDevice(for: mode), let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
        }
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    }

    /// Swaps the active input for the device the current `mode` wants, without touching outputs.
    /// Also re-run whenever the direction coordinator reports new device IDs, so a Duo posture
    /// change (partner mode) picks up the same "which device does this mode want" logic.
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
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        configureConnections()

        // The new device starts on its own hardware defaults, so re-push exposure unconditionally;
        // white balance only if warmth was ever actually touched away from its default (otherwise
        // the new device should stay on auto WB too, same as `apply(_:)`'s own rule).
        let warmthTouched = lastAppliedAdjustments.warmthKelvin != Adjustments().warmthKelvin
        applyToDevice(device, adjustments: lastAppliedAdjustments, setExposure: true, setWarmth: warmthTouched)
    }

    /// Sets the video data output connection's rotation/mirroring so frames always arrive upright
    /// and un-mirrored, whichever physical camera is active — `FrameProcessor` no longer guesses an
    /// orientation from device position. Re-run after both `configureSession()` and
    /// `reconfigureInput()`, since swapping the input can hand the output a fresh connection.
    private func configureConnections() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
    }

    /// Partner mode wants the camera facing the subject (away from the photographer's inner-display
    /// view), so the outer display mirrors what the lens sees. Self-portrait mode wants the camera
    /// facing the same screen the user is looking at — the classic "selfie" camera. With
    /// `DUO_DIRECTION_COORDINATOR` enabled on iOS 27.1+ Duo hardware, `forwardDeviceIDs`/
    /// `backwardDeviceIDs` carry the coordinator's current picks (see `CameraDirectionAnchor`);
    /// everything else (non-Duo iPhones, the flag off, or no coordinator report yet) falls back to
    /// the classic wide cameras.
    private func selectDevice(for mode: CaptureMode) -> AVCaptureDevice? {
        let ids = mode == .partner ? backwardDeviceIDs : forwardDeviceIDs
        if let id = ids.first, let device = AVCaptureDevice(uniqueID: id) {
            return device
        }
        switch mode {
        case .partner:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .selfPortrait:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
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
                // Clamped: `exposureEV` (`Adjustments`) ranges -2...2, but a device's own bias range
                // can be narrower, and `setExposureTargetBias` throws an ObjC exception for a value
                // outside it.
                let bias = min(max(Float(adjustments.exposureEV), device.minExposureTargetBias), device.maxExposureTargetBias)
                device.setExposureTargetBias(bias, completionHandler: nil)
            }

            // Guarded: `setWhiteBalanceModeLocked(with:)` throws an ObjC exception (not a Swift
            // `throw`, so `catch` below can't save it) on a device that doesn't support custom-gain
            // white balance locking at all.
            if setWarmth, device.isLockingWhiteBalanceWithCustomDeviceGainsSupported {
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
                // Horizon-level rotation for this one shot, per the current device's coordinator —
                // the live preview's connection instead keeps the fixed angle from
                // `configureConnections()`.
                if let connection = photoOutput.connection(with: .video), let rotationCoordinator {
                    let angle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                }
                let settings = AVCapturePhotoSettings()
                let delegate = PhotoCaptureDelegate { [self] result in
                    sessionQueue.async { [self] in self.activePhotoCapture = nil }
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
