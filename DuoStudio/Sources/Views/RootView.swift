import SwiftUI

/// App root: onboarding on first launch, then the camera. Owns the skin-driven colour scheme and
/// tint (the light skins need `.light`; the outer display forces `.dark` itself). The camera
/// permission is requested when the camera first appears - i.e. after onboarding, not before.
struct RootView: View {
    @Environment(StudioModel.self) private var model
    @AppStorage("hasOnboarded") private var hasOnboarded = false

    var body: some View {
        Group {
            if hasOnboarded {
                StudioView()
                    .task { await model.requestCameraAccess() }
            } else {
                OnboardingView { hasOnboarded = true }
            }
        }
        .background(Theme.Palette.paper.ignoresSafeArea())
        // UNVERIFIED (2026-10-18, written on Windows): that a root `preferredColorScheme` also reaches
        // presented sheets (Library, Controls, ...), and that Observation re-evaluates this body when
        // the skin changes.
        .preferredColorScheme(SkinStore.shared.skin.colorScheme)
        .tint(Theme.Palette.accent)
    }
}
