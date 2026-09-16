import SwiftUI

@main
struct AcrossApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = ConversationModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.Palette.accent)
        }
    }
}

private struct RootView: View {
    @Environment(ConversationModel.self) private var model

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()
            if model.phase == .conversation {
                ConversationView()
            } else {
                LanguageSetupView(mode: .launch)
            }
        }
    }
}
