// Hallmark · app-scope: native iOS · genre: atmospheric · theme: custom "subtitle" — tokens below are the only source of colour/type/spacing/motion. See ../../design.md.

import SwiftUI
import CaptionCore

extension Color {
    init(oklch l: Double, _ c: Double, _ h: Double) {
        let rgb = OKLCH.linearSRGB(l: l, c: c, h: h)
        self.init(.sRGBLinear, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

enum Theme {
    enum Palette {
        static let paper = Color(oklch: 0.14, 0.010, 70)
        static let paper2 = Color(oklch: 0.19, 0.012, 70)
        static let paper3 = Color(oklch: 0.24, 0.012, 70)
        static let rule = Color(oklch: 0.31, 0.010, 70)
        static let neutral = Color(oklch: 0.58, 0.010, 75)
        static let muted = Color(oklch: 0.74, 0.010, 80)
        static let ink = Color(oklch: 0.95, 0.012, 90)
        static let accent = Color(oklch: 0.84, 0.15, 88)
        static let danger = Color(oklch: 0.72, 0.16, 32)
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let foldBand: CGFloat = 28
    }

    enum TypeFace {
        static let wordmark: Font = .system(size: 34, weight: .regular, design: .serif)
        static let body: Font = .system(.body)
        static let secondary: Font = .system(.subheadline)
        static let label: Font = .system(.caption, design: .monospaced).weight(.medium)
        static let previousCaption: Font = .system(size: 24, weight: .regular)
        static let captionBase: CGFloat = 44
        static func caption(size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
        static let labelTracking: CGFloat = 1.2
    }

    enum Motion {
        static let micro: Double = 0.10
        static let short: Double = 0.22
        static let reduced: Double = 0.15

        static func easeOut(_ duration: Double) -> Animation {
            .timingCurve(0.16, 1, 0.3, 1, duration: duration)
        }

        static func crossfade(reduceMotion: Bool) -> Animation {
            reduceMotion ? .linear(duration: reduced) : easeOut(short)
        }
    }
}

/// Button press scale 0.98, disabled when Reduce Motion is on.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(Theme.Motion.easeOut(Theme.Motion.micro), value: configuration.isPressed)
    }
}
