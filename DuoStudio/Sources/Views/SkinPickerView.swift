import SwiftUI

/// "Pick a look." - the five skins as rows (swatch, title, blurb, "IN USE"). Tapping a row applies
/// it immediately, to both screens. Used in `SkinPickerSheet` and as onboarding's last page.
struct SkinPickerView: View {
    private var store: SkinStore { SkinStore.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Pick a look.")
                .font(Theme.TypeFace.title)
                .foregroundStyle(Theme.Palette.ink)
            Text("Changes both screens. Switch any time from the camera.")
                .font(Theme.TypeFace.body)
                .foregroundStyle(Theme.Palette.muted)
            VStack(spacing: Theme.Space.sm) {
                ForEach(Skin.allCases) { skin in
                    row(skin)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ skin: Skin) -> some View {
        let isCurrent = store.skin == skin
        return Button {
            store.skin = skin
        } label: {
            HStack(spacing: Theme.Space.md) {
                Circle()
                    .fill(skin.tokens.paper)
                    .overlay(Circle().strokeBorder(skin.tokens.accent, lineWidth: Theme.Stroke.swatchRing))
                    .frame(width: Theme.Layout.swatch, height: Theme.Layout.swatch)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(skin.title)
                        .font(Theme.TypeFace.body)
                        .foregroundStyle(Theme.Palette.ink)
                    Text(skin.blurb)
                        .font(Theme.TypeFace.control)
                        .foregroundStyle(Theme.Palette.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Theme.Space.sm)
                if isCurrent {
                    Text("IN USE")
                        .font(Theme.TypeFace.label)
                        .tracking(Theme.TypeFace.labelTracking)
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
            .padding(Theme.Space.md)
            .frame(minHeight: Theme.Space.hitTarget)
            .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(isCurrent ? Theme.Palette.accent : Color.clear, lineWidth: Theme.Stroke.selection)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(skin.title). \(skin.blurb)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Sheet from the camera's Skin button.
struct SkinPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                SkinPickerView()
                    .padding(Theme.Space.md)
            }
            .background(Theme.Palette.paper)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
