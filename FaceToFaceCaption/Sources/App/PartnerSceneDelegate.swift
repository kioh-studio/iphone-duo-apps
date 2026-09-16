import UIKit
import SwiftUI

// TODO(backlog): iPhone Duo outer display via `.sceneAccessory` if Apple adds a non-camera accessory (only CameraCaptureAccessory is documented) (iOS 27.1 SDK) — same PartnerCaptionView.
final class PartnerSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    // UNVERIFIED (2026-09-13, written on Windows): scene(_:willConnectTo:options:) is declared
    // @MainActor on UISceneDelegate in the iOS 26 SDK; confirm no explicit annotation is needed.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(
            rootView: PartnerCaptionView(showsTurnButton: false)
                .environment(ConversationModel.shared)
                .preferredColorScheme(.dark)
        )
        self.window = window
        window.isHidden = false
    }
}
