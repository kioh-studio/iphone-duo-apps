import SwiftUI
import PoseCore

/// Sheet (medium detent): filter picker + the three parameter sliders. Setting any of them here
/// goes through `StudioModel.setFilter`/`setAdjustment`, the same path a hand gesture uses, so the
/// outer display's HUD and the gesture-selected parameter stay in sync with manual changes too.
struct AdjustmentsView: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    filterPicker
                    slider(for: .exposure, range: -2...2, step: 0.3) { model.state.adjustments.exposureEV }
                    slider(for: .contrast, range: 0.5...1.5, step: 0.1) { model.state.adjustments.contrast }
                    slider(for: .warmth, range: 3000...8000, step: 250) { model.state.adjustments.warmthKelvin }
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.Palette.paper)
            .navigationTitle("Adjustments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(StudioFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
        }
    }

    private func filterChip(_ filter: StudioFilter) -> some View {
        let isSelected = model.state.filter == filter
        return Button {
            model.setFilter(filter)
        } label: {
            Text(filter.displayName)
                .font(Theme.TypeFace.body)
                .foregroundStyle(isSelected ? Theme.Palette.paper : Theme.Palette.ink)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.sm)
                .background(isSelected ? Theme.Palette.accent : Theme.Palette.paper3, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func slider(
        for parameter: StudioParameter, range: ClosedRange<Double>, step: Double, get: @escaping @MainActor @Sendable () -> Double
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(parameter.rawValue.uppercased())
                    .font(Theme.TypeFace.label)
                    .tracking(Theme.TypeFace.labelTracking)
                    .foregroundStyle(Theme.Palette.neutral)
                Spacer()
                Text(model.state.adjustments.formatted(parameter))
                    .font(Theme.TypeFace.readout)
                    .foregroundStyle(Theme.Palette.ink)
            }
            Slider(value: Binding(get: get, set: { model.setAdjustment(parameter, to: $0) }), in: range, step: step)
                .tint(Theme.Palette.accent)
                .accessibilityLabel(parameter.rawValue.capitalized)
                .accessibilityValue(model.state.adjustments.formatted(parameter))
        }
    }
}
