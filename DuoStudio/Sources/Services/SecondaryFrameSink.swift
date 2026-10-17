import AVFoundation
import CoreImage

/// Receives the interviewer camera's frames (Interview guide, dual-camera mode) and keeps only the
/// latest as an upright `CIImage` for `FrameProcessor` to composite under the guest frame. Holding
/// one pixel buffer (inside the `CIImage`) is all it retains.
///
/// `@unchecked Sendable`: `image` is only read or written while holding `lock`. Written from
/// `videoQueue` (the capture delegate) or the Simulator's `timerQueue`; read from whichever queue
/// runs `FrameProcessor.process`.
final class SecondaryFrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var image: CIImage?

    /// The most recent interviewer frame, `nil` until one arrives (or after `clear()`).
    var latest: CIImage? { lock.withLock { image } }

    func set(_ newImage: CIImage?) {
        lock.withLock { image = newImage }
    }

    func clear() { set(nil) }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        // The connection is configured upright and un-mirrored by `CameraService.configureConnections()`.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        set(CIImage(cvPixelBuffer: pixelBuffer))
    }
}
