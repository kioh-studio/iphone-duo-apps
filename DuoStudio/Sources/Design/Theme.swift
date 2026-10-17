// Hallmark · app-scope: native iOS · genre: atmospheric · theme: custom "monitor" with 5 runtime skins — tokens below are the only source of colour/type/spacing/motion. See ../../design.md.

import SwiftUI
import PoseCore

extension Color {
    init(oklch l: Double, _ c: Double, _ h: Double) {
        let rgb = OKLCH.linearSRGB(l: l, c: c, h: h)
        self.init(.sRGBLinear, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

// MARK: - Skins

/// The five runtime looks. `Theme.Palette` / `TypeFace` / `Radius` resolve against the active skin
/// (`SkinStore.shared.skin`), so every call site keeps using the same token names. Hex targets and
/// the OKLCH values used are listed in `design.md`.
enum Skin: String, CaseIterable, Codable, Sendable, Identifiable {
    case studio, mono, vintage, modern, pop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio: return "Studio"
        case .mono: return "Mono"
        case .vintage: return "Vintage"
        case .modern: return "Modern"
        case .pop: return "Pop"
        }
    }

    var blurb: String {
        switch self {
        case .studio: return "Graphite field monitor, one signal colour"
        case .mono: return "Pure black and white, editor-style"
        case .vintage: return "Warm paper, film-camera serif"
        case .modern: return "Light, airy, one electric blue"
        case .pop: return "Night purple and hot pink, made for dance"
        }
    }

    /// The inner display follows the skin; the outer display (`SubjectView`) is always dark.
    var colorScheme: ColorScheme {
        switch self {
        case .vintage, .modern: return .light
        case .studio, .mono, .pop: return .dark
        }
    }

    /// System font designs only - no bundled fonts.
    var bodyDesign: Font.Design {
        switch self {
        case .studio, .mono: return .default
        case .vintage: return .serif
        case .modern, .pop: return .rounded
        }
    }

    var readoutDesign: Font.Design {
        switch self {
        case .studio, .mono, .vintage: return .monospaced
        case .modern, .pop: return .rounded
        }
    }

    /// Mono and Pop run one weight step heavier than the others.
    func weight(_ base: Font.Weight) -> Font.Weight {
        guard self == .mono || self == .pop else { return base }
        switch base {
        case .regular: return .medium
        case .medium: return .semibold
        case .semibold: return .bold
        case .bold: return .heavy
        default: return base
        }
    }

    var cardRadius: CGFloat {
        switch self {
        case .studio: return 14
        case .mono: return 12
        case .vintage: return 6
        case .modern: return 20
        case .pop: return 24
        }
    }

    /// Pop's controls are pills: 999 is clamped by `RoundedRectangle` to half the shorter side.
    var controlRadius: CGFloat {
        switch self {
        case .studio: return 10
        case .mono: return 8
        case .vintage: return 4
        case .modern: return 14
        case .pop: return 999
        }
    }

    var tokens: SkinTokens {
        switch self {
        case .studio: return .studio
        case .mono: return .mono
        case .vintage: return .vintage
        case .modern: return .modern
        case .pop: return .pop
        }
    }
}

/// One skin's colours. Plain values (not `@MainActor`) so the skin picker can draw swatches of
/// skins that are not active.
struct SkinTokens: Sendable {
    let paper: Color
    let paper2: Color
    let paper3: Color
    let rule: Color
    let neutral: Color
    let muted: Color
    let ink: Color
    let accent: Color
    /// Text / icons on `accent` fills.
    let onAccent: Color
    let danger: Color
    /// Dark base of `scrim` / `scriptScrim` - stays dark in every skin so camera overlays read.
    let overlayBase: Color
    /// Text and icons drawn over live video or on the outer display - near-white in every skin.
    let overlayInk: Color
    /// Accent for the live skeleton, match %, countdown over video (brighter than `accent` on the
    /// light skins).
    let overlayAccent: Color
    /// Off-bone colour over video (`danger` is too dark on Vintage).
    let overlayDanger: Color

