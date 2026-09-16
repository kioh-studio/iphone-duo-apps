import UIKit
import Observation

/// Tracks whether an external (facing) display scene is currently connected.
///
/// Swift 6 note: a MainActor class can't reliably unregister a NotificationCenter token in
/// `deinit` (deinit isn't actor-isolated), so instead of storing observer tokens this watches
/// two long-running `NotificationCenter.notifications(named:)` async sequences in tasks owned
/// by this object. `DisplayMonitor` lives for the app's lifetime (owned by `ConversationModel`),
/// so the tasks never need explicit cancellation.
@MainActor
@Observable
final class DisplayMonitor {
    private(set) var hasFacingDisplay: Bool

    private var connectTask: Task<Void, Never>?
    private var disconnectTask: Task<Void, Never>?

    init() {
        hasFacingDisplay = Self.computeHasFacingDisplay()

        connectTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIScene.willConnectNotification) {
                self?.refresh()
            }
        }
        disconnectTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIScene.didDisconnectNotification) {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        hasFacingDisplay = Self.computeHasFacingDisplay()
    }

    private static func computeHasFacingDisplay() -> Bool {
        UIApplication.shared.connectedScenes.contains { $0.session.role == .windowExternalDisplayNonInteractive }
    }
}
