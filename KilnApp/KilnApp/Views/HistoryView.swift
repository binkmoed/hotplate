import SwiftUI

/// History tab: list of recorded firing sessions with a detail chart for
/// troubleshooting (full temperature curve + events of each firing).
struct HistoryView: View {
    @Environment(KilnClient.self) private var client

    @State private var sessions: [SessionSummary] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var pendingDelete: SessionSummary?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && sessions.isEmpty {
                    ProgressView("Loading firings…")
                } else if let loadError {
                    ContentUnavailableView("Couldn't load", systemImage: "externaldrive.badge.exclamationmark", description: Text(loadError))
                } else if sessions.isEmpty {
                    ContentUnavailableView("No firings yet", systemImage: "clock.arrow.circlepath", description: Text("Completed firings are recorded automatically and appear here."))
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink(value: session) {
                                SessionRow(session: session)
                            }
                            .swipeActions {
                                if session.outcome != "in-progress" {
                                    Button(role: .destructive) {
                                        pendingDelete = session
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: SessionSummary.self) { session in
                SessionDetailView(session: session)
            }
            .refreshable { await load() }
            .task { await load() }
            .alert("Delete this firing?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let session = pendingDelete {
                        Task { await delete(session) }
                    }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                if let target = pendingDelete {
                    Text("The log for '\(target.profile?.name ?? "this firing")' will be permanently removed from the controller.")
                } else {
                    Text("")
                }
            }
        }
    }

    private func delete(_ session: SessionSummary) async {
        guard let rest = client.restAPI else { return }
        if (try? await rest.deleteSession(id: session.id)) != nil {
            sessions.removeAll { $0.id == session.id }
        }
        pendingDelete = nil
    }

    private func load() async {
        guard let rest = client.restAPI else {
            loadError = "Not connected"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await rest.getSessions()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.profile?.name ?? "Firing")
                    .font(.headline)
                Spacer()
                outcomeBadge
            }
            HStack(spacing: 12) {
                if let started = session.started {
                    Label(Self.dateString(started), systemImage: "calendar")
                }
                if let peak = session.peakTemperature {
                    Label("\(Int(peak.rounded()))°", systemImage: "thermometer.high")
                }
                if let runtime = session.runtime {
                    Label(Format.clock(runtime), systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var outcomeBadge: some View {
        let (text, color): (String, Color) = {
            switch session.outcome {
            case "in-progress": return ("Running", .orange)
            case "completed": return ("Completed", .green)
            case "aborted": return ("Aborted", .red)
            default: return (session.outcome?.capitalized ?? "—", .secondary)
            }
        }()
        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private static func dateString(_ epoch: Double) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: epoch))
    }
}

/// Full detail of one firing: the complete chart plus the event timeline.
struct SessionDetailView: View {
    @Environment(KilnClient.self) private var client

    let session: SessionSummary

    @State private var log: SessionLog?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let log {
                    TemperatureChart(
                        history: log.chartHistory,
                        total: log.profile?.totalDuration ?? session.runtime,
                        schedule: log.profile?.data
                    )
                    .frame(height: 240)

                    statsGrid(log)

                    if !log.events.isEmpty {
                        eventList(log)
                    }
                } else if isLoading {
                    ProgressView().padding(.top, 60)
                } else if let errorText {
                    ContentUnavailableView("Couldn't load", systemImage: "externaldrive.badge.exclamationmark", description: Text(errorText))
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle(session.profile?.name ?? "Firing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard log == nil, let rest = client.restAPI else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            log = try await rest.getSessionLog(id: session.id)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func statsGrid(_ log: SessionLog) -> some View {
        let cfg = client.displayConfig
        let peak = session.peakTemperature.map { "\(Int($0.rounded()))°" } ?? "—"
        let currency = cfg.currencyType
        return HStack(spacing: 0) {
            statTile("Peak", peak)
            Divider().frame(height: 40)
            statTile("Duration", Format.clock(session.runtime ?? 0))
            Divider().frame(height: 40)
            statTile("Cost", session.cost.map { String(format: "%.2f%@", $0, currency) } ?? "—")
            Divider().frame(height: 40)
            statTile("Samples", "\(log.samples.count)")
        }
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2).bold().foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private func eventList(_ log: SessionLog) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Events").font(.headline)
            ForEach(Array(log.events.enumerated()), id: \.offset) { _, e in
                HStack {
                    Image(systemName: iconName(e.name))
                        .foregroundStyle(iconColor(e.name))
                        .frame(width: 22)
                    Text(e.detail?.isEmpty == false ? e.detail! : e.name.capitalized)
                    Spacer()
                    if let t = e.time, let started = log.started {
                        Text("+\(Format.clock(max(0, t - started)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func iconName(_ name: String) -> String {
        switch name {
        case "run": return "play.circle"
        case "resume": return "play.circle"
        case "pause": return "pause.circle"
        default: return "exclamationmark.triangle"
        }
    }

    /// Timeline entries are muted so they don't read as tappable controls
    /// (e.g. 'resume' is a historical record, not a button).
    private func iconColor(_ name: String) -> Color {
        switch name {
        case "run", "resume", "pause": return .secondary
        default: return .orange
        }
    }
}