    // Studio = the original graphite + chartreuse palette (hue 260 neutral, accent hue 125).
    static let studio = SkinTokens(
        paper: Color(oklch: 0.13, 0.004, 260),
        paper2: Color(oklch: 0.18, 0.005, 260),
        paper3: Color(oklch: 0.23, 0.006, 260),
        rule: Color(oklch: 0.30, 0.006, 260),
        neutral: Color(oklch: 0.58, 0.006, 260),
        muted: Color(oklch: 0.74, 0.005, 260),
        ink: Color(oklch: 0.96, 0.003, 260),
        accent: Color(oklch: 0.88, 0.19, 125),
        onAccent: Color(oklch: 0.13, 0.004, 260),
        danger: Color(oklch: 0.70, 0.17, 30),
        overlayBase: Color(oklch: 0.13, 0.004, 260),
        overlayInk: Color(oklch: 0.96, 0.003, 260),
        overlayAccent: Color(oklch: 0.88, 0.19, 125),
        overlayDanger: Color(oklch: 0.70, 0.17, 30)
    )

    static let mono = SkinTokens(
        paper: Color(oklch: 0.0, 0.0, 0),
        paper2: Color(oklch: 0.191, 0.0, 90),
        paper3: Color(oklch: 0.269, 0.0, 90),
        rule: Color(oklch: 0.360, 0.0, 90),
        neutral: Color(oklch: 0.633, 0.0, 90),
        muted: Color(oklch: 0.715, 0.0, 90),
        ink: Color(oklch: 1.0, 0.0, 90),
        accent: Color(oklch: 1.0, 0.0, 90),
        onAccent: Color(oklch: 0.0, 0.0, 0),
        danger: Color(oklch: 0.647, 0.238, 18),
        overlayBase: Color(oklch: 0.0, 0.0, 0),
        overlayInk: Color(oklch: 1.0, 0.0, 90),
        overlayAccent: Color(oklch: 1.0, 0.0, 90),
        overlayDanger: Color(oklch: 0.647, 0.238, 18)
    )

    static let vintage = SkinTokens(
        paper: Color(oklch: 0.924, 0.031, 86),
        paper2: Color(oklch: 0.885, 0.041, 87),
        paper3: Color(oklch: 0.834, 0.053, 86),
        rule: Color(oklch: 0.668, 0.060, 81),
        neutral: Color(oklch: 0.526, 0.042, 72),
        muted: Color(oklch: 0.436, 0.037, 70),
        ink: Color(oklch: 0.249, 0.026, 66),
        accent: Color(oklch: 0.540, 0.159, 37),
        onAccent: Color(oklch: 0.968, 0.022, 87),
        danger: Color(oklch: 0.406, 0.120, 35),
        overlayBase: Color(oklch: 0.245, 0.029, 59),
        overlayInk: Color(oklch: 0.968, 0.022, 87),
        overlayAccent: Color(oklch: 0.657, 0.159, 39),
        overlayDanger: Color(oklch: 0.729, 0.170, 35)
    )

    static let modern = SkinTokens(
        paper: Color(oklch: 0.976, 0.003, 265),
        paper2: Color(oklch: 1.0, 0.0, 90),
        paper3: Color(oklch: 0.939, 0.007, 261),
        rule: Color(oklch: 0.871, 0.014, 258),
        neutral: Color(oklch: 0.611, 0.027, 260),
        muted: Color(oklch: 0.471, 0.026, 257),
        ink: Color(oklch: 0.177, 0.011, 261),
        accent: Color(oklch: 0.551, 0.247, 266),
        onAccent: Color(oklch: 1.0, 0.0, 90),
        danger: Color(oklch: 0.626, 0.193, 23),
        overlayBase: Color(oklch: 0.195, 0.013, 264),
        overlayInk: Color(oklch: 0.988, 0.002, 248),
        overlayAccent: Color(oklch: 0.642, 0.190, 268),
        overlayDanger: Color(oklch: 0.701, 0.190, 21)
    )

