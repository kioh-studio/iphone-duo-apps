import Foundation

/// One of the on-device Core Image "photo effect" filters offered as live preview + capture
/// filters.
public enum StudioFilter: String, CaseIterable, Codable, Sendable {
    case none, chrome, fade, instant, mono, noir, process, tonal, transfer

    public var displayName: String {
        switch self {
        case .none: return "Original"
        case .chrome: return "Chrome"
        case .fade: return "Fade"
        case .instant: return "Instant"
        case .mono: return "Mono"
        case .noir: return "Noir"
        case .process: return "Process"
        case .tonal: return "Tonal"
        case .transfer: return "Transfer"
        }
    }

    /// `nil` for `.none`; otherwise the `CIFilter` name of the corresponding `CIPhotoEffect*`.
    public var coreImageName: String? {
        switch self {
        case .none: return nil
        case .chrome: return "CIPhotoEffectChrome"
        case .fade: return "CIPhotoEffectFade"
        case .instant: return "CIPhotoEffectInstant"
        case .mono: return "CIPhotoEffectMono"
        case .noir: return "CIPhotoEffectNoir"
        case .process: return "CIPhotoEffectProcess"
        case .tonal: return "CIPhotoEffectTonal"
        case .transfer: return "CIPhotoEffectTransfer"
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// The photographer's live capture adjustments. Exposure and warmth are hardware settings pushed
/// to the camera device; contrast is CI-only (baked in at preview + capture time).
public struct Adjustments: Hashable, Sendable {
    public var exposureEV: Double = 0
    public var contrast: Double = 1
    public var warmthKelvin: Double = 5500

    public init() {}

    /// Steps `p` by `steps` increments (negative to decrease), clamped to its range.
    public mutating func step(_ p: StudioParameter, by steps: Int) {
        switch p {
        case .exposure:
            exposureEV = (exposureEV + Double(steps) * 0.3).clamped(to: -2...2)
        case .contrast:
            contrast = (contrast + Double(steps) * 0.1).clamped(to: 0.5...1.5)
        case .warmth:
            warmthKelvin = (warmthKelvin + Double(steps) * 250).clamped(to: 3000...8000)
        }
    }

    /// A short monospaced readout, e.g. "+0.3 EV", "1.10×", "5500 K".
    public func formatted(_ p: StudioParameter) -> String {
        switch p {
        case .exposure:
            let sign = exposureEV >= 0 ? "+" : ""
            return "\(sign)\(String(format: "%.1f", exposureEV)) EV"
        case .contrast:
            return String(format: "%.2f×", contrast)
        case .warmth:
            return "\(Int(warmthKelvin.rounded())) K"
        }
    }
}

/// The full live state of the studio session: what's applied to the preview/capture, and which
/// parameter hand gestures currently adjust.
public struct StudioState: Hashable, Sendable {
    public var filter: StudioFilter = .none
    public var adjustments = Adjustments()
    public var selectedParameter: StudioParameter = .exposure
    public var outerZoom: Double = 1

    public init() {}

    /// Applies a `GestureEvent`: next/previousFilter wrap around `allCases`; zoom multiplies &
    /// clamps 1...4; nextParameter cycles; adjust steps the selected parameter.
    public mutating func apply(_ event: GestureEvent) {
        switch event {
        case .nextFilter:
            filter = Self.cycled(StudioFilter.allCases, from: filter, by: 1)
        case .previousFilter:
            filter = Self.cycled(StudioFilter.allCases, from: filter, by: -1)
        case .zoom(let factor):
            outerZoom = (outerZoom * factor).clamped(to: 1...4)
        case .nextParameter:
            selectedParameter = Self.cycled(StudioParameter.allCases, from: selectedParameter, by: 1)
        case .adjust(let step):
            adjustments.step(selectedParameter, by: step)
        }
    }

    private static func cycled<T: Equatable>(_ cases: [T], from current: T, by delta: Int) -> T {
        guard let index = cases.firstIndex(of: current), !cases.isEmpty else { return current }
        let count = cases.count
        let newIndex = ((index + delta) % count + count) % count
        return cases[newIndex]
    }
}
