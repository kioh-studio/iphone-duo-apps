import SwiftUI
import PhotosUI
import PoseCore

/// Everything the user can reuse, in one place: Poses / Routines / Scripts / Questions. Presented as
/// a sheet from the camera's Library button (a sheet, not a full-screen cover, so `StudioView`'s
/// `onDisappear` - which stops the camera - never fires).
struct LibraryView: View {
    private enum LibraryTab: String, CaseIterable {
        case poses = "Poses"
        case routines = "Routines"
        case scripts = "Scripts"
        case questions = "Questions"
    }

    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var tab: LibraryTab = .poses
    @State private var pickerItem: PhotosPickerItem?
    @State private var editingTemplate: PoseTemplate?
    @State private var isScriptEditorPresented = false
    @State private var isQuestionsEditorPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Space.md) {
                tabBar
                ScrollView {
                    content
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.bottom, Theme.Space.lg)
                }
            }
            .background(Theme.Palette.paper)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
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
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { await model.importPickedVideo(item) }
        }
    }

    private var tabBar: some View {
        HStack(spacing: Theme.Space.sm) {
            ForEach(LibraryTab.allCases, id: \.self) { item in
                let isSelected = tab == item
                Button {
                    tab = item
                } label: {
                    ChipLabel(title: item.rawValue, isSelected: isSelected)
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, Theme.Space.md)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .poses: posesGrid
        case .routines: routines
        case .scripts: scriptRow
        case .questions: questionsRow
        }
    }

    // MARK: - Poses

    private var posesGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Theme.Space.sm, alignment: .top),
                count: Theme.Layout.libraryColumns
            ),
            spacing: Theme.Space.sm
        ) {
            ForEach(model.templates) { template in
                poseCard(template)
            }
            newPoseCard
        }
    }

    private func poseCard(_ template: PoseTemplate) -> some View {
        let isSelected = model.selectedTemplateID == template.id
        return Button {
            model.select(template: template)
            model.mode = .pose
            dismiss()
        } label: {
            VStack(spacing: Theme.Space.xs) {
                PoseThumbnailView(pose: template.pose)
                    .aspectRatio(Theme.Layout.thumbAspect, contentMode: .fit)
                Text(template.name)
                    .font(Theme.TypeFace.control)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
            }
            .padding(Theme.Space.sm)
            .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(isSelected ? Theme.Palette.accent : Color.clear, lineWidth: Theme.Stroke.selection)
            )
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button(template.isBuiltIn ? "Edit as new pose" : "Edit") { editingTemplate = template }
            if !template.isBuiltIn {
                Button("Delete", role: .destructive) { model.deleteCustom(template) }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var newPoseCard: some View {
        Button {
            editingTemplate = model.newTemplateDraft()
        } label: {
            VStack(spacing: Theme.Space.xs) {
                Color.clear
                    .aspectRatio(Theme.Layout.thumbAspect, contentMode: .fit)
                    .overlay(Image(systemName: "plus").font(Theme.TypeFace.title))
                Text("New pose")
                    .font(Theme.TypeFace.control)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.Palette.accent)
            .padding(Theme.Space.sm)
            .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Routines

    private var routines: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if model.routines.isEmpty {
                Text("No routines yet.")
                    .font(Theme.TypeFace.body)
                    .foregroundStyle(Theme.Palette.muted)
            }
            ForEach(model.routines) { routine in
                routineRow(routine)
            }
            importControl
            Text("Use videos you have the rights to. Moves are read on this iPhone, nothing is uploaded.")
                .font(Theme.TypeFace.control)
                .foregroundStyle(Theme.Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func routineRow(_ routine: DanceRoutine) -> some View {
        let isSelected = model.selectedRoutineID == routine.id
        return HStack(spacing: Theme.Space.sm) {
            Button {
                model.select(routine: routine)
            } label: {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(routine.name)
                        .font(Theme.TypeFace.body)
                        .foregroundStyle(Theme.Palette.ink)
                    Text(model.summary(of: routine))
                        .font(Theme.TypeFace.label)
                        .foregroundStyle(Theme.Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button("Flip L/R") { model.toggleMirror(routine) }
                .font(Theme.TypeFace.control)
                .foregroundStyle(Theme.Palette.accent)
                .frame(minHeight: Theme.Space.hitTarget)
            Button(role: .destructive) {
                model.deleteRoutine(routine)
            } label: {
                Image(systemName: "trash")
                    .frame(width: Theme.Space.hitTarget, height: Theme.Space.hitTarget)
                    .foregroundStyle(Theme.Palette.danger)
            }
            .accessibilityLabel("Delete \(routine.name)")
        }
        .buttonStyle(PressableStyle())
        .padding(Theme.Space.md)
        .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(isSelected ? Theme.Palette.accent : Color.clear, lineWidth: Theme.Stroke.selection)
        )
    }

    @ViewBuilder
    private var importControl: some View {
        if let progress = model.importProgress {
            Text("Importing \(Int((progress * 100).rounded()))%")
                .font(Theme.TypeFace.readout)
                .foregroundStyle(Theme.Palette.accent)
                .monospacedDigit()
                .frame(minHeight: Theme.Space.hitTarget)
        } else {
            PhotosPicker(selection: $pickerItem, matching: .videos) {
                ChipLabel(title: "+ Import video")
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Scripts

    private var scriptRow: some View {
        let line = model.scriptFirstLine
        return libraryRow(
            title: line.isEmpty ? "No script yet" : line,
            detail: line.isEmpty
                ? "Tap to write one."
                : "\(model.scriptWordCount) words · about \(model.scriptEstimatedSeconds) s at \(Int(model.scriptSpeed)) pt/s",
            isPlaceholder: line.isEmpty
        ) { isScriptEditorPresented = true }
    }

    // MARK: - Questions

    private var questionsRow: some View {
        let questions = model.interviewQuestions
        return libraryRow(
            title: questions.first ?? "No questions yet",
            detail: questions.isEmpty ? "Tap to add some." : "\(questions.count) \(questions.count == 1 ? "question" : "questions")",
            isPlaceholder: questions.isEmpty
        ) { isQuestionsEditorPresented = true }
    }

    private func libraryRow(
        title: String, detail: String, isPlaceholder: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(title)
                        .font(Theme.TypeFace.body)
                        .foregroundStyle(isPlaceholder ? Theme.Palette.muted : Theme.Palette.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(Theme.TypeFace.label)
                        .foregroundStyle(Theme.Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.Palette.neutral)
            }
            .padding(Theme.Space.md)
            .frame(minHeight: Theme.Space.hitTarget)
            .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(PressableStyle())
    }
}

/// A small static drawing of a pose template for the Library grid (thin strokes, unlike the live
/// `SkeletonOverlay`). The pose is in normalized, top-left-origin coordinates, so it is mapped
/// straight onto the view's rect.
struct PoseThumbnailView: View {
    let pose: Pose

    var body: some View {
        // Resolved on the main actor and captured by value (the renderer closure stays token-free).
        let color = Theme.Palette.accent
        return Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            for bone in Pose.bones {
                guard let from = pose.joints[bone.from], let to = pose.joints[bone.to] else { continue }
                var path = Path()
                path.move(to: PreviewLayout.point(from, in: rect))
                path.addLine(to: PreviewLayout.point(to, in: rect))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: Theme.Stroke.thumbBone, lineCap: .round))
            }
            for (_, joint) in pose.joints {
                let center = PreviewLayout.point(joint, in: rect)
                let dot = CGRect(
                    x: center.x - Theme.Stroke.thumbJoint / 2, y: center.y - Theme.Stroke.thumbJoint / 2,
                    width: Theme.Stroke.thumbJoint, height: Theme.Stroke.thumbJoint
                )
                context.fill(Path(ellipseIn: dot), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}
