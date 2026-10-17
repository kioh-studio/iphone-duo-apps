import SwiftUI

@main
struct DuoStudioApp: App {
    @State private var model = StudioModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
