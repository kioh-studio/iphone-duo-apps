import SwiftUI

/// Live mic-level indicator: 5 capsules whose heights follow a fixed envelope, scaled by `level`.
struct LevelMeter: View {
    let level: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let envelope: [Double] = [0.5, 0.8, 1, 0.8, 0.5]
    private static let maxHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(Self.envelope.enumerated()), id: \.offset) { _, multiplier in
                Capsule()
                    .fill(Theme.Palette.accent)
                    .frame(width: 3, height: max(3, Self.maxHeight * multiplier * level))
            }
        }
        .frame(height: Self.maxHeight, alignment: .center)
        .animation(reduceMotion ? nil : Theme.Motion.easeOut(Theme.Motion.micro), value: level)
        .accessibilityHidden(true)
    }
}
