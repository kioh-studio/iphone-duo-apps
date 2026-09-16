import UIKit

// UNVERIFIED (2026-09-13, written on Windows): UIApplicationDelegate's scene-configuration
// method signature and whether it is MainActor-isolated by default under Swift 6 strict
// concurrency on the iOS 26 SDK.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        if role == .windowExternalDisplayNonInteractive {
            let configuration = UISceneConfiguration(name: "Partner", sessionRole: role)
            configuration.delegateClass = PartnerSceneDelegate.self
            return configuration
        }
        return UISceneConfiguration(name: nil, sessionRole: role)
    }
}
