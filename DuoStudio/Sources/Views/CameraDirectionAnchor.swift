import SwiftUI
#if DUO_DIRECTION_COORDINATOR
import AVFoundation
import AVKit
#endif

/// Invisible host view for `AVCaptureDeviceDirectionCoordinator` (AVKit, main-actor isolated),
/// which needs a real, on-screen `UIView` to reason about which side of the Duo it's on. Placed in
/// `StudioView`'s background. Everything here is a no-op unless the app is built with the
/// `DUO_DIRECTION_COORDINATOR` flag (on by default, see `project.yml`) on iOS 27.1+.
struct CameraDirectionAnchor: UIViewRepresentable {
    let model: StudioModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        view.isUserInteractionEnabled = false
        #if DUO_DIRECTION_COORDINATOR
        if #available(iOS 27.1, *) {
            context.coordinator.start(view: view, model: model)
        }
        #endif
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Holds the coordinator strongly so it (and its change handler) outlives `makeUIView`'s local
    /// scope — a local `let` there would be deallocated, and the handler with it, before it could
    /// ever fire.
    final class Coordinator {
        // Untyped so this property doesn't need an `@available` annotation just to be declared.
        private var directionCoordinator: AnyObject?

        #if DUO_DIRECTION_COORDINATOR
        // `init(view: UIView, deviceTypes:changeHandler:)` — `view` is a non-optional `UIView` (the
        // hidden anchor view `makeUIView` builds above), and `AVCaptureDeviceDirectionMap`'s
        // `forwardFacingDeviceDescriptors`/`backwardFacingDeviceDescriptors` and
        // `AVCaptureDeviceDescriptor.uniqueID` are confirmed shapes.
        // https://developer.apple.com/documentation/avkit/avcapturedevicedirectioncoordinator
        @available(iOS 27.1, *)
        @MainActor
        func start(view: UIView, model: StudioModel) {
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera, .builtInDualWideCamera,
            ]
            let coordinator = AVCaptureDeviceDirectionCoordinator(view: view, deviceTypes: deviceTypes) { directions in
                let forwardIDs = directions.forwardFacingDeviceDescriptors.map(\.uniqueID)
                let backwardIDs = directions.backwardFacingDeviceDescriptors.map(\.uniqueID)
                Task { @MainActor in
                    model.updateCameraDirections(forwardIDs: forwardIDs, backwardIDs: backwardIDs)
                }
            }
            directionCoordinator = coordinator

            // Read the coordinator's current state once, synchronously, and push it through the
            // same path the change handler uses — so the right camera is picked from the first
            // frame instead of waiting for the first `changeHandler` call.
            // UNVERIFIED (2026-09-20, written on Windows): whether the subject-facing camera in
            // partner mode is actually the backward-facing descriptor here on real Duo hardware —
            // the docs confirm the API's shape, not which physical camera each side resolves to.
            let initial = coordinator.deviceDirections
            model.updateCameraDirections(
                forwardIDs: initial.forwardFacingDeviceDescriptors.map(\.uniqueID),
                backwardIDs: initial.backwardFacingDeviceDescriptors.map(\.uniqueID)
            )
        }
        #endif
    }
}
