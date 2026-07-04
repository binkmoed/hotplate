import SwiftUI

/// Lists profiles on the server; pull to refresh, tap to edit, swipe to delete.
struct ProfileListView: View {
    @Environment(KilnClient.self) private var client

    @State private var editing: Profile?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                if client.profiles.isEmpty {
                    ContentUnavailableView(
                        "No Profiles",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Tap + to create your first firing profile.")
                    )
                } else {
                    ForEach(client.profiles) { profile in
                        NavigationLink(value: profile) {
                            ProfileRow(profile: profile)
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            client.deleteProfile(name: client.profiles[idx].name)
                        }
                    }
                }
            }
            .navigationTitle("Profiles")
            .navigationDestination(for: Profile.self) { profile in
                ProfileEditorView(profile: profile)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        creating = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $creating) {
                NavigationStack {
                    ProfileEditorView(profile: Profile.blank, isNew: true)
                }
            }
            .refreshable {
                client.refreshStorage()
            }
            .overlay {
                if client.profiles.isEmpty && !client.isConnected {
                    ContentUnavailableView("Not Connected", systemImage: "wifi.slash")
                }
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(profile.name).font(.headline)
                Spacer()
                Text("\(Int(profile.peakTemp))°")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Label(Format.clock(profile.totalDuration), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(profile.data.count) pts", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
