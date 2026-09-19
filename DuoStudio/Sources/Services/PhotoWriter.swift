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
    private static let context = CIContext()

    static func write(_ data: Data, filter: StudioFilter, contrast: Double) async throws {
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
              let heif = context.heifRepresentation(of: ciImage, format: .RGBA8, colorSpace: colorSpace)
        else {
            throw PhotoWriterError.renderFailed
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoWriterError.unauthorized
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: heif, options: nil)
        }
    }
}
