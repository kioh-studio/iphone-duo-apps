import AVFoundation

enum MovieComposerError: Error {
    case noVideoTrack
    case compositionFailed
}

/// Muxes a reference video's soundtrack into a finished recording. Dance mode records no microphone
/// audio at all (the music plays from the speaker; recording it would add room echo), so the saved
/// clip gets the reference video's own audio instead.
enum MovieComposer {
    /// Returns a new temp `.mp4` with `video`'s picture and the first audio track of `media`
    /// (trimmed to the shorter of the two). If `media` has no audio track, returns `video`
    /// unchanged. The caller owns and deletes both files.
    static func replacingAudio(of video: URL, withAudioFrom media: URL) async throws -> URL {
        let mediaAsset = AVURLAsset(url: media)
        guard let mediaAudio = try await mediaAsset.loadTracks(withMediaType: .audio).first else { return video }

        let videoAsset = AVURLAsset(url: video)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw MovieComposerError.noVideoTrack
        }
        let videoDuration = try await videoAsset.load(.duration)
        let mediaDuration = try await mediaAsset.load(.duration)

        let composition = AVMutableComposition()
        guard
            let videoOut = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioOut = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MovieComposerError.compositionFailed }

        try videoOut.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        try audioOut.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTimeMinimum(videoDuration, mediaDuration)), of: mediaAudio, at: .zero
        )

        // UNVERIFIED (2026-10-18, written on Windows): `AVAssetExportSession(asset:presetName:)`
        // (failable init) and the async `export(to:as:)` introduced alongside the deprecation of
        // `outputURL`/`outputFileType`/`exportAsynchronously` — signature and Passthrough + .mp4
        // pairing not checked against the current SDK.
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw MovieComposerError.compositionFailed
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try await session.export(to: output, as: .mp4)
        return output
    }
}
