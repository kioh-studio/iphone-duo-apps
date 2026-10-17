import SwiftUI

/// Sheet: the teleprompter script (`TextEditor`) and its scroll speed. Binds straight to
/// `StudioModel.scriptText` / `scriptSpeed`, which persist themselves.
struct ScriptEditorView: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                TextEditor(text: Binding(get: { model.scriptText }, set: { model.scriptText = $0 }))
                    .font(Theme.TypeFace.body)
                    .foregroundStyle(Theme.Palette.ink)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Space.sm)
                    .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .accessibilityLabel("Script")

                speedControl
            }
            .padding(Theme.Space.md)
            .background(Theme.Palette.paper)
            .navigationTitle("Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var speedControl: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text("SCROLL SPEED")
                    .font(Theme.TypeFace.label)
                    .tracking(Theme.TypeFace.labelTracking)
                    .foregroundStyle(Theme.Palette.neutral)
                Spacer()
                Text("\(Int(model.scriptSpeed)) pt/s")
                    .font(Theme.TypeFace.readout)
                    .foregroundStyle(Theme.Palette.ink)
            }
            Slider(
                value: Binding(get: { model.scriptSpeed }, set: { model.scriptSpeed = $0 }),
                in: StudioModel.scriptSpeedRange, step: 5
            )
            .tint(Theme.Palette.accent)
            .accessibilityLabel("Scroll speed")
            .accessibilityValue("\(Int(model.scriptSpeed)) points per second")
        }
    }
}
