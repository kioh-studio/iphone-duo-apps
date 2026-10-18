import AVFoundation
import CoreGraphics
import Foundation
import Observation
import PoseCore

/// Which physical camera the session should use.
/// - `partner`: photographer holds the open Duo; the camera facing the subject feeds both the
///   inner preview and the outer accessory (`SubjectView`).
/// - `selfPortrait`: phone on a tripod, camera facing the same screen the user looks at — works
///   on every iPhone, not just the Duo. The main screen shows the `SubjectView` experience itself.
enum CaptureMode: String, CaseIterable, Codable, Sendable {
    case partner, selfPortrait
}

/// What the shutter makes: a still photo (pose-template guide) or a video (Frame / Script / Dance
/// guide on the subject's display).
enum ShootKind: String, CaseIterable, Codable, Sendable {
    case photo, video
}

/// What the subject's display shows while shooting video.
/// - `frame`: TikTok-safe framing box + step back / move hints.
/// - `script`: auto-scrolling teleprompter.
/// - `dance`: follow-along - a ghost skeleton from an imported reference video, played in sync with
///   its music, plus live match % and a final routine score.
/// - `interview`: partner mode only - both cameras recorded into one 9:16 split-screen clip (guest
///   on top, interviewer below), with question cards on the inner display.
enum VideoGuide: String, CaseIterable, Codable, Sendable {
    case frame, script, dance, interview

    var title: String {
        switch self {
        case .frame: return "Frame"
        case .script: return "Script"
        case .dance: return "Dance"
        case .interview: return "Interview"
        }
    }
}

enum RecordingPhase: Equatable {
    case idle, countdown(Int), recording, saving
}

/// A photo or video that was just saved to Photos - drives the "Saved to Photos" sheet.
/// `routineScore` is the dance recording's score (0...100), snapshotted at save time because
/// `StudioModel.lastRoutineScore` clears itself after `Theme.Motion.scoreHold`.
struct SavedClip: Identifiable, Equatable {
    let id = UUID()
    let mode: StudioMode
    let routineScore: Int?

    var subline: String {
        switch mode {
        case .pose, .selfie: return "Filter and contrast baked in."
        case .dance: return "Original music added back in."
        case .interview: return "Guest on top, you below."
        case .frame, .script: return "Filter baked in, ready to post."
        }
    }
}

/// One toast describing the gesture (or inner-UI action) that was just recognised, shown on the
/// outer display (and, in self-portrait mode, the main screen). `Identifiable` so `SubjectView`
/// can key a crossfade transition off `id` even when two gestures produce the same `text`.
struct GestureToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
}

/// Owns the camera pipeline, gesture recognition and all app state. Thin views read from this and
/// call into it; it never touches SwiftUI itself.
@MainActor
@Observable
final class StudioModel {
    enum CameraAuthorization: Equatable {
        case unknown, authorized, denied
    }

    private static let customTemplatesKey = "customPoseTemplates"
    private static let modeKey = "studioMode"
    private static let soloKey = "soloVideo"
    // Legacy keys: read once to migrate to "studioMode" (see `migratedMode`), never written again.
    private static let captureModeKey = "captureMode"
    private static let shootKindKey = "shootKind"
    private static let videoGuideKey = "videoGuide"
    private static let scriptTextKey = "teleprompterScript"
    private static let scriptSpeedKey = "teleprompterSpeed"
    private static let interviewQuestionsKey = "interviewQuestions"
    static let scriptSpeedRange: ClosedRange<Double> = 10...120

    // MARK: - Camera / pipeline

    #if targetEnvironment(simulator)
    /// The Simulator has no camera — `SimulatedFrameSource` feeds `receive(_:)` a synthetic
    /// frame/pose/gesture stream instead. See `DuoStudio/plan.md`'s Simulator section for what
    /// this does and doesn't prove.
    private let simulatedSource: SimulatedFrameSource
    #else
    private let frameProcessor = FrameProcessor()
    private let camera: CameraService
    #endif
    /// `captureSource` (not `capture`, to avoid colliding with the `capture()` method below) is
    /// either `camera` or `simulatedSource`, type-erased to the operations both share — see
    /// `CaptureSource`.
    private let captureSource: any CaptureSource
    private var recognizer = GestureRecognizer()

    var cameraAuthorization: CameraAuthorization = .unknown
    var errorMessage: String?

    // MARK: - Live frame state