    static let pop = SkinTokens(
        paper: Color(oklch: 0.210, 0.066, 294),
        paper2: Color(oklch: 0.270, 0.090, 294),
        paper3: Color(oklch: 0.332, 0.106, 294),
        rule: Color(oklch: 0.454, 0.123, 293),
        neutral: Color(oklch: 0.676, 0.083, 298),
        muted: Color(oklch: 0.826, 0.064, 301),
        ink: Color(oklch: 0.982, 0.012, 343),
        accent: Color(oklch: 0.695, 0.223, 355),
        onAccent: Color(oklch: 0.210, 0.066, 294),
        danger: Color(oklch: 0.880, 0.135, 86),
        overlayBase: Color(oklch: 0.210, 0.066, 294),
        overlayInk: Color(oklch: 0.982, 0.012, 343),
        overlayAccent: Color(oklch: 0.695, 0.223, 355),
        overlayDanger: Color(oklch: 0.880, 0.135, 86)
    )
}

/// The active skin, persisted in UserDefaults ("skin"). `@Observable`, so any view that reads a
/// `Theme` token inside `body` re-renders when the skin changes. Services must not depend on it
/// (they repeat the Studio constants they need - see `FrameProcessor.paper`).
// UNVERIFIED (2026-10-18, written on Windows): that reading `SkinStore.shared.skin` through the
// `@MainActor static var` token getters inside a view's `body` registers Observation tracking (so the
// view re-renders on a skin change) - including for `.sheet` content and the `CameraCaptureAccessory`
// scene's `SubjectView`. If a view fails to refresh, give the root views `.id(skin)`.
@MainActor
@Observable
final class SkinStore {
    static let shared = SkinStore()
    private static let key = "skin"

    var skin: Skin {
        didSet { UserDefaults.standard.set(skin.rawValue, forKey: Self.key) }
    }

    private init() {
        skin = UserDefaults.standard.string(forKey: Self.key).flatMap(Skin.init(rawValue:)) ?? .studio
    }
}

// MARK: - Tokens

enum Theme {
    /// Colours resolve against the active skin. Everything drawn over live video or on the outer
    /// display uses the `overlay*` tokens (and `scrim`), never `ink` / `muted` / `accent` - those are
    /// dark on the light skins.
    enum Palette {
        @MainActor static var paper: Color { SkinStore.shared.skin.tokens.paper }
        @MainActor static var paper2: Color { SkinStore.shared.skin.tokens.paper2 }
        @MainActor static var paper3: Color { SkinStore.shared.skin.tokens.paper3 }
        @MainActor static var rule: Color { SkinStore.shared.skin.tokens.rule }
        @MainActor static var neutral: Color { SkinStore.shared.skin.tokens.neutral }
        @MainActor static var muted: Color { SkinStore.shared.skin.tokens.muted }
        @MainActor static var ink: Color { SkinStore.shared.skin.tokens.ink }
        /// The skin's one signal colour: selected states, primary buttons, rings. Keep usage rare.
        @MainActor static var accent: Color { SkinStore.shared.skin.tokens.accent }
        /// Text / icons on `accent` fills.
        @MainActor static var onAccent: Color { SkinStore.shared.skin.tokens.onAccent }
        /// Off bones on inner surfaces. Never the only cue - always paired with the thicker `Stroke.offBone` width.
        @MainActor static var danger: Color { SkinStore.shared.skin.tokens.danger }

        /// Near-white text / icons over live video and on the outer display, in every skin.
        @MainActor static var overlayInk: Color { SkinStore.shared.skin.tokens.overlayInk }
        @MainActor static var overlayMuted: Color { overlayInk.opacity(0.7) }
        /// Live skeleton, match %, countdown over video.
        @MainActor static var overlayAccent: Color { SkinStore.shared.skin.tokens.overlayAccent }
        /// Off bones over video.
        @MainActor static var overlayDanger: Color { SkinStore.shared.skin.tokens.overlayDanger }
        /// Dark base behind the outer display and the scrims.
        @MainActor static var overlayBase: Color { SkinStore.shared.skin.tokens.overlayBase }
        /// Template (ghost) skeleton - dashed, drawn under the live one.
        @MainActor static var ghost: Color { overlayInk.opacity(0.7) }
        @MainActor static var scrim: Color { overlayBase.opacity(0.55) }
        /// Teleprompter panel behind the script text - denser than `scrim`, since text has to stay
        /// readable at 2-3 m over a bright live preview.
        @MainActor static var scriptScrim: Color { overlayBase.opacity(0.8) }
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

    /// Per-skin corner radii. `control` is 999 for Pop (pill).
    enum Radius {
        @MainActor static var card: CGFloat { SkinStore.shared.skin.cardRadius }
        @MainActor static var control: CGFloat { SkinStore.shared.skin.controlRadius }
    }

