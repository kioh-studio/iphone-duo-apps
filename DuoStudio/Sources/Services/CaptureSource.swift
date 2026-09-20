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
}
