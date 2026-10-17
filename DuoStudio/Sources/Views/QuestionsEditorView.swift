import SwiftUI

/// Sheet: the interview questions, one per line. Binds straight to
/// `StudioModel.interviewQuestionsText`, which persists itself.
struct QuestionsEditorView: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: Binding(get: { model.interviewQuestionsText }, set: { model.interviewQuestionsText = $0 }))
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.ink)
                .scrollContentBackground(.hidden)
                .padding(Theme.Space.sm)
                .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .accessibilityLabel("Interview questions, one per line")
                .padding(Theme.Space.md)
                .background(Theme.Palette.paper)
                .navigationTitle("Questions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