    enum Layout {
        /// Share of the outer display's height the teleprompter panel occupies.
        static let teleprompterFraction: CGFloat = 0.6
        /// Minimum height of the mode panel row under the preview.
        static let modePanelHeight: CGFloat = 84
        /// Space `SubjectView` keeps free at the top when it is the inner preview, for the top bar.
        static let topBarClearance: CGFloat = 64
        static let libraryColumns = 3
        /// Pose thumbnail width / height.
        static let thumbAspect: CGFloat = 0.75
        /// Onboarding's inside / outside illustration.
        static let illustrationHeight: CGFloat = 180
        static let swatch: CGFloat = 36
    }

    enum Opacity {
        static let disabled: Double = 0.4
    }

    enum TypeFace {
        @MainActor private static var skin: Skin { SkinStore.shared.skin }

        // UNVERIFIED (2026-10-18, written on Windows): `Font.system(_:design:)` followed by `.weight(_:)`
        // with `.serif` / `.rounded` / `.monospaced` - assumed to keep the Dynamic Type text style.
        /// Proportional text in the skin's body design.
        @MainActor private static func text(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
            Font.system(style, design: skin.bodyDesign).weight(skin.weight(weight))
        }

        /// Readout text in the skin's readout design (monospaced on Studio / Mono / Vintage).
        @MainActor private static func readoutText(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
            Font.system(style, design: skin.readoutDesign).weight(skin.weight(weight))
        }

        @MainActor static var body: Font { text(.body) }
        @MainActor static var title: Font { text(.title2, .semibold) }
        @MainActor static var display: Font { text(.largeTitle, .bold) }
        /// Buttons and one-line descriptions on the inner display (mode dial, summaries, bottom row).
        @MainActor static var control: Font { text(.footnote, .medium) }
        /// Uppercase + `labelTracking` for short readout tags ("MATCH", "FILTER").
        @MainActor static var label: Font { readoutText(.caption, .medium) }
        @MainActor static var readout: Font { readoutText(.subheadline) }
        static let labelTracking: CGFloat = 1.2

        // Outer-display HUD: fixed sizes (not Dynamic Type) - read at 2-3 m by the subject, not
        // held close like the inner display's text.
        @MainActor static var outerScore: Font {
            Font.system(size: 96, weight: skin.weight(.semibold), design: skin.readoutDesign)
        }
        @MainActor static var outerLabel: Font {
            Font.system(size: 34, weight: skin.weight(.semibold), design: skin.readoutDesign)
        }
        @MainActor static var outerToast: Font {
            Font.system(size: 44, weight: skin.weight(.bold), design: skin.bodyDesign)
        }
        /// `SubjectView`'s gesture legend - bigger than `label`, since it has to read at 2-3 m.
        @MainActor static var outerLegend: Font {
            Font.system(size: 22, weight: skin.weight(.medium), design: skin.readoutDesign)
        }
        /// Teleprompter text (video modes, Script). Line spacing is `Space.sm`.
        @MainActor static var outerScript: Font {
            Font.system(size: 40, weight: skin.weight(.semibold), design: skin.bodyDesign)
        }
        /// Pre-recording 3-2-1.
        @MainActor static var outerCountdown: Font {
            Font.system(size: 180, weight: skin.weight(.bold), design: skin.readoutDesign)
        }
    }

    enum Stroke {
        static let liveBone: CGFloat = 6
        static let ghostBone: CGFloat = 4
        static let ghostDash: [CGFloat] = [10, 8]
        static let offBone: CGFloat = 9
        static let jointDot: CGFloat = 10
        static let shutterRing: CGFloat = 4
        /// TikTok-safe framing box (Frame mode).
        static let frameGuide: CGFloat = 3
        /// Corner radius of the record button's inner square while recording.
        static let recordCorner: CGFloat = 8
        /// Library pose thumbnails.
        static let thumbBone: CGFloat = 2
        static let thumbJoint: CGFloat = 4
        /// Accent ring on a skin swatch.
        static let swatchRing: CGFloat = 3
        /// Outline on a selected card.
        static let selection: CGFloat = 2
    }

    enum Motion {
        static let micro: Double = 0.10
        static let short: Double = 0.22
        static let reduced: Double = 0.15
        static let shutterFlash: Double = 0.12
        /// Seconds per countdown number before recording starts.
        static let countdownStep: Double = 1.0
        /// Seconds the routine score stays on the outer display after a dance recording.
        static let scoreHold: Double = 4.0

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
