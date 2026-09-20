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
    private static let captureModeKey = "captureMode"

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
    private(set) var livePose: Pose?
    private(set) var match: PoseMatch?

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
    var displayTemplate: Pose? { selectedTemplate?.pose }

    // MARK: - Modes / toggles

    var captureMode: CaptureMode {
        didSet {
            guard captureMode != oldValue else { return }
            UserDefaults.standard.set(captureMode.rawValue, forKey: Self.captureModeKey)
            if captureMode == .selfPortrait {
                isOuterEnabled = false
            } else {
                isOuterEnabled = true
            }
            captureSource.setMode(captureMode)
        }
    }

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

        captureMode = defaults.string(forKey: Self.captureModeKey).flatMap(CaptureMode.init(rawValue:)) ?? .partner

        #if targetEnvironment(simulator)
        let source = SimulatedFrameSource()
        simulatedSource = source
        captureSource = source
        #else
        let cameraService = CameraService(frameProcessor: frameProcessor)
        camera = cameraService
        captureSource = cameraService
        #endif
        // `didSet` doesn't fire for the assignment above, so the capture source needs to be told
        // the loaded mode explicitly.
        captureSource.setMode(captureMode)
        #if targetEnvironment(simulator)
        simulatedSource.model = self
        #else
        frameProcessor.model = self
        #endif
    }

    // MARK: - Lifecycle

    func requestCameraAccess() async {
        #if targetEnvironment(simulator)
        // No AVFoundation permission prompt makes sense against a synthetic source — the
        // Simulator has no camera to authorize in the first place.
        cameraAuthorization = .authorized
        captureSource.start()
        #else
        let granted = await CameraService.requestAuthorization()
        cameraAuthorization = granted ? .authorized : .denied
        if granted { captureSource.start() }
        #endif
    }

    func stop() {
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
    func receive(_ result: FrameResult) {
        previewImage = result.image
        guard result.isDetectionFrame else { return }
        livePose = result.pose
        match = computeMatch(livePose: result.pose)

        guard gesturesEnabled, let hand = result.hand, let event = recognizer.feed(hand) else { return }
        apply(event)
    }

    private func computeMatch(livePose: Pose?) -> PoseMatch? {
        guard let livePose, let template = displayTemplate else { return nil }
        return PoseMatcher.match(live: livePose, template: template)
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
        } catch {
            errorMessage = "Couldn't save the photo."
        }
    }
}
