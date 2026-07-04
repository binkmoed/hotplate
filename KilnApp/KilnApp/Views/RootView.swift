import SwiftUI

/// Decides between the connection setup flow and the main tab interface.
struct RootView: View {
    @Environment(KilnClient.self) private var client

    var body: some View {
        ZStack {
            Color.black.opacity(0.04).ignoresSafeArea()
            Group {
                switch client.phase {
                case .disconnected, .failed:
                    ConnectionSetupView()
                case .connecting:
                    ProgressView("Connecting…")
                case .connected:
                    MainTabView()
                }
            }
            .animation(.easeInOut(duration: 0.25), value: client.phase)
        }
        .task {
            // Auto-connect if we already have saved credentials.
            if client.connection != nil && client.phase == .disconnected {
                await client.reconnect()
            }
        }
    }
}
