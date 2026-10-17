import SwiftUI
import PhotosUI
import PoseCore

/// Capsule-ish label shared by the mode panel's chips and the Library's tabs: `accent` fill with
/// `onAccent` text when selected, `paper3` with `ink` otherwise. 44pt minimum height.
struct ChipLabel: View {
    let title: String
    var isSelected = false

    var body: some View {
        Text(title)
            .font(Theme.TypeFace.control)
            .padding(.horizontal, Theme.Space.md)
            .frame(minHeight: Theme.Space.hitTarget)
            .background(
                isSelected ? Theme.Palette.accent : Theme.Palette.paper3,
                in: RoundedRectangle(cornerRadius: Theme.Radius.control)
            )
            .foregroundStyle(isSelected ? Theme.Palette.onAccent : Theme.Palette.ink)
    }
}

/// The one row between the preview and the mode dial; its content depends on the mode.
/// Pose / Selfie: template chips + "+ New pose" (Selfie adds the remote-shutter hint). Frame: a hint
/// line. Script: first script line, speed, Edit. Dance: routine chips + import. Interview: the
/// question card.
struct ModePanelView: View {
    @Environment(StudioModel.self) private var model
    @State private var pickerItem: PhotosPickerItem?

    let onNewPose: () -> Void
    let onEditScript: () -> Void
    let onEditQuestions: () -> Void

    var body: some View {
        content
            .font(Theme.TypeFace.control)
            .foregroundStyle(Theme.Palette.ink)
            .buttonStyle(PressableStyle())
            .frame(maxWidth: .infinity, minHeight: Theme.Layout.modePanelHeight, alignment: .center)
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .pose, .selfie:
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                templateStrip
                if model.mode == .selfie {
                    Text("Remote shutter: volume button, Camera Control or a Bluetooth remote.")
                        .font(Theme.TypeFace.label)
                        .foregroundStyle(Theme.Palette.muted)
                        .padding(.horizontal, Theme.Space.md)
                }
            }
        case .frame:
            Text(model.isSolo ? "Hints appear on this screen." : "Hints appear on the outer screen.")
                .foregroundStyle(Theme.Palette.muted)
                .padding(.horizontal, Theme.Space.md)
        case .script:
            scriptRow
        case .dance:
            danceRow
        case .interview:
            InterviewCardView(onEdit: onEditQuestions)
        }
    }

    // MARK: - Pose / Selfie

    private var templateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(model.templates) { template in
                    templateChip(template)
                }
                Button(action: onNewPose) {
                    ChipLabel(title: "+ New pose")
                }
            }
            .padding(.horizontal, Theme.Space.md)
        }
    }

    private func templateChip(_ template: PoseTemplate) -> some View {
        let isSelected = model.selectedTemplateID == template.id
        return Button {
            model.select(template: template)
        } label: {
            ChipLabel(title: template.name, isSelected: isSelected)
        }
        .contextMenu {
            if !template.isBuiltIn {
                Button("Delete", role: .destructive) { model.deleteCustom(template) }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Script

    private var scriptRow: some View {
        HStack(spacing: Theme.Space.sm) {
            let line = model.scriptFirstLine
            Text(line.isEmpty ? "No script yet" : line)
                .lineLimit(1)
                .foregroundStyle(line.isEmpty ? Theme.Palette.muted : Theme.Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(Int(model.scriptSpeed)) pt/s")
                .font(Theme.TypeFace.readout)
                .foregroundStyle(Theme.Palette.neutral)
                .monospacedDigit()
                .accessibilityLabel("Scroll speed \(Int(model.scriptSpeed)) points per second")
            Button(action: onEditScript) {
                ChipLabel(title: "Edit")
            }
            .disabled(model.recordingPhase != .idle)
        }
        .padding(.horizontal, Theme.Space.md)
    }

    // MARK: - Dance

    private var danceRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(model.routines) { routine in
                    routineChip(routine)
                }
                importControl
            }
            .padding(.horizontal, Theme.Space.md)
        }
        .disabled(model.recordingPhase != .idle)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { await model.importPickedVideo(item) }
        }
    }

    private func routineChip(_ routine: DanceRoutine) -> some View {
        let isSelected = model.selectedRoutineID == routine.id
        return Button {
            model.select(routine: routine)
        } label: {
            ChipLabel(title: routine.isMirrored ? "\(routine.name) (flipped)" : routine.name, isSelected: isSelected)
        }
        .contextMenu {
            Button("Flip left/right") { model.toggleMirror(routine) }
            Button("Delete", role: .destructive) { model.deleteRoutine(routine) }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var importControl: some View {
        if let progress = model.importProgress {
            Text("Importing \(Int((progress * 100).rounded()))%")
                .font(Theme.TypeFace.readout)
                .foregroundStyle(Theme.Palette.accent)
                .monospacedDigit()
        } else {
            PhotosPicker(selection: $pickerItem, matching: .videos) {
                ChipLabel(title: "+ Import video")
            }
        }
    }
}
