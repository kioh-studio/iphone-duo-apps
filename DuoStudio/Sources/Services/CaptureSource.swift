import Foundation
import PoseCore

/// Whatever feeds `StudioModel` frames and takes capture commands: the real `CameraService` on
/// device, or — in the Simulator, which has no camera — `SimulatedFrameSource`.
///
/// `setDirectionalDevices` deliberately isn't part of this protocol: it only means something for a
/// real, physical Duo (see `CameraDirectionAnchor`), so it stays `CameraService`-only and
/// `StudioModel.updateCameraDirections(forwardIDs:backwardIDs:)` calls it on that concrete type
/// directly rather than through this abstraction.
protocol CaptureSource: AnyObject, Sendable {
    func start()
    func stop()
    func apply(_ adjustments: Adjustments)
    func setMode(_ mode: CaptureMode)
    func capturePhoto() async throws -> Data
    /// Video shoot kind: `isVideo` switches the capture preset; `recordsAudio` adds the microphone;
    /// `interview` (Interview guide) asks for both cameras recorded into one split-screen clip.
    func setVideoConfiguration(isVideo: Bool, recordsAudio: Bool, interview: Bool)
    /// Registers a callback (invoked from a background queue) reporting whether the Interview
    /// guide is really recording both cameras (`true`) or fell back to the guest camera only
    /// (`false`). Fires each time the capture setup is rebuilt for the Interview guide.
    func setDualCaptureHandler(_ handler: @escaping @Sendable (Bool) -> Void)
    /// Begins writing processed frames (plus mic audio when `includeAudio`) to a temp `.mp4`.
    func startRecording(includeAudio: Bool) async throws
    /// Finishes the recording and returns the temp file's URL; the caller owns (and deletes) it.
    func stopRecording() async throws -> URL
}
