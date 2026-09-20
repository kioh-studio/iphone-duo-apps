import SwiftUI
#if DUO_DIRECTION_COORDINATOR
import AVFoundation
import AVKit
#endif

/// Invisible host view for `AVCaptureDeviceDirectionCoordinator` (AVKit, main-actor isolated),
/// which needs a real, on-screen `UIView` to reason about which side of the Duo it's on. Placed in
/// `StudioView`'s background. Everything here is a no-op unless the app is built with the
/// `DUO_DIRECTION_COORDINATOR` flag (see `project.yml`) on iOS 27.1+ — the flag is off by default
/// so a first Mac build can't fail on this API before it's been checked against the real SDK.
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
        @available(iOS 27.1, *)
        func start(view: UIView, model: StudioModel) {
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInOuterUltraWideCamera, .builtInInnerUltraWideCamera, .builtInDualWideCamera,
            ]
            let coordinator = AVCaptureDeviceDirectionCoordinator(view: view, deviceTypes: deviceTypes) { directions in
                // UNVERIFIED (2026-09-20, written on Windows): `AVCaptureDeviceDescriptor.uniqueID`
                // as the way to turn a direction-map entry into something `AVCaptureDevice
                // (uniqueID:)` can resolve later on `sessionQueue` — not checked against the real
                // SDK.
                let forwardIDs = directions.forwardFacingDeviceDescriptors.map(\.uniqueID)
                let backwardIDs = directions.backwardFacingDeviceDescriptors.map(\.uniqueID)
                Task { @MainActor in
                    model.updateCameraDirections(forwardIDs: forwardIDs, backwardIDs: backwardIDs)
                }
            }
            directionCoordinator = coordinator
        }
        #endif
    }
}
