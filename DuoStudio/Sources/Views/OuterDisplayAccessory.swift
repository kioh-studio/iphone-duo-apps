import SwiftUI

/// Shows `SubjectView` on the Duo's outer display via `CameraCaptureAccessory`, only when the
/// iOS 27.1 SDK is available. `StudioModel` forces `isOuterEnabled` off in self-portrait mode (the
/// main screen already shows the same content there), so this modifier doesn't need to know which
/// mode is active — it just reflects `isOuterEnabled`/`isOuterAvailable`.
///
/// Confirmed against Apple's published docs (2026-09-20):
/// https://developer.apple.com/documentation/swiftui/view/sceneaccessory(content:) and
/// https://developer.apple.com/documentation/swiftui/cameracaptureaccessory
struct OuterDisplayAccessory: ViewModifier {
    let model: StudioModel

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.sceneAccessory {
                CameraCaptureAccessory(isEnabled: outerEnabledBinding) {
                    SubjectView()
                        .environment(model)
                }
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
