import CoreImage
import Photos
import PoseCore

enum PhotoWriterError: Error {
    case renderFailed
    case unauthorized
}

/// Bakes the currently-selected filter and contrast into the captured photo, then saves it to the
/// user's photo library. Exposure and warmth are already baked in by the hardware — `CameraService
/// .apply(_:)` sets them on the device before capture — so only the filter and contrast (which have
/// no device equivalent) need reapplying here.
enum PhotoWriter {
    /// `CIContext` is `Sendable` (documented thread-safe for concurrent use), so a single shared
    /// instance needs no actor/queue confinement of its own.
    private static let context = CIContext()

    static func write(_ data: Data, filter: StudioFilter, contrast: Double) async throws {
        // No filter and no contrast change: save the original capture untouched, so it keeps its
        // EXIF and bit depth rather than being flattened to RGBA8 HEIF by a no-op CI round-trip.
        let hasEdits = filter != .none || abs(contrast - 1) >= 0.001
        let outputData: Data
        if hasEdits {
            guard var ciImage = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
                throw PhotoWriterError.renderFailed
            }
            if let filterName = filter.coreImageName {
                ciImage = ciImage.applyingFilter(filterName)
            }
            ciImage = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: contrast])

            // UNVERIFIED (2026-09-20, written on Windows): `CIContext.heifRepresentation(of:format:
            // colorSpace:options:)` is assumed to return `Data?` (like `jpegRepresentation`), not a
            // throwing call — unconfirmed against the current SDK.
            guard let colorSpace = ciImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let rendered = context.heifRepresentation(of: ciImage, format: .RGBA8, colorSpace: colorSpace)
            else {
                throw PhotoWriterError.renderFailed
            }
            outputData = rendered
        } else {
            outputData = data
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoWriterError.unauthorized
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: outputData, options: nil)
        }
    }
}
