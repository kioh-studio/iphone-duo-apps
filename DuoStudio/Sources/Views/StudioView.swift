import SwiftUI
import AVKit
import PoseCore

/// The camera screen, one structure for every mode (top to bottom):
/// 1. the preview, with a top bar of toggles on it (Outer, Gestures, Solo, the MATCH / REC readout,
///    Skin);
/// 2. the mode panel (`ModePanelView`: templates, hint, script, routines or the question card);
/// 3. the mode dial (`ModeDialView`) with the mode's one-line summary;
/// 4. the bottom row: Library, the shutter / record button, Controls.
///
/// In partner modes the preview is the un-mirrored working view with `SkeletonOverlay`, and
/// `SubjectView` goes to the Duo's outer display via `OuterDisplayAccessory`. Selfie and Solo video
/// use `SubjectView` itself as the preview (the user is the subject), with the same panel, dial and
/// bottom row below it.
struct StudioView: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var isControlsPresented = false
    @State private var isLibraryPresented = false
    @State private var isSkinPickerPresented = false
    @State private var isScriptEditorPresented = false
    @State private var isQuestionsEditorPresented = false
    @State private var editingTemplate: PoseTemplate?
    @State private var flashOpacity: Double = 0

    var body: some View {
        content
            .background(CameraDirectionAnchor(model: model))
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear {
                model.stop()
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .modifier(OuterDisplayAccessory(model: model))
            // UNVERIFIED (2026-09-20, written on Windows): `.onCameraCaptureEvent { event in }`
            // (AVKit, iOS 18+) — exact modifier name and `event.phase` shape for remote-shutter
            // handling (volume buttons, Camera Control, Bluetooth remotes). Wired for every mode.
            // No self-timer, no gesture shutter.
            //
            // `[model]`: an explicit capture list so the closure captures the `@Environment` value
            // itself rather than reading the (possibly nonisolated-context) `model` property off
            // `self` each time it's invoked.
            .onCameraCaptureEvent { [model] event in
                guard event.phase == .ended else { return }
                Task { await model.remoteShutter() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.stopRecordingIfNeeded() }
            }
            .sensoryFeedback(.impact, trigger: model.flashTrigger)
            .onChange(of: model.flashTrigger) { _, _ in
                guard !reduceMotion else { return }
                flashOpacity = 1
                withAnimation(Theme.Motion.easeOut(Theme.Motion.shutterFlash)) { flashOpacity = 0 }
            }
            .sheet(isPresented: $isControlsPresented) {
                ControlsView()
            }
            .sheet(isPresented: $isLibraryPresented) {
                LibraryView()
            }
            .sheet(isPresented: $isSkinPickerPresented) {
                SkinPickerSheet()
            }
            .sheet(item: $editingTemplate) { template in
                PoseEditorView(template: template)
            }
            .sheet(isPresented: $isScriptEditorPresented) {
                ScriptEditorView()
            }
            .sheet(isPresented: $isQuestionsEditorPresented) {
                QuestionsEditorView()
            }
            .sheet(item: savedClip) { clip in
                SavedView(clip: clip)
            }
            .overlay {
                Theme.Palette.paper.opacity(flashOpacity).ignoresSafeArea().allowsHitTesting(false)
            }
            .alert(model.errorMessage ?? "", isPresented: isShowingSaveError) {
                Button("OK", role: .cancel) {}
            }
    }

    /// Bridges `model.errorMessage` (a failed photo/video save, import or recording start) to
    /// `.alert`'s `Bool` binding - the message itself is the alert's title; dismissing the alert
    /// (button or swipe-away) clears it.
    private var isShowingSaveError: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in if !isPresented { model.errorMessage = nil } }
        )
    }

    /// `.sheet(item:)` binding for the "Saved to Photos" sheet; dismissing clears it.
    private var savedClip: Binding<SavedClip?> {
        Binding(get: { model.lastSaved }, set: { model.lastSaved = $0 })
    }

    @ViewBuilder
    private var content: some View {
        if model.cameraAuthorization == .denied {
            deniedState
        } else {
            cameraLayout
        }
    }

    // MARK: - Camera layout

    private var cameraLayout: some View {
        VStack(spacing: 0) {
            previewArea
            controls
        }
        .background(Theme.Palette.paper.ignoresSafeArea())
    }

    private var previewArea: some View {
        ZStack(alignment: .top) {
            if model.captureMode == .selfPortrait {
                SubjectView(isOuterDisplay: false)
            } else {
                preview
            }
            topBar
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .padding(.horizontal, Theme.Space.md)
    }

    private var preview: some View {
        GeometryReader { proxy in
            ZStack {
                if model.isInterviewVideo, let image = model.compositePreviewImage ?? model.previewImage {
                    // Interview: exactly what is being recorded (the split-screen composite, or
                    // the guest camera alone in the fallback). No skeleton - it would not line up
                    // with the composite, and the guide shows none.
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else if let image = model.previewImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    SkeletonOverlay(
                        livePose: model.livePose, template: model.displayTemplate, match: model.match,
                        imageSize: CGSize(width: image.width, height: image.height)
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    if model.mode == .frame {
                        FrameGuideOverlay(hint: model.frameHint, imageSize: CGSize(width: image.width, height: image.height))
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                } else {
                    Theme.Palette.overlayBase
                }
            }
        }
    }

    // MARK: - Top bar

    /// Outer / Gestures / Solo toggles, then the MATCH or REC readout and the Skin button - each on
    /// a `scrim` capsule with `overlayInk`, since they sit on live video.
    private var topBar: some View {
        // Labelled chips when they fit, icon-only (same accessibility labels) on narrow widths.
        ViewThatFits(in: .horizontal) {
            topBarRow(labelled: true)
            topBarRow(labelled: false)
        }
        .buttonStyle(PressableStyle())
        .padding(Theme.Space.sm)
    }

    private func topBarRow(labelled: Bool) -> some View {
        HStack(spacing: Theme.Space.xs) {
            toggleChip("Outer", labelled: labelled, symbol: "rectangle.portrait.on.rectangle.portrait", isOn: model.isOuterEnabled) {
                model.isOuterEnabled.toggle()
            }
            .disabled(!model.isOuterAvailable || model.captureMode == .selfPortrait)
            .opacity(model.isOuterAvailable && model.captureMode == .partner ? 1 : Theme.Opacity.disabled)
            .accessibilityHint(model.isOuterAvailable ? "" : "Not available on this iPhone")

            toggleChip("Gestures", labelled: labelled, symbol: model.gesturesEnabled ? "hand.raised" : "hand.raised.slash", isOn: model.gesturesEnabled) {
                model.gesturesEnabled.toggle()
            }

            if model.mode.supportsSolo {
                toggleChip("Solo", labelled: labelled, symbol: "person.crop.square", isOn: model.isSolo) {
                    model.isSolo.toggle()
                }
                .disabled(model.recordingPhase != .idle)
            }

            Spacer(minLength: Theme.Space.xs)

            trailingReadout

            Button {
                isSkinPickerPresented = true
            } label: {
                Image(systemName: "paintpalette")
                    .frame(width: Theme.Space.hitTarget, height: Theme.Space.hitTarget)
                    .foregroundStyle(Theme.Palette.overlayInk)
                    .background(Theme.Palette.scrim, in: Capsule())
            }
            .accessibilityLabel("Change skin")
        }
    }

    private func toggleChip(_ title: String, labelled: Bool, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipLabel(title, symbol: symbol, labelled: labelled)
                .font(Theme.TypeFace.label)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(isOn ? Theme.Palette.overlayAccent : Theme.Palette.overlayInk)
                .padding(.horizontal, Theme.Space.sm)
                .frame(minWidth: Theme.Space.hitTarget, minHeight: Theme.Space.hitTarget)
                .background(Theme.Palette.scrim, in: Capsule())
        }
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    @ViewBuilder
    private func chipLabel(_ title: String, symbol: String, labelled: Bool) -> some View {
        if labelled {
            Label(title, systemImage: symbol).labelStyle(.titleAndIcon)
        } else {
            Label(title, systemImage: symbol).labelStyle(.iconOnly)
        }
    }

    /// `REC 00:12` while recording; otherwise the match % for the modes that score (Pose, Selfie,
    /// Dance); nothing for the others.
    @ViewBuilder
    private var trailingReadout: some View {
        if model.recordingPhase == .recording {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(model.elapsedLabel(at: ProcessInfo.processInfo.systemUptime))
                    .font(Theme.TypeFace.readout)
                    .foregroundStyle(Theme.Palette.overlayAccent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .readoutCapsule()
            }
        } else if model.mode.scoresMatch {
            matchReadout
                .readoutCapsule()
        }
    }

    private var matchReadout: some View {
        HStack(spacing: Theme.Space.xs) {
            Text("MATCH")
                .lineLimit(1)
                .fixedSize()
                .font(Theme.TypeFace.label)
                .tracking(Theme.TypeFace.labelTracking)
                .foregroundStyle(Theme.Palette.overlayMuted)
            if let match = model.match {
                let percent = Int((match.score * 100).rounded())
                Text("\(percent)%")
                    .font(Theme.TypeFace.readout)
                    .foregroundStyle(Theme.Palette.overlayAccent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityValue("\(percent) percent match")
            } else {
                Text("—")
                    .font(Theme.TypeFace.readout)
                    .foregroundStyle(Theme.Palette.overlayAccent)
                    .accessibilityValue("No pose detected")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pose match")
    }

    // MARK: - Controls (panel, dial, bottom row)

    private var controls: some View {
        VStack(spacing: Theme.Space.md) {
            ModePanelView(
                onNewPose: { editingTemplate = model.newTemplateDraft() },
                onEditScript: { isScriptEditorPresented = true },
                onEditQuestions: { isQuestionsEditorPresented = true }
            )
            ModeDialView()
            bottomRow
        }
        .padding(.top, Theme.Space.md)
        .padding(.bottom, Theme.Space.sm)
        .font(Theme.TypeFace.body)
        .foregroundStyle(Theme.Palette.ink)
        .buttonStyle(PressableStyle())
    }

    private var bottomRow: some View {
        HStack {
            sideButton("Library", symbol: "square.grid.2x2") { isLibraryPresented = true }
                .disabled(model.recordingPhase != .idle)
            Spacer()
            captureButton
            Spacer()
            sideButton("Controls", symbol: "slider.horizontal.3") { isControlsPresented = true }
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    private func sideButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xs) {
                Image(systemName: symbol)
                Text(title)
                    .font(Theme.TypeFace.control)
            }
            .frame(minWidth: Theme.Space.shutter - Theme.Space.md, minHeight: Theme.Space.hitTarget)
        }
    }

    @ViewBuilder
    private var captureButton: some View {
        switch model.shootKind {
        case .photo: shutterButton
        case .video: recordButton
        }
    }

    /// Same 76pt accent ring as the shutter; the inner `ink` circle becomes a rounded square
    /// (half size) while recording. Disabled only while the file is being saved - during the
    /// countdown a tap cancels it.
    private var recordButton: some View {
        let isRecording = model.recordingPhase == .recording
        let inner = Theme.Space.shutter - Theme.Space.md
        return Button {
            model.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Theme.Palette.accent, lineWidth: Theme.Stroke.shutterRing)
                    .frame(width: Theme.Space.shutter, height: Theme.Space.shutter)
                if isRecording {
                    RoundedRectangle(cornerRadius: Theme.Stroke.recordCorner)
                        .fill(Theme.Palette.ink)
                        .frame(width: inner / 2, height: inner / 2)
                } else {
                    Circle()
                        .fill(Theme.Palette.ink)
                        .frame(width: inner, height: inner)
                }
            }
        }
        .disabled(model.recordingPhase == .saving)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }

    private var shutterButton: some View {
        Button {
            Task { await model.capture() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Theme.Palette.accent, lineWidth: Theme.Stroke.shutterRing)
                    .frame(width: Theme.Space.shutter, height: Theme.Space.shutter)
                Circle()
                    .fill(Theme.Palette.ink)
                    .frame(width: Theme.Space.shutter - Theme.Space.md, height: Theme.Space.shutter - Theme.Space.md)
            }
        }
        .disabled(model.isCapturing)
        .accessibilityLabel("Take photo")
    }

    // MARK: - Camera denied

    private var deniedState: some View {
        VStack(spacing: Theme.Space.md) {
            Text("Camera access needed")
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.ink)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(Theme.Palette.accent)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.paper)
    }
}

private extension View {
    /// The top bar's readout capsule (MATCH %, REC 00:12): `scrim` behind, 44pt tall like its neighbours.
    @MainActor func readoutCapsule() -> some View {
        padding(.horizontal, Theme.Space.sm)
            .frame(minHeight: Theme.Space.hitTarget)
            .background(Theme.Palette.scrim, in: Capsule())
    }
}
