import SwiftUI

@main
struct PokiApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notifications
    @UIApplicationDelegateAdaptor(PokiAppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear { notifications.attach(model) }
        }
    }
}

