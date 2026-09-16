import Foundation

/// OKLCH → linear sRGB conversion (Björn Ottosson's OKLab matrices).
public enum OKLCH {
    /// Converts an OKLCH color (`l` 0...1, `c` chroma, `h` hue in degrees) to linear sRGB.
    /// Components are clamped to 0...1.
    public static func linearSRGB(l: Double, c: Double, h: Double) -> (red: Double, green: Double, blue: Double) {
        let hr = h * .pi / 180
        let a = c * cos(hr)
        let b = c * sin(hr)

        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b

        let L = l_ * l_ * l_
        let M = m_ * m_ * m_
        let S = s_ * s_ * s_

        let red = 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let green = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let blue = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S

        return (
            red: min(max(red, 0), 1),
            green: min(max(green, 0), 1),
            blue: min(max(blue, 0), 1)
        )
    }
}
