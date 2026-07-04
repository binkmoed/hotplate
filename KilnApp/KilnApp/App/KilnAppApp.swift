import SwiftUI

@main
struct KilnAppApp: App {
    @State private var client = KilnClient()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(client)
                .task { NotificationManager.shared.requestAuthorization() }
        }
    }
}
