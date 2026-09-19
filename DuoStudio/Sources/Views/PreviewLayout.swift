import CoreGraphics
import PoseCore

/// Shared geometry so the preview image (drawn aspect-fill) and `SkeletonOverlay`'s normalized
/// pose points always land on the same pixels, whatever the image's aspect ratio vs. the view's.
enum PreviewLayout {
    /// The rect an aspect-filled image of `imageSize` occupies inside `bounds` — larger than
    /// `bounds` on one axis, centred, matching `.aspectRatio(contentMode: .fill)`.
    static func aspectFillRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        return CGRect(origin: origin, size: size)
    }

    /// Maps a normalized (0...1, top-left origin) point into an aspect-filled image rect.
    /// `Point2`'s components are `Double`; `CGRect`'s are `CGFloat` — the two don't implicitly
    /// convert, so the crossing happens explicitly here, once, rather than at every call site.
    static func point(_ normalized: Point2, in imageRect: CGRect) -> CGPoint {
        CGPoint(
            x: imageRect.minX + CGFloat(normalized.x) * imageRect.width,
            y: imageRect.minY + CGFloat(normalized.y) * imageRect.height
        )
    }

    /// The inverse of `point(_:in:)` — a view-space point back to normalized 0...1 coordinates,
    /// clamped. Used by `PoseEditorView`'s drag handles.
    static func normalized(_ point: CGPoint, in imageRect: CGRect) -> Point2 {
        guard imageRect.width > 0, imageRect.height > 0 else { return Point2(x: 0.5, y: 0.5) }
        let x = (point.x - imageRect.minX) / imageRect.width
        let y = (point.y - imageRect.minY) / imageRect.height
        return Point2(x: Double(min(max(x, 0), 1)), y: Double(min(max(y, 0), 1)))
    }
}
