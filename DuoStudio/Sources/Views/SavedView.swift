import SwiftUI

/// Sheet after a photo or video was saved to Photos. No Share button: the saved temp file is gone
/// (see backlog). Dance shows the real routine score.
struct SavedView: View {
    let clip: SavedClip
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle")
                .font(Theme.TypeFace.display)
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityHidden(true)
            VStack(spacing: Theme.Space.sm) {
                Text("Saved to Photos")
                    .font(Theme.TypeFace.title)
                    .foregroundStyle(Theme.Palette.ink)
                Text(clip.subline)
                    .font(Theme.TypeFace.body)
                    .foregroundStyle(Theme.Palette.muted)
                    .multilineTextAlignment(.center)
            }
            if clip.mode == .dance, let score = clip.routineScore {
                Text("ROUTINE SCORE \(score)%")
                    .font(Theme.TypeFace.readout)
                    .tracking(Theme.TypeFace.labelTracking)
                    .foregroundStyle(Theme.Palette.accent)
                    .monospacedDigit()
                    .accessibilityLabel("Routine score \(score) percent")
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Text("Shoot again")
                    .font(Theme.TypeFace.body)
                    .frame(maxWidth: .infinity, minHeight: Theme.Space.hitTarget)
                    .foregroundStyle(Theme.Palette.onAccent)
                    .background(Theme.Palette.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.paper)
        .presentationDetents([.medium])
    }
}
