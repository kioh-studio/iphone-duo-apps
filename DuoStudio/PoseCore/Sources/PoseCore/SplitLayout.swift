import Foundation

/// Geometry of the Interview guide's recorded frame: a 1080x1920 portrait canvas split into two
/// 1080x960 halves - guest on top, interviewer on the bottom.
///
/// Everything here is in Core Image's coordinate space (origin BOTTOM-left, y up), because the only
/// consumer is the Core Image compositor in `FrameProcessor`. So the top half has the larger y.
public enum SplitLayout {
    public struct Rect: Hashable, Sendable {
        public var x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }
    }

    /// A uniform scale then translation: a source point `(px, py)` (origin at the source's own
    /// bottom-left corner) lands at `(px * scale + tx, py * scale + ty)`.
    public struct Placement: Hashable, Sendable {
        public var scale: Double, tx: Double, ty: Double
    }

    public static let canvasWidth = 1080.0
    public static let canvasHeight = 1920.0
    /// Guest (top half, y-up so the larger y).
    public static let guest = Rect(x: 0, y: canvasHeight / 2, width: canvasWidth, height: canvasHeight / 2)
    /// Interviewer (bottom half).
    public static let interviewer = Rect(x: 0, y: 0, width: canvasWidth, height: canvasHeight / 2)

    /// Aspect-fill: the smallest uniform scale that makes a `sourceWidth` x `sourceHeight` image
    /// cover `target`, centred on it. The overflow on one axis is cropped by the caller (crop to
    /// `target`). A degenerate source (zero/negative size) yields the identity scale centred on the
    /// target.
    public static func aspectFill(sourceWidth: Double, sourceHeight: Double, into target: Rect) -> Placement {
        guard sourceWidth > 0, sourceHeight > 0 else {
            return Placement(scale: 1, tx: target.midX, ty: target.midY)
        }
        let scale = max(target.width / sourceWidth, target.height / sourceHeight)
        return Placement(
            scale: scale,
            tx: target.midX - sourceWidth * scale / 2,
            ty: target.midY - sourceHeight * scale / 2
        )
    }
}