    private(set) var previewImage: CGImage?
    /// Interview guide (dual-camera): the split-screen composite being recorded, for the inner
    /// preview. `nil` otherwise.
    private(set) var compositePreviewImage: CGImage?
    private(set) var livePose: Pose?
    private(set) var match: PoseMatch?
    /// Video kind + Frame guide: advice from the latest detection frame; `nil` otherwise.
    private(set) var frameHint: FrameHint?
    /// Video kind + Dance guide: the reference skeleton to draw - see `updateDanceGhost()`.
    private(set) var danceGhost: Pose?

    // MARK: - Studio state (filter / adjustments / zoom)

    private(set) var state = StudioState()

    // MARK: - Templates

    private(set) var customTemplates: [PoseTemplate]
    var selectedTemplateID: UUID?

    var templates: [PoseTemplate] { PoseLibrary.builtIn + customTemplates }
    var selectedTemplate: PoseTemplate? { templates.first { $0.id == selectedTemplateID } }

    /// The selected template's pose, as stored — templates live in the camera's upright,
    /// un-mirrored coordinate space (the same space `livePose` and the pose editor use), so a
    /// custom template built from "Use live pose" always matches itself. Both `StudioView` (whose
    /// preview is un-mirrored) and `SubjectView` (which mirrors this pose along with everything
    /// else it draws — see `mirroredPreview`) draw this same value.
    ///
    /// Video kind: only the Dance guide has a ghost (`danceGhost`); Frame and Script draw none.
    var displayTemplate: Pose? {
        switch shootKind {
        case .photo: return selectedTemplate?.pose
        case .video: return videoGuide == .dance ? danceGhost : nil
        }
    }

    // MARK: - Modes / toggles

    /// The single source of truth for what the app is doing (the mode dial). Ignored (reverted)
    /// while a recording is in progress. Persisted under "studioMode".
    var mode: StudioMode {
        didSet {
            guard mode != oldValue else { return }
            guard recordingPhase == .idle else {
                mode = oldValue
                return
            }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
            applyDerivedChange(from: Self.derive(oldValue, solo: isSolo))
        }
    }

    /// "Solo": the video modes that support it (Frame, Script, Dance) are shot alone on a stand, so
    /// the front camera and this screen are used instead of the Duo's outer display. Persisted under
    /// "soloVideo". Ignored (reverted) while recording.
    var isSolo: Bool {
        didSet {
            guard isSolo != oldValue else { return }
            guard recordingPhase == .idle else {
                isSolo = oldValue
                return
            }
            UserDefaults.standard.set(isSolo, forKey: Self.soloKey)
            applyDerivedChange(from: Self.derive(mode, solo: oldValue))
        }
    }

    // `captureMode`, `shootKind` and `videoGuide` are derived from `mode` + `isSolo`, so they can
    // never disagree with it.
    private struct Derived: Equatable {
        let kind: ShootKind
        let guide: VideoGuide
        let capture: CaptureMode
    }

    private static func derive(_ mode: StudioMode, solo: Bool) -> Derived {
        let videoCapture: CaptureMode = solo ? .selfPortrait : .partner
        switch mode {
        case .pose: return Derived(kind: .photo, guide: .frame, capture: .partner)
        case .selfie: return Derived(kind: .photo, guide: .frame, capture: .selfPortrait)
        case .frame: return Derived(kind: .video, guide: .frame, capture: videoCapture)
        case .script: return Derived(kind: .video, guide: .script, capture: videoCapture)
        case .dance: return Derived(kind: .video, guide: .dance, capture: videoCapture)
        case .interview: return Derived(kind: .video, guide: .interview, capture: .partner)
        }
    }

    private var derived: Derived { Self.derive(mode, solo: isSolo) }

    /// Photo for Pose / Selfie, video otherwise.
    var shootKind: ShootKind { derived.kind }

    /// The video modes' guide (`.frame` for the photo modes, where it is unused).
    var videoGuide: VideoGuide { derived.guide }

    /// Selfie, and Solo video, use the camera facing the user; everything else the partner camera.
    var captureMode: CaptureMode { derived.capture }

    /// Pushes a mode / solo change to the capture pipeline. The Interview guide needs the
    /// partner-mode camera pair, so it is entered after the camera switch and left before it.
    private func applyDerivedChange(from old: Derived) {
        let new = derived
        let videoChanged = new.kind != old.kind || new.guide != old.guide
        let captureChanged = new.capture != old.capture
        if new.guide == .interview {
            if captureChanged { applyCaptureMode() }
            if videoChanged { configureVideo() }
        } else {
            if videoChanged { configureVideo() }
            if captureChanged { applyCaptureMode() }
        }
    }

    private func applyCaptureMode() {
        // No subject on the other side of a fold when the user shoots from this screen.
        isOuterEnabled = captureMode == .partner
        captureSource.setMode(captureMode)
    }

