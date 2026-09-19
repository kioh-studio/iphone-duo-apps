import SwiftUI

@main
struct DuoStudioApp: App {
    @State private var model = StudioModel()

    var body: some Scene {
        WindowGroup {
            StudioView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.Palette.accent)
                .task { await model.requestCameraAccess() }
        }
    }
}
