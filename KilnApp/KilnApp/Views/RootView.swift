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
            // Auto-connect only if we have a PERSISTED connection in Keychain.
            // This prevents loops after "Forget Server" + bad IP attempts.
            if ServerConnection.saved != nil && client.phase == .disconnected {
                Logger.shared.debug("Auto-reconnecting to saved server")
                await client.reconnect()
            }
        }
    }
}
