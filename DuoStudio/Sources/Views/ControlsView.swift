import SwiftUI
import PoseCore

/// Sheet: filter chips, the three parameter sliders, the hand-gesture legend and the outer-display /
/// gesture toggles. Setting a filter or slider goes through `StudioModel.setFilter` /
/// `setAdjustment`, the same path a hand gesture uses, so the outer display's HUD and the
/// gesture-selected parameter stay in sync with manual changes too.
struct ControlsView: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    section("FILTER") { filterPicker }
                    section("ADJUST") {
                        VStack(alignment: .leading, spacing: Theme.Space.md) {
                            slider(for: .exposure, range: -2...2, step: 0.3, value: \.exposureEV)
                            slider(for: .contrast, range: 0.5...1.5, step: 0.1, value: \.contrast)
                            slider(for: .warmth, range: 3000...8000, step: 250, value: \.warmthKelvin)
                        }
                    }
                    section("HAND GESTURES") { gestureLegend }
                    toggles
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.Palette.paper)
            .navigationTitle("Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(title)
                .font(Theme.TypeFace.label)
                .tracking(Theme.TypeFace.labelTracking)
                .foregroundStyle(Theme.Palette.neutral)
            content()
        }
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.sm) {
                ForEach(StudioFilter.allCases, id: \.self) { filter in
                    let isSelected = model.state.filter == filter
                    Button {
                        model.setFilter(filter)
                    } label: {
                        ChipLabel(title: filter.displayName, isSelected: isSelected)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func slider(
        for parameter: StudioParameter, range: ClosedRange<Double>, step: Double,
        value: WritableKeyPath<Adjustments, Double>
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
            Slider(value: Binding(get: { model.state.adjustments[keyPath: value] }, set: { model.setAdjustment(parameter, to: $0) }), in: range, step: step)
                .tint(Theme.Palette.accent)
                .accessibilityLabel(parameter.rawValue.capitalized)
                .accessibilityValue(model.state.adjustments.formatted(parameter))
        }
    }

    // MARK: - Gesture legend

    // UNVERIFIED (2026-10-18, written on Windows): same SF Symbols stand-ins as `SubjectView.legend`
    // (no confirmed literal "fist" / "OK sign" glyph); the words carry the meaning.
    private var gestureLegend: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Theme.Space.sm), GridItem(.flexible(), spacing: Theme.Space.sm)],
            spacing: Theme.Space.sm
        ) {
            legendCard(symbol: "hand.raised", gesture: "Swipe palm", action: "Change filter")
            legendCard(symbol: "hand.pinch", gesture: "OK sign", action: "Zoom their view")
            legendCard(symbol: "hand.raised.fill", gesture: "Hold fist", action: "Next setting")
            legendCard(symbol: "hand.point.up.left.fill", gesture: "Point up/down", action: "Adjust it")
        }
    }

    private func legendCard(symbol: String, gesture: String, action: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Palette.accent)
            Text(gesture)
                .font(Theme.TypeFace.control)
                .foregroundStyle(Theme.Palette.ink)
            Text(action)
                .font(Theme.TypeFace.control)
                .foregroundStyle(Theme.Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.md)
        .background(Theme.Palette.paper2, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Toggles

    private var toggles: some View {
        VStack(spacing: Theme.Space.sm) {
            Toggle("Show outer display", isOn: Binding(get: { model.isOuterEnabled }, set: { model.isOuterEnabled = $0 }))
                .disabled(!model.isOuterAvailable || model.captureMode == .selfPortrait)
            Toggle("Hand gestures", isOn: Binding(get: { model.gesturesEnabled }, set: { model.gesturesEnabled = $0 }))
        }
        .font(Theme.TypeFace.body)
        .foregroundStyle(Theme.Palette.ink)
        .tint(Theme.Palette.accent)
    }
}
