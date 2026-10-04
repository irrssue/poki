import SwiftUI

@main
struct PokiApp: App {
    @UIApplicationDelegateAdaptor(PokiAppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

