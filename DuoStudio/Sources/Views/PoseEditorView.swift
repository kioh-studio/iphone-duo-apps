import SwiftUI
import Foundation
import PoseCore

/// Sheet for authoring or editing a pose template: the current preview, frozen and dimmed, with
/// every present joint draggable via a 44pt handle. Built-in templates are always edited as a new
/// copy (`saveCustom` on `StudioModel` already forces `isBuiltIn = false`).
struct PoseEditorView: View {
    let original: PoseTemplate

    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var pose: Pose

    init(template: PoseTemplate) {
        original = template
        _name = State(initialValue: template.name)
        _pose = State(initialValue: template.pose)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let imageSize = model.previewImage.map { CGSize(width: $0.width, height: $0.height) } ?? proxy.size
                let rect = PreviewLayout.aspectFillRect(imageSize: imageSize, in: CGRect(origin: .zero, size: proxy.size))

                ZStack {
                    Theme.Palette.paper.ignoresSafeArea()
                    if let image = model.previewImage {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .opacity(0.4)
                    }
                    SkeletonOverlay(livePose: pose, template: nil, match: nil, imageSize: imageSize)

                    ForEach(Joint.allCases, id: \.self) { joint in
                        if let point = pose.joints[joint] {
                            handle(for: joint, at: PreviewLayout.point(point, in: rect), rect: rect)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .coordinateSpace(.named("editor"))
            }
            .navigationTitle("Edit Pose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                controls
            }
        }
    }

    /// The gesture's `location`/`translation` are reported in the shared "editor" named
    /// coordinate space (set on the `ZStack` above), not the handle's own local frame — otherwise
    /// a handle that has already moved away from its start point would report drag locations
    /// relative to its *current* position instead of the shared preview frame.
    private func handle(for joint: Joint, at center: CGPoint, rect: CGRect) -> some View {
        Circle()
            .fill(Theme.Palette.accent)
            .frame(width: Theme.Space.hitTarget, height: Theme.Space.hitTarget)
            .contentShape(Circle())
            .position(center)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("editor"))
                    .onChanged { value in
                        pose.joints[joint] = PreviewLayout.normalized(value.location, in: rect)
                    }
            )
            .accessibilityLabel(Text(joint.rawValue))
            .accessibilityAddTraits(.isButton)
    }

    private var controls: some View {
        VStack(spacing: Theme.Space.md) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(Theme.TypeFace.body)
            Button("Use live pose") {
                if let live = model.livePose { pose = live }
            }
            .disabled(model.livePose == nil)
            .buttonStyle(PressableStyle())
            .font(Theme.TypeFace.body)
        }
        .padding(Theme.Space.md)
        .background(Theme.Palette.paper2)
    }

    private func save() {
        let template = PoseTemplate(
            id: original.isBuiltIn ? UUID() : original.id,
            name: name.trimmingCharacters(in: .whitespaces),
            pose: pose,
            isBuiltIn: false
        )
        model.saveCustom(template)
        dismiss()
    }
}
