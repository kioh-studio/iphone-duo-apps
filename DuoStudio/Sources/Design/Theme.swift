// Hallmark · app-scope: native iOS · genre: atmospheric · theme: custom "monitor" — tokens below are the only source of colour/type/spacing/motion. See ../../design.md.

import SwiftUI
import PoseCore

extension Color {
    init(oklch l: Double, _ c: Double, _ h: Double) {
        let rgb = OKLCH.linearSRGB(l: l, c: c, h: h)
        self.init(.sRGBLinear, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

enum Theme {
    enum Palette {
        // Graphite, neutral cool hue (260); one chartreuse signal (accent, hue 125) kept to ≤5% of
        // the UI — everything else is desaturated so the signal reads immediately.
        static let paper = Color(oklch: 0.13, 0.004, 260)
        static let paper2 = Color(oklch: 0.18, 0.005, 260)
        static let paper3 = Color(oklch: 0.23, 0.006, 260)
        static let rule = Color(oklch: 0.30, 0.006, 260)
        static let neutral = Color(oklch: 0.58, 0.006, 260)
        static let muted = Color(oklch: 0.74, 0.005, 260)
        static let ink = Color(oklch: 0.96, 0.003, 260)
        /// Live skeleton, match %, shutter ring, focus. Keep usage rare — it's the one signal color.
        static let accent = Color(oklch: 0.88, 0.19, 125)
        /// Off bones. Never the only cue — always paired with the thicker `Stroke.offBone` width.
        static let danger = Color(oklch: 0.70, 0.17, 30)
        /// Template (ghost) skeleton — dashed, drawn under the live one.
        static let ghost = ink.opacity(0.7)
        static let scrim = paper.opacity(0.55)
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let hitTarget: CGFloat = 44
        static let shutter: CGFloat = 76
    }

    enum TypeFace {
        static let body: Font = .system(.body)
        /// Uppercase + `labelTracking` for short readout tags ("MATCH", "FILTER").
        static let label: Font = .system(.caption, design: .monospaced).weight(.medium)
        static let readout: Font = .system(.subheadline, design: .monospaced)
        static let labelTracking: CGFloat = 1.2

        // Outer-display HUD: fixed sizes (not Dynamic Type) — read at 2–3 m by the subject, not
        // held close like the inner display's text.
        static let outerScore: Font = .system(size: 96, weight: .semibold, design: .monospaced)
        static let outerLabel: Font = .system(size: 34, weight: .semibold, design: .monospaced)
        static let outerToast: Font = .system(size: 44, weight: .bold)
        /// `SubjectView`'s gesture legend — bigger than `label`, since it has to read at 2–3 m.
        static let outerLegend: Font = .system(size: 22, weight: .medium, design: .monospaced)
    }

    enum Stroke {
        static let liveBone: CGFloat = 6
        static let ghostBone: CGFloat = 4
        static let ghostDash: [CGFloat] = [10, 8]
        static let offBone: CGFloat = 9
        static let jointDot: CGFloat = 10
        static let shutterRing: CGFloat = 4
    }

    enum Motion {
        static let micro: Double = 0.10
        static let short: Double = 0.22
        static let reduced: Double = 0.15
        static let shutterFlash: Double = 0.12

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
