import SwiftUI

/// Interview mode, inner display: the current question on a card with previous / next buttons, a
/// "2/7" readout and an Edit button (opens the questions editor). Stays usable while recording, so
/// the interviewer can step through questions. A one-line notice appears when this iPhone can only
/// record the guest camera.
struct InterviewCardView: View {
    @Environment(StudioModel.self) private var model
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                stepButton(symbol: "chevron.left", label: "Previous question", enabled: model.canGoToPreviousQuestion) {
                    model.previousQuestion()
                }
                questionText
                    .frame(maxWidth: .infinity, alignment: .leading)
                stepButton(symbol: "chevron.right", label: "Next question", enabled: model.canGoToNextQuestion) {
                    model.nextQuestion()
                }
                Button("Edit", action: onEdit)
                    .font(Theme.TypeFace.control)
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(minWidth: Theme.Space.hitTarget, minHeight: Theme.Space.hitTarget)
                    .disabled(model.recordingPhase != .idle)
            }
            .padding(Theme.Space.sm)
            .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.card))

            if !model.interviewDualAvailable {
                Text("This iPhone can't record both cameras — recording the guest only.")
                    .font(Theme.TypeFace.label)
                    .foregroundStyle(Theme.Palette.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private var questionText: some View {
        if let question = model.currentQuestion {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(question)
                    .font(Theme.TypeFace.body)
                    .foregroundStyle(Theme.Palette.ink)
                Text(model.questionReadout)
                    .font(Theme.TypeFace.label)
                    .foregroundStyle(Theme.Palette.neutral)
                    .monospacedDigit()
                    .accessibilityLabel("Question \(model.questionReadout.replacingOccurrences(of: "/", with: " of "))")
            }
        } else {
            Text("Add questions to keep the interview on track")
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.muted)
        }
    }

    private func stepButton(symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: Theme.Space.hitTarget, height: Theme.Space.hitTarget)
                .foregroundStyle(enabled ? Theme.Palette.ink : Theme.Palette.neutral)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
