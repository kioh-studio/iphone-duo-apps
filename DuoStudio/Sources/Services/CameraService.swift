import AVFoundation
import PoseCore

enum CameraServiceError: Error {
    case captureFailed
    /// The Simulator's stick-figure fallback has no real frames to record.
    case recordingUnsupported
}

/// Wraps the `AVCaptureSession` that feeds the live preview, the pose/hand pipeline (via
/// `FrameProcessor`) and photo capture.
///
/// `@unchecked Sendable`: every stored mutable property (`session`, `videoDeviceInput`, `mode`,
/// `isConfigured`, `activePhotoCapture`, `forwardDeviceIDs`, `backwardDeviceIDs`,
/// `rotationCoordinator`, `lastAppliedAdjustments`, `isVideoShoot`, `recordsAudio`, `audioInput`,
/// `isInterview`, `dualActive`, `dualDisabled`, `interviewerInput`, `dualHandler`) is only ever touched from `sessionQueue`, a
/// private serial queue — never from `MainActor` or from `videoQueue` (which only ever sees the
/// already-configured, effectively-immutable `AVCaptureVideoDataOutput`). Every public method
/// re-enters `sessionQueue` before touching state, so nothing here is read concurrently with a
/// write. `session` itself is one of them: the Interview guide swaps it for an
/// `AVCaptureMultiCamSession` (and back), so it is a `var` replaced only on `sessionQueue`.
final class CameraService: NSObject, CaptureSource, @unchecked Sendable {
    private var session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "tech.kioh.duostudio.session")
    private let videoQueue = DispatchQueue(label: "tech.kioh.duostudio.video")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    /// Interview guide: the interviewer camera's output and its frame sink (latest frame only).
    private let secondaryOutput = AVCaptureVideoDataOutput()
    private let secondarySink = SecondaryFrameSink()
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
    /// Video shoot kind: 1080p preset (instead of `.photo`) and, when `recordsAudio`, a microphone
    /// input + audio data output. Set by `setVideoConfiguration`; applied by `configureSession()`
    /// (first build) or `applyVideoConfiguration()` (live session).
    private var isVideoShoot = false
    private var recordsAudio = false
    private var audioInput: AVCaptureDeviceInput?
    /// Interview guide requested (video kind + `.interview`), and whether the current `session` is
    /// really a dual-camera one. `dualDisabled`: dual mode failed to start once this run, so later
    /// rebuilds go straight to the guest-only fallback instead of retrying.
    private var isInterview = false
    private var dualActive = false
    private var dualDisabled = false
    private var interviewerInput: AVCaptureDeviceInput?
    private var dualHandler: (@Sendable (Bool) -> Void)?

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

    static func requestMicrophoneAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    func start() {
        sessionQueue.async { [self] in
            if !isConfigured {
                buildSession()
                isConfigured = true
            }
            guard !session.isRunning else { return }
            startSession()
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

    /// Photo shoot: `.photo` preset, no microphone. Video shoot: 1080p preset (portrait 1080×1920
    /// after the 90° connection rotation), plus the microphone when `recordsAudio`. Safe before the
    /// session is built — it just records the values for `configureSession()`.
    ///
    /// Interview (`interview` while `isVideo`): the session is rebuilt as a multi-camera one (or
    /// back). Never call this mid-recording - `StudioModel` guards that.
    func setVideoConfiguration(isVideo: Bool, recordsAudio: Bool, interview: Bool) {
        sessionQueue.async { [self] in
            let wantsInterview = isVideo && interview
            let changed = isVideoShoot != isVideo || self.recordsAudio != recordsAudio || isInterview != wantsInterview
            let interviewChanged = isInterview != wantsInterview
            isVideoShoot = isVideo
            self.recordsAudio = recordsAudio
            isInterview = wantsInterview
            guard isConfigured, changed else { return }
            // A dual session has manual connections, so any change (including the microphone
            // arriving) rebuilds it rather than patching it in place.
            if interviewChanged || dualActive {
                rebuildSession()
            } else {
                applyVideoConfiguration()
            }
        }
    }

    func setDualCaptureHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        sessionQueue.async { [self] in dualHandler = handler }
    }

    /// Starts writing processed frames (and mic audio, when `includeAudio` and an audio input is
    /// actually attached) to a temp `.mp4`. Hops through `sessionQueue` so it lands after any
    /// pending `setVideoConfiguration`.
    func startRecording(includeAudio: Bool) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
                frameProcessor.recorder.start(url: url, includeAudio: includeAudio && audioInput != nil)
                continuation.resume()
            }
        }
    }

    func stopRecording() async throws -> URL {
        try await frameProcessor.recorder.finish()
    }

    // MARK: - Session configuration (sessionQueue only)

    /// Builds `session` for the current request: the dual-camera Interview session when asked for
    /// and possible, otherwise the regular single-camera one (which is also the Interview
    /// guest-only fallback). Leaves the session configured but not started. Reports the outcome to
    /// `dualHandler` when Interview was requested.
    private func buildSession() {
        dualActive = false
        frameProcessor.setInterviewSink(nil)
        secondarySink.clear()
        if isInterview, !dualDisabled, let multi = makeDualSession() {
            session = multi
            dualActive = true
            configureConnections()
            frameProcessor.setInterviewSink(secondarySink)
        } else {
            session = AVCaptureSession()
            configureSession()
        }
        if isInterview { dualHandler?(dualActive) }
    }

    /// Starts `session`; if a dual session doesn't come up running, falls back to guest-only.
    private func startSession() {
        session.startRunning()
        guard dualActive, !session.isRunning else { return }
        // ponytail: one-way fallback for this run; retry (or lower activeFormat) if device testing
        // shows dual mode failing transiently.
        dualDisabled = true
        tearDown(session)
        buildSession()
        session.startRunning()
    }

    /// Replaces `session` (Interview entered/left, or the dual pair changed), restarting it if the
    /// old one was running.
    private func rebuildSession() {
        let wasRunning = session.isRunning
        tearDown(session)
        buildSession()
        if wasRunning { startSession() }
    }

    /// Stops `old` and detaches everything from it so the shared outputs can join the next session.
    private func tearDown(_ old: AVCaptureSession) {
        if old.isRunning { old.stopRunning() }
        old.beginConfiguration()
        for input in old.inputs { old.removeInput(input) }
        for output in old.outputs { old.removeOutput(output) }
        old.commitConfiguration()
        videoDeviceInput = nil
        interviewerInput = nil
        audioInput = nil
        rotationCoordinator = nil
    }

    private func configureSession() {
        session.beginConfiguration()
        applyPreset()
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

        updateAudio()
        configureConnections()
    }

    // MARK: - Interview: dual-camera session (sessionQueue only)

    /// Builds a configured `AVCaptureMultiCamSession`: guest camera -> `videoOutput` (the normal
    /// `FrameProcessor` path), interviewer camera -> `secondaryOutput` (-> `secondarySink`), mic ->
    /// `audioOutput`. Connections are made by hand (`...WithNoConnections` + explicit
    /// `AVCaptureConnection`s), as multi-camera sessions require. Returns `nil` - leaving no
    /// session state behind - when the device can't do it: no multi-cam support, the two cameras
    /// aren't a supported pair, a connection can't be made, or `hardwareCost` exceeds 1.0.
    /// No photo output: the Interview guide only records video.
    private func makeDualSession() -> AVCaptureMultiCamSession? {
        guard AVCaptureMultiCamSession.isMultiCamSupported,
              let guest = selectDevice(for: .partner), let interviewer = selectDevice(for: .selfPortrait),
              guest.uniqueID != interviewer.uniqueID, Self.isSupportedPair(guest, interviewer),
              let guestInput = try? AVCaptureDeviceInput(device: guest),
              let interviewerCameraInput = try? AVCaptureDeviceInput(device: interviewer)
        else { return nil }

        Self.selectMultiCamFormat(for: guest)
        Self.selectMultiCamFormat(for: interviewer)

        let multi = AVCaptureMultiCamSession()
        multi.beginConfiguration()

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(frameProcessor, queue: videoQueue)
        secondaryOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        secondaryOutput.alwaysDiscardsLateVideoFrames = true
        secondaryOutput.setSampleBufferDelegate(secondarySink, queue: videoQueue)

        var micInput: AVCaptureDeviceInput?
        if recordsAudio, let mic = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: mic) {
            micInput = input
        }

        guard multi.canAddInput(guestInput), multi.canAddInput(interviewerCameraInput),
              multi.canAddOutput(videoOutput), multi.canAddOutput(secondaryOutput)
        else {
            multi.commitConfiguration()
            tearDown(multi)
            return nil
        }
        multi.addInputWithNoConnections(guestInput)
        multi.addInputWithNoConnections(interviewerCameraInput)
        multi.addOutputWithNoConnections(videoOutput)
        multi.addOutputWithNoConnections(secondaryOutput)

        var wired = Self.connect(guestInput, device: guest, to: videoOutput, in: multi)
            && Self.connect(interviewerCameraInput, device: interviewer, to: secondaryOutput, in: multi)

        var audio: AVCaptureDeviceInput?
        if wired, let micInput, multi.canAddInput(micInput), multi.canAddOutput(audioOutput) {
            multi.addInputWithNoConnections(micInput)
            multi.addOutputWithNoConnections(audioOutput)
            audioOutput.setSampleBufferDelegate(frameProcessor, queue: videoQueue)
            if let port = micInput.ports.first(where: { $0.mediaType == .audio }) {
                let connection = AVCaptureConnection(inputPorts: [port], output: audioOutput)
                if multi.canAddConnection(connection) {
                    multi.addConnection(connection)
                    audio = micInput
                }
            }
            // A mic that can't be wired just means a silent interview; video still records.
        }
        multi.commitConfiguration()

        // UNVERIFIED (2026-10-18, written on Windows): `hardwareCost` / `systemPressureCost` are
        // read after commit; > 1.0 means the pair can't run together at the chosen formats.
        // ponytail: lowering activeFormat would keep dual working on more devices; fall back for now.
        wired = wired && multi.hardwareCost <= 1.0 && multi.systemPressureCost <= 1.0
        guard wired else {
            tearDown(multi)
            return nil
        }

        videoDeviceInput = guestInput
        interviewerInput = interviewerCameraInput
        audioInput = audio
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: guest, previewLayer: nil)
        return multi
    }

    /// UNVERIFIED (2026-10-18, written on Windows): `supportedMultiCamDeviceSets` is queried for
    /// wide/ultra-wide/TrueDepth device types only - whether the Duo's inner under-display camera
    /// (the interviewer) appears under one of these types is unknown; if not, dual mode is simply
    /// reported unavailable (guest-only fallback).
    private static func isSupportedPair(_ a: AVCaptureDevice, _ b: AVCaptureDevice) -> Bool {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTrueDepthCamera],
            mediaType: .video, position: .unspecified
        )
        return discovery.supportedMultiCamDeviceSets.contains { $0.contains(a) && $0.contains(b) }
    }

    /// Multi-camera sessions ignore `sessionPreset`; the device's own format has to be one that
    /// supports multi-cam. Picks the largest such format up to 1080p at 30 fps.
    /// UNVERIFIED (2026-10-18, written on Windows): the inner camera's 1080p limit, and that
    /// setting `activeFormat` before adding the input is the right order.
    private static func selectMultiCamFormat(for device: AVCaptureDevice) {
        let candidates = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return format.isMultiCamSupported
                && max(dimensions.width, dimensions.height) <= 1920
                && format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }
        }
        let best = candidates.max { lhs, rhs in
            let l = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let r = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return Int(l.width) * Int(l.height) < Int(r.width) * Int(r.height)
        }
        guard let best, (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        device.activeFormat = best
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
    }

    /// One manual video connection from `input`'s video port to `output`.
    private static func connect(
        _ input: AVCaptureDeviceInput, device: AVCaptureDevice, to output: AVCaptureVideoDataOutput,
        in session: AVCaptureMultiCamSession
    ) -> Bool {
        guard let port = input.ports(
            for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: device.position
        ).first else { return false }
        let connection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(connection) else { return false }
        session.addConnection(connection)
        return true
    }

    /// sessionQueue-confined; call inside a begin/commitConfiguration pair.
    private func applyPreset() {
        if isVideoShoot, session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if isVideoShoot {
            session.sessionPreset = .high
        } else {
            session.sessionPreset = .photo
        }
    }

    /// sessionQueue-confined; call inside a begin/commitConfiguration pair. Adds the microphone
    /// input + audio data output when this is a video shoot that records sound, removes them
    /// otherwise. The audio output's delegate queue is `videoQueue` — the same queue the video
    /// output uses — so the recorder sees audio and video buffers in capture order.
    private func updateAudio() {
        if isVideoShoot && recordsAudio {
            if audioInput == nil, let mic = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: mic), session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
            if audioInput != nil, !session.outputs.contains(audioOutput), session.canAddOutput(audioOutput) {
                // UNVERIFIED (2026-10-18, written on Windows): two outputs delivering to one serial
                // queue + one delegate object is the documented pattern, but not checked against a
                // running session.
                audioOutput.setSampleBufferDelegate(frameProcessor, queue: videoQueue)
                session.addOutput(audioOutput)
            }
        } else {
            if session.outputs.contains(audioOutput) { session.removeOutput(audioOutput) }
            if let input = audioInput {
                session.removeInput(input)
                audioInput = nil
            }
        }
    }

    private func applyVideoConfiguration() {
        session.beginConfiguration()
        applyPreset()
        updateAudio()
        session.commitConfiguration()
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
        if dualActive {
            // A dual session's inputs are wired by hand; swapping one in place isn't safe. Rebuild
            // only when the pair of cameras actually changed (not on every coordinator report).
            if selectDevice(for: .partner)?.uniqueID != videoDeviceInput?.device.uniqueID
                || selectDevice(for: .selfPortrait)?.uniqueID != interviewerInput?.device.uniqueID {
                rebuildSession()
            }
            return
        }
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
        // Interview: the interviewer camera's connection gets the same upright, un-mirrored rule.
        for output in dualActive ? [videoOutput, secondaryOutput] : [videoOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
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
                // The Interview session has no photo output.
                guard session.outputs.contains(photoOutput) else {
                    continuation.resume(throwing: CameraServiceError.captureFailed)
                    return
                }
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
