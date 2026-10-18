import SwiftUI

/// The mode dial: two labelled groups (PHOTO, VIDEO), each a row of buttons on a `paper2` track,
/// with the selected mode's one-line summary underneath. Disabled while a recording is running
/// (the model guards too).
struct ModeDialView: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            // Side by side when every label fits untruncated; otherwise stacked, full-width groups.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    group(.photo, title: "PHOTO", stacked: false)
                    group(.video, title: "VIDEO", stacked: false)
                }
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    group(.photo, title: "PHOTO", stacked: true)
                    group(.video, title: "VIDEO", stacked: true)
                }
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

    private func group(_ group: StudioMode.Group, title: String, stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title)
                .font(Theme.TypeFace.label)
                .tracking(Theme.TypeFace.labelTracking)
                .foregroundStyle(Theme.Palette.neutral)
            HStack(spacing: Theme.Space.xs) {
                ForEach(StudioMode.modes(in: group), id: \.self) { mode in
                    button(mode, stacked: stacked)
                }
            }
            .padding(Theme.Space.xs)
            .frame(maxWidth: stacked ? .infinity : nil)
            .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title.capitalized)
    }

    private func button(_ mode: StudioMode, stacked: Bool) -> some View {
        let isSelected = model.mode == mode
        return Button {
            model.mode = mode
        } label: {
            Text(mode.title)
                .font(Theme.TypeFace.control)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Theme.Space.sm)
                .frame(maxWidth: stacked ? .infinity : nil, minHeight: Theme.Space.hitTarget)
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
