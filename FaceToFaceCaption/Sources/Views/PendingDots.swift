import SwiftUI

/// Three-dot "translating" loader. Pulses via `PhaseAnimator`; static under Reduce Motion.
struct PendingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in dot(opacity: 0.6) }
                }
            } else {
                PhaseAnimator([0, 1, 2]) { phase in
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            dot(opacity: index == phase ? 1 : 0.3)
                        }
                    }
                } animation: { _ in
                    Theme.Motion.easeOut(Theme.Motion.short)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Translating")
    }

    private func dot(opacity: Double) -> some View {
        Circle()
            .fill(Theme.Palette.accent)
            .frame(width: 6, height: 6)
            .opacity(opacity)
    }
}
