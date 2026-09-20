import SwiftUI
import AVKit
import PoseCore

/// The photographer-facing screen. In partner mode this is the inner-display control surface
/// (preview, template strip, shutter, filters/adjustments, outer/gesture toggles) with
/// `SubjectView` mirrored out to the Duo's outer display via `OuterDisplayAccessory`. In
/// self-portrait mode this screen instead reuses `SubjectView` itself as the backdrop, with a
/// minimal control layer (mode switch, template picker, shutter) on top — see the ADDENDUM.
struct StudioView: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var isAdjustmentsPresented = false
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
            // handling (volume buttons, Camera Control, Bluetooth remotes). Wired for both modes
            // per the ADDENDUM. No self-timer, no gesture shutter.
            //
            // `[model]`: an explicit capture list so the closure captures the `@Environment` value
            // itself rather than reading the (possibly nonisolated-context) `model` property off
            // `self` each time it's invoked.
            .onCameraCaptureEvent { [model] event in
                guard event.phase == .ended else { return }
                Task { await model.capture() }
            }
            .sensoryFeedback(.impact, trigger: model.flashTrigger)
            .onChange(of: model.flashTrigger) { _, _ in
                guard !reduceMotion else { return }
                flashOpacity = 1
                withAnimation(Theme.Motion.easeOut(Theme.Motion.shutterFlash)) { flashOpacity = 0 }
            }
            .sheet(isPresented: $isAdjustmentsPresented) {
                AdjustmentsView()
            }
            .sheet(item: $editingTemplate) { template in
                PoseEditorView(template: template)
            }
            .overlay {
                Theme.Palette.paper.opacity(flashOpacity).ignoresSafeArea().allowsHitTesting(false)
            }
            .alert("Couldn't save the photo", isPresented: isShowingSaveError) {
                Button("OK", role: .cancel) {}
            }
    }

    /// Bridges `model.errorMessage` (set on a failed `capture()`/save) to `.alert`'s `Bool`
    /// binding; dismissing the alert (button or swipe-away) clears the underlying message.
    private var isShowingSaveError: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in if !isPresented { model.errorMessage = nil } }
        )
    }

    @ViewBuilder
    private var content: some View {
        if model.cameraAuthorization == .denied {
            deniedState
        } else {
            switch model.captureMode {
            case .partner:
                partnerLayout
            case .selfPortrait:
                selfPortraitLayout
            }
        }
    }

    // MARK: - Partner mode

    private var partnerLayout: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()
            preview.ignoresSafeArea()
            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = model.previewImage {
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
                } else {
                    Color.black
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: Theme.Space.md) {
            modeSwitch

            Button {
                model.isOuterEnabled.toggle()
            } label: {
                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
            }
            .disabled(!model.isOuterAvailable)
            .opacity(model.isOuterAvailable ? 1 : 0.4)
            .accessibilityLabel("Outer display")
            .accessibilityValue(model.isOuterEnabled ? "On" : "Off")
            .accessibilityHint(model.isOuterAvailable ? "" : "Not available on this iPhone")

            Button {
                model.gesturesEnabled.toggle()
            } label: {
                Image(systemName: model.gesturesEnabled ? "hand.raised" : "hand.raised.slash")
            }
            .accessibilityLabel("Gesture control")
            .accessibilityValue(model.gesturesEnabled ? "On" : "Off")

            Spacer()

            matchReadout
        }
        .font(Theme.TypeFace.body)
        .foregroundStyle(Theme.Palette.ink)
        .buttonStyle(PressableStyle())
        .padding(Theme.Space.sm)
        .background(Theme.Palette.scrim, in: Capsule())
        .padding(Theme.Space.md)
    }

    private var modeSwitch: some View {
        HStack(spacing: Theme.Space.xs) {
            modeButton(.partner, symbol: "person.2", label: "Partner mode")
            modeButton(.selfPortrait, symbol: "person.crop.square", label: "Self-portrait mode")
        }
    }

    private func modeButton(_ mode: CaptureMode, symbol: String, label: String) -> some View {
        let isSelected = model.captureMode == mode
        return Button {
            model.captureMode = mode
        } label: {
            Image(systemName: symbol)
                .frame(width: Theme.Space.hitTarget, height: Theme.Space.hitTarget)
                .foregroundStyle(isSelected ? Theme.Palette.accent : Theme.Palette.neutral)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var matchReadout: some View {
        Group {
            if let match = model.match {
                let percent = Int((match.score * 100).rounded())
                Text("\(percent)%")
                    .accessibilityValue("\(percent) percent match")
            } else {
                Text("—")
                    .accessibilityValue("No pose detected")
            }
        }
        .font(Theme.TypeFace.readout)
        .foregroundStyle(Theme.Palette.accent)
        .accessibilityLabel("Pose match")
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Space.md) {
            templateStrip
            HStack {
                Button {
                    isAdjustmentsPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: Theme.Space.hitTarget, height: Theme.Space.hitTarget)
                }
                .accessibilityLabel("Adjustments")

                Spacer()
                shutterButton
                Spacer()

                Color.clear.frame(width: Theme.Space.hitTarget, height: Theme.Space.hitTarget)
            }
            .padding(.horizontal, Theme.Space.lg)
        }
        .font(Theme.TypeFace.body)
        .foregroundStyle(Theme.Palette.ink)
        .buttonStyle(PressableStyle())
        .padding(.bottom, Theme.Space.lg)
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

    private var templateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(model.templates) { template in
                    templateChip(template)
                }
                Button("Edit") { editingTemplate = model.selectedTemplate }
                    .disabled(model.selectedTemplate == nil)
                Button {
                    editingTemplate = newTemplate()
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
            .padding(.horizontal, Theme.Space.md)
        }
        .font(Theme.TypeFace.label)
        .foregroundStyle(Theme.Palette.ink)
        .buttonStyle(PressableStyle())
    }

    private func templateChip(_ template: PoseTemplate) -> some View {
        let isSelected = model.selectedTemplateID == template.id
        return Button {
            model.select(template: template)
        } label: {
            Text(template.name)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .background(isSelected ? Theme.Palette.accent : Theme.Palette.paper3, in: Capsule())
                .foregroundStyle(isSelected ? Theme.Palette.paper : Theme.Palette.ink)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            if !template.isBuiltIn {
                Button("Delete", role: .destructive) { model.deleteCustom(template) }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func newTemplate() -> PoseTemplate {
        PoseTemplate(name: "New Template", pose: model.livePose ?? PoseLibrary.builtIn.first!.pose)
    }

    // MARK: - Self-portrait mode (main screen reuses SubjectView)

    private var selfPortraitLayout: some View {
        ZStack {
            SubjectView(isOuterDisplay: false)
            VStack {
                HStack {
                    modeSwitch
                        .padding(Theme.Space.sm)
                        .background(Theme.Palette.scrim, in: Capsule())
                    Spacer()
                }
                .padding(Theme.Space.md)
                Spacer()
                HStack {
                    templatePickerButton
                    Spacer()
                    shutterButton
                    Spacer()
                    Color.clear.frame(width: Theme.Space.hitTarget, height: Theme.Space.hitTarget)
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.lg)
            }
        }
    }

    private var templatePickerButton: some View {
        Menu {
            ForEach(model.templates) { template in
                Button(template.name) { model.select(template: template) }
            }
        } label: {
            Image(systemName: "figure.stand")
                .frame(width: Theme.Space.hitTarget, height: Theme.Space.hitTarget)
                .foregroundStyle(Theme.Palette.ink)
        }
        .accessibilityLabel("Choose template")
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
