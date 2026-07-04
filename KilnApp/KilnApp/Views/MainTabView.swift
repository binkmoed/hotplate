import SwiftUI

/// Tabbed main interface shown once connected.
struct MainTabView: View {
    @Environment(KilnClient.self) private var client

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Kiln", systemImage: "flame.fill") }

            ProfileListView()
                .tabItem { Label("Profiles", systemImage: "list.bullet.rectangle") }
                .task { client.refreshStorage() }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.orange)
        .overlay(alignment: .top) {
            if !client.isConnected {
                reconnectBanner
            }
        }
    }

    private var reconnectBanner: some View {
        VStack(spacing: 8) {
            Label("Connection lost. Reconnecting…", systemImage: "wifi.slash")
                .font(.footnote)
                .padding(.horizontal).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
        }
        .task {
            while !client.isConnected {
                await client.reconnect()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
}