    /// One-time migration from the old three-switch keys: Selfie = photo + self-portrait, Pose =
    /// photo + partner, a video guide = its mode (Solo when it was shot in self-portrait mode).
    private static func migratedMode(_ defaults: UserDefaults) -> (mode: StudioMode, solo: Bool) {
        let capture = defaults.string(forKey: captureModeKey).flatMap(CaptureMode.init(rawValue:)) ?? .partner
        let kind = defaults.string(forKey: shootKindKey).flatMap(ShootKind.init(rawValue:)) ?? .photo
        let guide = defaults.string(forKey: videoGuideKey).flatMap(VideoGuide.init(rawValue:)) ?? .frame
        switch kind {
        case .photo:
            return (capture == .selfPortrait ? StudioMode.selfie : StudioMode.pose, false)
        case .video:
            let solo = capture == .selfPortrait
            switch guide {
            case .frame: return (.frame, solo)
            case .script: return (.script, solo)
            case .dance: return (.dance, solo)
            // Interview was partner-only; a stale self-portrait pairing meant Frame.
            case .interview: return solo ? (StudioMode.frame, true) : (StudioMode.interview, false)
            }
        }
    }

    // MARK: - Video shoot kind

    /// Video kind + Interview guide.
    var isInterviewVideo: Bool { shootKind == .video && videoGuide == .interview }

    var scriptText: String {
        didSet { UserDefaults.standard.set(scriptText, forKey: Self.scriptTextKey) }
    }

    /// Teleprompter scroll speed in points per second.
    var scriptSpeed: Double {
        didSet {
            let clamped = min(max(scriptSpeed, Self.scriptSpeedRange.lowerBound), Self.scriptSpeedRange.upperBound)
            if clamped != scriptSpeed { scriptSpeed = clamped }
            UserDefaults.standard.set(scriptSpeed, forKey: Self.scriptSpeedKey)
        }
    }

    // MARK: - Script summaries (Library, mode panel)

    // ponytail: the teleprompter's real height depends on the outer display's width and font; this
    // assumes ~30 characters per line at ~56 pt per line. Measure the text if the estimate matters.
    private static let scriptCharsPerLine = 30
    private static let scriptPointsPerLine = 56.0

