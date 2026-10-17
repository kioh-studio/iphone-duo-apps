import SwiftUI

/// The mode dial: two labelled groups (PHOTO, VIDEO), each a row of buttons on a `paper2` track,
/// with the selected mode's one-line summary underneath. Disabled while a recording is running
/// (the model guards too).
struct ModeDialView: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                group(.photo, title: "PHOTO")
                group(.video, title: "VIDEO")
            }
            Text(model.mode.summary)
                .font(Theme.TypeFace.control)
                .foregroundStyle(Theme.Palette.muted)
                .lineLimit(3, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Space.md)
        .disabled(model.recordingPhase != .idle)
    }

    private func group(_ group: StudioMode.Group, title: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title)
                .font(Theme.TypeFace.label)
                .tracking(Theme.TypeFace.labelTracking)
                .foregroundStyle(Theme.Palette.neutral)
            HStack(spacing: Theme.Space.xs) {
                ForEach(StudioMode.modes(in: group), id: \.self) { mode in
                    button(mode)
                }
            }
            .padding(Theme.Space.xs)
            .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title.capitalized)
    }

    private func button(_ mode: StudioMode) -> some View {
        let isSelected = model.mode == mode
        return Button {
            model.mode = mode
        } label: {
            Text(mode.title)
                .font(Theme.TypeFace.control)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, Theme.Space.sm)
                .frame(maxWidth: .infinity, minHeight: Theme.Space.hitTarget)
                .foregroundStyle(isSelected ? Theme.Palette.onAccent : Theme.Palette.ink)
                .background(
                    isSelected ? Theme.Palette.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control)
                )
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
