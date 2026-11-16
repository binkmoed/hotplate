import SwiftUI

@main
struct HotplateAppApp: App {
    @State private var client = HotplateClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(client)
                .task { NotificationManager.shared.requestAuthorization() }
        }
    }
}