    /// First non-empty line of the script, trimmed; empty when there is no script.
    var scriptFirstLine: String {
        scriptText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    var scriptWordCount: Int {
        scriptText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Rough scroll time of the whole script at the current speed, in seconds.
    var scriptEstimatedSeconds: Int {
        let lines = scriptText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .reduce(0) { $0 + max(1, ($1.count + Self.scriptCharsPerLine - 1) / Self.scriptCharsPerLine) }
        guard scriptWordCount > 0, scriptSpeed > 0 else { return 0 }
        return Int((Double(lines) * Self.scriptPointsPerLine / scriptSpeed).rounded())
    }

    // MARK: - Interview

    /// The questions as the user typed them (one per line), persisted as-is so a trailing newline
    /// survives while typing; `interviewQuestions` is the cleaned list.
    var interviewQuestionsText: String {
        didSet {
            UserDefaults.standard.set(interviewQuestionsText, forKey: Self.interviewQuestionsKey)
            currentQuestionIndex = min(currentQuestionIndex, max(interviewQuestions.count - 1, 0))
        }
    }

    /// Non-empty lines of `interviewQuestionsText`, trimmed.
    var interviewQuestions: [String] {
        interviewQuestionsText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Not persisted; reset to 0 on each recording start.
    private(set) var currentQuestionIndex = 0

    var currentQuestion: String? {
        let questions = interviewQuestions
        return questions.indices.contains(currentQuestionIndex) ? questions[currentQuestionIndex] : nil
    }

    /// "2/7" (1-based), empty when there are no questions.
    var questionReadout: String {
        let count = interviewQuestions.count
        return count == 0 ? "" : "\(min(currentQuestionIndex, count - 1) + 1)/\(count)"
    }

    var canGoToPreviousQuestion: Bool { currentQuestionIndex > 0 }
    var canGoToNextQuestion: Bool { currentQuestionIndex < interviewQuestions.count - 1 }

    func nextQuestion() {
        currentQuestionIndex = min(currentQuestionIndex + 1, max(interviewQuestions.count - 1, 0))
    }

    func previousQuestion() {
        currentQuestionIndex = max(currentQuestionIndex - 1, 0)
    }

    /// False when this iPhone can't record both cameras at once, so the Interview guide records
    /// the guest camera only (reported by the capture source; assumed true until it says otherwise).
    private(set) var interviewDualAvailable = true

    private(set) var recordingPhase: RecordingPhase = .idle
    /// `ProcessInfo.systemUptime` when the current recording began (`nil` otherwise). Views read
    /// the clock inside a `TimelineView` and ask `recordingElapsed(at:)`, so nothing here ticks.
    private(set) var recordingStartUptime: TimeInterval?
    /// Non-nil while a reference video is being imported (0...1).
    private(set) var importProgress: Double?
    /// The finished dance recording's score (0...100), shown for `Theme.Motion.scoreHold` seconds.
    private(set) var lastRoutineScore: Int?
    /// Set after a photo or video was saved to Photos; the "Saved to Photos" sheet binds to it and
    /// clears it on dismiss.
    var lastSaved: SavedClip?

    private(set) var routines: [DanceRoutine]
    var selectedRoutineID: UUID?
    var selectedRoutine: DanceRoutine? { routines.first { $0.id == selectedRoutineID } }

    /// True during the countdown and the recording itself - the stretch where gestures are off and
    /// the subject's display hides its gesture HUD.
    var isRecordingActive: Bool {
        switch recordingPhase {
        case .countdown, .recording: return true
        case .idle, .saving: return false
        }
    }

    /// The number being counted down (3, 2, 1), `nil` outside the countdown.
    var countdownValue: Int? {
        if case .countdown(let value) = recordingPhase { return value }
        return nil
    }

    @ObservationIgnored private var scorer = DanceScorer()
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var activeRoutine: DanceRoutine?
    @ObservationIgnored private var recordingTask: Task<Void, Never>?
    @ObservationIgnored private var autoStopTask: Task<Void, Never>?
    @ObservationIgnored private var scoreClearTask: Task<Void, Never>?
    @ObservationIgnored private var micAuthorized = false
    @ObservationIgnored private var micRequested = false

    /// Bound to `CameraCaptureAccessory(isEnabled:)`. Forced off in self-portrait mode, where
    /// there's no subject on the other side of a fold to show it to.
    var isOuterEnabled = true {
        didSet {
            guard isOuterEnabled, captureMode == .selfPortrait else { return }
            isOuterEnabled = false
        }
    }
    var isOuterAvailable = false
    var gesturesEnabled = true

    private(set) var lastGesture: GestureToast?
    private var gestureClearTask: Task<Void, Never>?

    private(set) var isCapturing = false
    /// Bumped on every `capture()`; views drive both the shutter-flash overlay and the capture
    /// haptic (`.sensoryFeedback(_:trigger:)`) off this.
    private(set) var flashTrigger = 0

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.customTemplatesKey),
           let decoded = try? JSONDecoder().decode([PoseTemplate].self, from: data) {
            customTemplates = decoded
        } else {
            customTemplates = []
        }
        selectedTemplateID = PoseLibrary.builtIn.first?.id

        // Locals, not `self.mode`: an `@Observable` property must not be read before every stored
        // property is initialised.
        let initialMode: StudioMode
        let initialSolo: Bool
        if let saved = defaults.string(forKey: Self.modeKey).flatMap(StudioMode.init(rawValue:)) {
            initialMode = saved
            initialSolo = defaults.bool(forKey: Self.soloKey)
        } else {
            let migrated = Self.migratedMode(defaults)
            initialMode = migrated.mode
            initialSolo = migrated.solo
            defaults.set(initialMode.rawValue, forKey: Self.modeKey)
            defaults.set(initialSolo, forKey: Self.soloKey)
        }
        mode = initialMode
        isSolo = initialSolo
        scriptText = defaults.string(forKey: Self.scriptTextKey) ?? ""
        interviewQuestionsText = defaults.string(forKey: Self.interviewQuestionsKey) ?? ""
        let savedSpeed = defaults.object(forKey: Self.scriptSpeedKey) as? Double ?? 40
        scriptSpeed = min(max(savedSpeed, Self.scriptSpeedRange.lowerBound), Self.scriptSpeedRange.upperBound)
        let loadedRoutines = RoutineStore.load()
        routines = loadedRoutines
        selectedRoutineID = loadedRoutines.first?.id

        #if targetEnvironment(simulator)
        let source = SimulatedFrameSource()
        simulatedSource = source
        captureSource = source
        #else
        let cameraService = CameraService(frameProcessor: frameProcessor)
        camera = cameraService
        captureSource = cameraService
        #endif
        // `didSet` doesn't fire for the assignments above, so the capture source needs to be told
        // the loaded mode explicitly.
        isOuterEnabled = captureMode == .partner
        captureSource.setMode(captureMode)
        #if targetEnvironment(simulator)
        simulatedSource.model = self
        #else
        frameProcessor.model = self
        #endif
        captureSource.setDualCaptureHandler { [weak self] available in
            Task { @MainActor in self?.interviewDualAvailable = available }
        }
    }

    // MARK: - Lifecycle

    func requestCameraAccess() async {
        #if targetEnvironment(simulator)
        // No AVFoundation permission prompt makes sense against a synthetic source — the
        // Simulator has no camera to authorize in the first place.
        cameraAuthorization = .authorized
        captureSource.start()
        configureVideo()
        #else
        let granted = await CameraService.requestAuthorization()
        cameraAuthorization = granted ? .authorized : .denied
        if granted {
            captureSource.start()
            configureVideo()
        }
        #endif
    }

    func stop() {
        stopRecordingIfNeeded()
        captureSource.stop()
    }

    /// Forwarded from `CameraDirectionAnchor`'s coordinator change handler (`DUO_DIRECTION_COORDINATOR`
    /// builds only) whenever the Duo's forward/backward-facing devices change. No-op in the
    /// Simulator, which has neither a direction coordinator nor a real camera to route these IDs to.
    func updateCameraDirections(forwardIDs: [String], backwardIDs: [String]) {
        #if !targetEnvironment(simulator)
        camera.setDirectionalDevices(forwardIDs: forwardIDs, backwardIDs: backwardIDs)
        #endif
    }

    // MARK: - Frame ingestion

    /// Called once per processed frame, hopped onto `MainActor` by `FrameProcessor`. The preview
    /// image updates every frame; `livePose`/`match` only update on Vision-detection frames (every
    /// 3rd — see `FrameProcessor`), since `result.pose` is always `nil` on the frames in between and
    /// clearing the skeleton on 2 out of every 3 frames is what caused the flicker.
    ///
    /// Video kind adds: the Frame guide's `frameHint` (detection frames), the Dance guide's
    /// `danceGhost` (every frame, so it moves smoothly with the music), and routine scoring
    /// (detection frames, while recording). Gestures are ignored for as long as a countdown, a
    /// recording or a save is in progress.
    func receive(_ result: FrameResult) {
        previewImage = result.image
        compositePreviewImage = result.compositePreview
        if result.isDetectionFrame {
            livePose = result.pose
            frameHint = shootKind == .video && videoGuide == .frame ? FrameGuide.hint(for: result.pose) : nil
            match = computeMatch(livePose: result.pose)
        }
        updateDanceGhost()

        guard result.isDetectionFrame, recordingPhase == .idle, gesturesEnabled,
              let hand = result.hand, let event = recognizer.feed(hand) else { return }
        apply(event)
    }

    private func computeMatch(livePose: Pose?) -> PoseMatch? {
        guard let livePose else { return nil }
        switch shootKind {
        case .photo:
            guard let template = displayTemplate else { return nil }
            return PoseMatcher.match(live: livePose, template: template)
        case .video:
            // Only a dance recording scores; `t` is the reference player's clock (the music is
            // the clock), not wall time.
            guard videoGuide == .dance, recordingPhase == .recording, let routine = activeRoutine,
                  let t = playerTime() else { return nil }
            return scorer.record(live: livePose, at: t, routine: routine)
        }
    }

    /// The reference player's current time in seconds, `nil` if there is no player or no valid time.
    private func playerTime() -> Double? {
        guard let player else { return nil }
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : nil
    }

    /// Dance guide ghost. While recording: the routine's pose at the music's current time, moved
    /// and scaled onto the dancer (`PoseAligner`) so it is drawn over them - unaligned if no live
    /// pose yet. While idle (including the countdown): the routine's opening pose, as a preview.
    private func updateDanceGhost() {
        guard shootKind == .video, videoGuide == .dance, let routine = activeRoutine ?? selectedRoutine else {
            if danceGhost != nil { danceGhost = nil }
            return
        }
        let t = recordingPhase == .recording ? (playerTime() ?? 0) : 0
        guard let template = routine.pose(at: t) else {
            danceGhost = nil
            return
        }
        if recordingPhase == .recording, let livePose {
            danceGhost = PoseAligner.align(template, to: livePose)
        } else {
            danceGhost = template
        }
    }

    // MARK: - Gesture / manual parameter changes

    /// Applies a `GestureEvent` from a recognised hand gesture, through the one path (this method
    /// and `finishStateChange`) that every state change — gesture or inner-UI — funnels through,
    /// so both sources stay in sync with the camera and `FrameProcessor`.
    private func apply(_ event: GestureEvent) {
        state.apply(event)
        finishStateChange(toast(for: event))
    }

    private func finishStateChange(_ toast: GestureToast) {
        captureSource.apply(state.adjustments)
        #if targetEnvironment(simulator)
        simulatedSource.updateFilter(state.filter, contrast: state.adjustments.contrast)
        #else
        frameProcessor.updateFilter(state.filter, contrast: state.adjustments.contrast)
        #endif
        lastGesture = toast
        scheduleGestureClear()
    }

    private func toast(for event: GestureEvent) -> GestureToast {
        switch event {
        case .nextFilter, .previousFilter:
            return GestureToast(text: state.filter.displayName, symbol: "camera.filters")
        case .zoom(let factor):
            let symbol = factor >= 1 ? "plus.magnifyingglass" : "minus.magnifyingglass"
            return GestureToast(text: String(format: "%.1f×", state.outerZoom), symbol: symbol)
        case .nextParameter:
            return GestureToast(text: state.selectedParameter.rawValue.capitalized, symbol: "hand.raised.fill")
        case .adjust:
            return GestureToast(text: state.adjustments.formatted(state.selectedParameter), symbol: "hand.point.up.left.fill")
        }
    }

    private func scheduleGestureClear() {
        gestureClearTask?.cancel()
        let id = lastGesture?.id
        gestureClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, self.lastGesture?.id == id else { return }
            self.lastGesture = nil
        }
    }

