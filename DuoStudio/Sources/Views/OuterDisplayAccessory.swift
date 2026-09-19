import SwiftUI

/// Shows `SubjectView` on the Duo's outer display via `CameraCaptureAccessory`, only when the
/// iOS 27.1 SDK is available. `StudioModel` forces `isOuterEnabled` off in self-portrait mode (the
/// main screen already shows the same content there), so this modifier doesn't need to know which
/// mode is active — it just reflects `isOuterEnabled`/`isOuterAvailable`.
///
/// UNVERIFIED (2026-09-20, written on Windows): the whole shape of this modifier, per Tech Talk
/// 111464. Apple documents only the camera-capture use of `.sceneAccessory` — a non-camera
/// accessory API isn't confirmed to exist at all — so this file's shape may need to change once
/// the real SDK is available.
struct OuterDisplayAccessory: ViewModifier {
    let model: StudioModel

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            // UNVERIFIED (2026-09-20, written on Windows): `.sceneAccessory { CameraCaptureAccessory
            // (isEnabled:) { ... } }` — exact modifier name, initializer, and content-closure shape.
            content.sceneAccessory {
                CameraCaptureAccessory(isEnabled: outerEnabledBinding) {
                    SubjectView()
                        .environment(model)
                }
                // UNVERIFIED (2026-09-20, written on Windows): `.onAvailabilityChange { Bool in }` —
                // exact modifier name and closure signature for outer-display availability.
                .onAvailabilityChange { available in
                    model.isOuterAvailable = available
                }
            }
        } else {
            content
        }
    }

    /// `model` is a plain reference here (not a View's `@Bindable`), so the binding is built by
    /// hand instead of via `$model.isOuterEnabled`.
    private var outerEnabledBinding: Binding<Bool> {
        Binding(get: { model.isOuterEnabled }, set: { model.isOuterEnabled = $0 })
    }
}
