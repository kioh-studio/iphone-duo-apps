import AVFoundation
import CoreImage
import ImageIO
import PoseCore

enum RoutineImportError: Error {
    case tooLong
    case noVideoTrack
    case readFailed
}

/// Turns a reference dance video into a `DanceRoutine`: copies the file into `RoutineStore`, then
/// samples a body-pose skeleton from it at 10 fps with Vision. All on-device.
enum RoutineImporter {
    /// ponytail: 90 s cap keeps import time (Vision per sample) and the routines.json size bounded;
    /// raise it (and show progress per minute) if users want full-length songs.
    static let maxDuration: Double = 90
    /// Seconds between skeleton samples (10 fps). A ceiling on fast choreography — see backlog.
    static let sampleInterval: Double = 0.1

    /// Not `@MainActor`: this is a nonisolated `async` function, so it runs on the global executor,
    /// not the caller's main actor, and its blocking read/Vision loop stays off the UI thread. It
    /// does hold one cooperative-pool thread for the duration — acceptable for a rare, user-
    /// initiated import. Honours task cancellation between samples.
    ///
    /// A video without an audio track imports fine; the muxed recording just ends up silent
    /// (`MovieComposer.replacingAudio` returns the recording untouched).
    // UNVERIFIED (2026-10-18, written on Windows): `@concurrent` (Swift 6.2) assumed available in the
    // toolchain; it pins this to the global executor even if the project later enables
    // NonisolatedNonsendingByDefault.
    @concurrent
    static func importRoutine(
        from source: URL, name: String, progress: @Sendable (Double) -> Void
    ) async throws -> DanceRoutine {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw RoutineImportError.readFailed }
        guard duration <= maxDuration else { throw RoutineImportError.tooLong }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RoutineImportError.noVideoTrack
        }
        let transform = try await track.load(.preferredTransform)
        let imageOrientation = orientation(for: transform)

        let fileExtension = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let mediaFileName = "\(UUID().uuidString).\(fileExtension)"
        let destination = RoutineStore.directory.appendingPathComponent(mediaFileName)
        try FileManager.default.copyItem(at: source, to: destination)

        do {
            let frames = try sampleFrames(asset: asset, track: track, orientation: imageOrientation, duration: duration, progress: progress)
            return DanceRoutine(name: name, duration: duration, frames: frames, mediaFileName: mediaFileName)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func sampleFrames(
        asset: AVURLAsset, track: AVAssetTrack, orientation: CGImagePropertyOrientation,
        duration: Double, progress: @Sendable (Double) -> Void
    ) throws -> [TimedPose] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw RoutineImportError.readFailed }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? RoutineImportError.readFailed }

        var frames: [TimedPose] = []
        var firstTimestamp: Double?
        var nextSampleTime = 0.0

        while true {
            try Task.checkCancellation()
            // The pool keeps a long Vision loop from piling up autoreleased objects.
            let finished: Bool = autoreleasepool {
                guard let sample = output.copyNextSampleBuffer() else { return true }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return false }

                let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard timestamp.isFinite else { return false }
                let first = firstTimestamp ?? timestamp
                firstTimestamp = first
                let time = timestamp - first
                // Skip frames until the next 10 fps sample is due (small epsilon so a frame
                // landing a hair early on a 30 fps clip still counts).
                guard time + 0.001 >= nextSampleTime else { return false }
                nextSampleTime = max(nextSampleTime + sampleInterval, time + 0.001)

                // UNVERIFIED (2026-10-18, written on Windows): mapping `preferredTransform` to an
                // EXIF orientation and applying it with `CIImage.oriented(_:)`, then re-origining to
                // (0,0) — expected to give an upright image Vision reads correctly, but orientation
                // handling for imported (esp. mirrored/rotated) videos hasn't been run.
                var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
                image = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))

                frames.append(TimedPose(time: time, pose: VisionPose.detectBody(in: image)))
                progress(min(1, time / duration))
                return false
            }
            if finished { break }
        }

        if reader.status == .failed { throw reader.error ?? RoutineImportError.readFailed }
        progress(1)
        return frames
    }

    /// The EXIF orientation that undoes a video track's `preferredTransform` rotation. Mirrored
    /// transforms (rare) fall through to `.up`.
    private static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): return .right    // portrait, as shot on an iPhone held upright
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