    // MARK: - Inner-UI setters (go through the same `finishStateChange` path as gestures)

    func setFilter(_ filter: StudioFilter) {
        guard filter != state.filter else { return }
        state.filter = filter
        finishStateChange(GestureToast(text: state.filter.displayName, symbol: "camera.filters"))
    }

    /// Direct continuous set for the Sliders in `AdjustmentsView` (gesture-driven steps go through
    /// `apply(.adjust(step:))` above instead). Also makes `parameter` the selected one, so a
    /// gesture picking up right after a manual tweak continues adjusting the same value.
    func setAdjustment(_ parameter: StudioParameter, to value: Double) {
        state.selectedParameter = parameter
        switch parameter {
        case .exposure: state.adjustments.exposureEV = value
        case .contrast: state.adjustments.contrast = value
        case .warmth: state.adjustments.warmthKelvin = value
        }
        finishStateChange(GestureToast(text: state.adjustments.formatted(parameter), symbol: "hand.point.up.left.fill"))
    }

    // MARK: - Templates

    func select(template: PoseTemplate) {
        selectedTemplateID = template.id
    }

    /// A new, unsaved template to open in the pose editor: the live pose if there is one.
    func newTemplateDraft() -> PoseTemplate {
        PoseTemplate(name: "New Template", pose: livePose ?? PoseLibrary.builtIn.first!.pose)
    }

    func saveCustom(_ template: PoseTemplate) {
        var saved = template
        saved.isBuiltIn = false
        if let index = customTemplates.firstIndex(where: { $0.id == saved.id }) {
            customTemplates[index] = saved
        } else {
            customTemplates.append(saved)
        }
        persistCustomTemplates()
        select(template: saved)
    }

    func deleteCustom(_ template: PoseTemplate) {
        guard !template.isBuiltIn else { return }
        customTemplates.removeAll { $0.id == template.id }
        persistCustomTemplates()
        if selectedTemplateID == template.id {
            selectedTemplateID = PoseLibrary.builtIn.first?.id
        }
    }

    private func persistCustomTemplates() {
        guard let data = try? JSONEncoder().encode(customTemplates) else { return }
        UserDefaults.standard.set(data, forKey: Self.customTemplatesKey)
    }

    // MARK: - Capture

    func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        flashTrigger += 1
        defer { isCapturing = false }
        do {
            let data = try await captureSource.capturePhoto()
            try await PhotoWriter.write(data, filter: state.filter, contrast: state.adjustments.contrast)
            lastSaved = SavedClip(mode: mode, routineScore: nil)
        } catch {
            errorMessage = "Couldn't save the photo."
        }
    }

    // MARK: - Video configuration

    /// Tells the capture source what the current kind/guide needs (preset, microphone, dual
    /// cameras). The microphone is used by the Frame, Script and Interview guides - Dance plays the
    /// reference music from the speaker and muxes it in afterwards, so it records no mic audio -
    /// and its permission is requested the first time one of those guides is entered. Denied: the
    /// video is simply silent.
    private func configureVideo() {
        #if !targetEnvironment(simulator)
        if shootKind == .video, videoGuide != .dance, !micRequested {
            micRequested = true
            Task { [weak self] in
                let granted = await CameraService.requestMicrophoneAuthorization()
                guard let self else { return }
                self.micAuthorized = granted
                self.pushVideoConfiguration()
            }
        }
        #endif
        pushVideoConfiguration()
    }

    private func pushVideoConfiguration() {
        let isVideo = shootKind == .video
        captureSource.setVideoConfiguration(
            isVideo: isVideo,
            recordsAudio: isVideo && videoGuide != .dance && micAuthorized,
            interview: isVideo && videoGuide == .interview
        )
    }

    // MARK: - Recording

    /// Seconds since the recording started (0 when not recording).
    func recordingElapsed(at uptime: TimeInterval) -> TimeInterval {
        guard let start = recordingStartUptime else { return 0 }
        return max(0, uptime - start)
    }

    /// "REC 00:12".
    func elapsedLabel(at uptime: TimeInterval) -> String {
        let seconds = Int(recordingElapsed(at: uptime))
        return String(format: "REC %02ld:%02ld", seconds / 60, seconds % 60)
    }

    /// How far the teleprompter text has scrolled up, in points.
    func scriptOffset(at uptime: TimeInterval) -> Double {
        recordingElapsed(at: uptime) * scriptSpeed
    }

    /// Remote shutter (volume buttons, Camera Control, Bluetooth remote): photo takes a photo,
    /// video starts/stops recording.
    func remoteShutter() async {
        switch shootKind {
        case .photo: await capture()
        case .video: toggleRecording()
        }
    }

    /// idle starts (after a 3-2-1 countdown), recording stops, a countdown is cancelled, a save in
    /// progress is ignored.
    func toggleRecording() {
        switch recordingPhase {
        case .idle: startRecording()
        case .recording: Task { await stopRecording() }
        case .countdown: cancelCountdown()
        case .saving: break
        }
    }

    /// Backgrounding / leaving the screen: end whatever is running.
    func stopRecordingIfNeeded() {
        switch recordingPhase {
        case .countdown: cancelCountdown()
        case .recording: Task { await stopRecording() }
        case .idle, .saving: break
        }
    }

    private func startRecording() {
        guard shootKind == .video, recordingPhase == .idle else { return }
        let routine: DanceRoutine?
        if videoGuide == .dance {
            guard let selected = selectedRoutine else {
                errorMessage = "Import a dance video first."
                return
            }
            guard FileManager.default.fileExists(atPath: RoutineStore.mediaURL(for: selected).path) else {
                errorMessage = "That dance video is missing. Import it again."
                return
            }
            routine = selected
        } else {
            routine = nil
        }
        // A hold timer left over from before the countdown must not fire the moment gestures
        // come back.
        recognizer = GestureRecognizer()
        lastRoutineScore = nil
        scoreClearTask?.cancel()
        currentQuestionIndex = 0
        activeRoutine = routine
        recordingPhase = .countdown(3)
        recordingTask = Task { [weak self] in await self?.runRecording(routine: routine) }
    }

    private func cancelCountdown() {
        recordingTask?.cancel()
        recordingTask = nil
        activeRoutine = nil
        recordingPhase = .idle
    }

    private func runRecording(routine: DanceRoutine?) async {
        for number in stride(from: 3, through: 1, by: -1) {
            recordingPhase = .countdown(number)
            try? await Task.sleep(for: .seconds(Theme.Motion.countdownStep))
            guard !Task.isCancelled else { return }
        }

        do {
            if let routine {
                try startPlayer(for: routine)
                scorer.reset()
                // UNVERIFIED (2026-10-18, written on Windows): async preroll(atRate:) overload
                _ = await player?.preroll(atRate: 1)
                guard !Task.isCancelled else {
                    teardownPlayer()
                    activeRoutine = nil
                    recordingPhase = .idle
                    return
                }
                try await captureSource.startRecording(includeAudio: false)
            } else {
                try await captureSource.startRecording(includeAudio: videoGuide != .dance && micAuthorized)
            }
        } catch {
            teardownPlayer()
            activeRoutine = nil
            errorMessage = error is CameraServiceError
                ? "Recording isn't supported in this simulator mode."
                : "Couldn't start recording."
            recordingPhase = .idle
            return
        }

        // Cancelled while the recorder was starting (e.g. the screen went away): undo it.
        guard !Task.isCancelled else {
            teardownPlayer()
            activeRoutine = nil
            if let url = try? await captureSource.stopRecording() { try? FileManager.default.removeItem(at: url) }
            recordingPhase = .idle
            return
        }

        // ponytail: recorder start and player.play() are a few ms apart; add an offset knob if
        // device testing shows audible drift between the muxed music and the picture.
        player?.play()
        recordingStartUptime = ProcessInfo.processInfo.systemUptime
        recordingPhase = .recording
        if let routine { scheduleAutoStop(after: routine.duration) }
    }

    /// Dance: stop when the reference video (and so the music) ends.
    private func scheduleAutoStop(after seconds: Double) {
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.stopRecording()
        }
    }

    /// Ends the recording, finishes the file (dance: muxes the reference music in), saves it to
    /// Photos and deletes the temp files. Any failure surfaces as one alert; the phase always ends
    /// back at `.idle`. A countdown in progress is simply cancelled.
    func stopRecording() async {
        switch recordingPhase {
        case .countdown:
            cancelCountdown()
            return
        case .recording:
            break
        case .idle, .saving:
            return
        }

        autoStopTask?.cancel()
        autoStopTask = nil
        recordingTask = nil
        let routine = activeRoutine
        teardownPlayer()
        recordingPhase = .saving
        recordingStartUptime = nil

        var tempURLs: [URL] = []
        var routineScore: Int?
        do {
            var url = try await captureSource.stopRecording()
            tempURLs.append(url)
            if let routine {
                let score = scorer.average.map { Int(($0 * 100).rounded()) }
                routineScore = score
                url = try await MovieComposer.replacingAudio(of: url, withAudioFrom: RoutineStore.mediaURL(for: routine))
                if !tempURLs.contains(url) { tempURLs.append(url) }
                showRoutineScore(score)
            }
            try await PhotoWriter.writeVideo(at: url)
            lastSaved = SavedClip(mode: mode, routineScore: routineScore)
        } catch {
            errorMessage = "Couldn't save the video."
        }
        // The Photos write moves the final file on success; whatever is left is a temp leftover.
        for url in tempURLs { try? FileManager.default.removeItem(at: url) }
        activeRoutine = nil
        recordingPhase = .idle
    }

    private func showRoutineScore(_ score: Int?) {
        lastRoutineScore = score
        scoreClearTask?.cancel()
        scoreClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.Motion.scoreHold))
            guard !Task.isCancelled else { return }
            self?.lastRoutineScore = nil
        }
    }

    // MARK: - Dance playback

    private func startPlayer(for routine: DanceRoutine) throws {
        // UNVERIFIED (2026-10-18, written on Windows): `.playback` for the music while an
        // `AVCaptureSession` (video only, no audio input) runs - assumed not to interrupt or
        // reconfigure the capture session; also plays through the silent switch.
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback)
        try audioSession.setActive(true)
        player = AVPlayer(url: RoutineStore.mediaURL(for: routine))
    }

    private func teardownPlayer() {
        guard let player else { return }
        player.pause()
        self.player = nil
        // Best-effort: hand the audio session back to whatever was playing before.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Routines

    /// Imports a reference dance video (a temp copy made by the picker - deleted afterwards) into
    /// a routine: skeleton timeline sampled on-device, video kept for playback and its music.
    func importRoutine(from url: URL) async {
        guard importProgress == nil else { return }
        importProgress = 0
        defer {
            importProgress = nil
            try? FileManager.default.removeItem(at: url)
        }
        do {
            let routine = try await RoutineImporter.importRoutine(from: url, name: "Routine \(routines.count + 1)") { [weak self] value in
                // Hops to the main actor; ignored if the import already finished.
                Task { @MainActor in
                    guard let self, self.importProgress != nil else { return }
                    self.importProgress = value
                }
            }
            routines.append(routine)
            RoutineStore.save(routines)
            selectedRoutineID = routine.id
        } catch RoutineImportError.tooLong {
            errorMessage = "That video is longer than \(Int(RoutineImporter.maxDuration)) seconds."
        } catch {
            errorMessage = "Couldn't import that video."
        }
    }

    /// "0:24 · 240 frames · Flipped" - the Library's routine row.
    func summary(of routine: DanceRoutine) -> String {
        let seconds = Int(routine.duration.rounded())
        let time = String(format: "%ld:%02ld", seconds / 60, seconds % 60)
        return "\(time) · \(routine.frames.count) frames · \(routine.isMirrored ? "Flipped" : "Not flipped")"
    }

    func select(routine: DanceRoutine) {
        guard recordingPhase == .idle else { return }
        selectedRoutineID = routine.id
    }

    /// Flip left/right, for tutorials filmed mirrored.
    func toggleMirror(_ routine: DanceRoutine) {
        guard recordingPhase == .idle, let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        routines[index].isMirrored.toggle()
        RoutineStore.save(routines)
    }

    func deleteRoutine(_ routine: DanceRoutine) {
        guard recordingPhase == .idle else { return }
        RoutineStore.delete(routine)
        routines.removeAll { $0.id == routine.id }
        RoutineStore.save(routines)
        if selectedRoutineID == routine.id {
            selectedRoutineID = routines.first?.id
        }
    }
}
