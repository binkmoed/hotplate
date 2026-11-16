import SwiftUI

/// The live dashboard: current temperature, target, progress, runtime and controls.
struct DashboardView: View {
    @Environment(HotplateClient.self) private var client

    @State private var showStopConfirmation = false
    @State private var showStartSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    HStack {
                        profilePicker
                        Spacer()
                        chartLegend
                    }
                    TemperatureChart(
                        history: client.history,
                        total: client.displayProfile?.totalDuration,
                        schedule: client.displayProfile?.data
                    )
                    .frame(height: 220)
                    pidCard
                    actionsRow
                }
                .padding()
            }
            .navigationTitle(client.displayProfile?.name ?? "Hotplate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !client.isConnected {
                        Label("Offline", systemImage: "wifi.slash")
                            .foregroundStyle(.red)
                    }
                    if client.currentState == .running {
                        FlickeringFlame()
                    } else {
                        Image(systemName: stateIcon)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(stateColor)
                    }
                }
            }
            .sheet(isPresented: $showStartSheet) {
                StartFiringSheet()
                    .presentationDetents([.medium])
                    .presentationBackground(.regularMaterial)
            }
            .alert("Stop firing?", isPresented: $showStopConfirmation) {
                Button("Stop", role: .destructive) {
                    Task { await client.stop() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will abort the current firing and return the hotplate to idle. The elements will be de-energised.")
            }
            .alert("Firing Complete", isPresented: Binding(
                get: { client.completedFiring != nil },
                set: { if !$0 { client.acknowledgeCompletedFiring() } }
            )) {
                Button("OK") { client.acknowledgeCompletedFiring() }
            } message: {
                if let firing = client.completedFiring {
                    Text("\(firing.profile?.name ?? "The firing")" + " finished successfully" + summaryText(firing))
                } else {
                    Text("")
                }
            }
            .alert("Firing Aborted", isPresented: Binding(
                get: { client.abortedFiring != nil },
                set: { if !$0 { client.acknowledgeAbortedFiring() } }
            )) {
                Button("OK") { client.acknowledgeAbortedFiring() }
            } message: {
                if let firing = client.abortedFiring {
                    let reason = client.abortReason.map { " — \($0)" } ?? ""
                    Text("\(firing.profile?.name ?? "The firing") was aborted\(reason)" + summaryText(firing))
                } else {
                    Text("")
                }
            }
        }
    }

    // MARK: - Subviews

    private var profilePicker: some View {
        // While a firing runs the profile is fixed; when idle the user can pick which
        // profile's schedule to preview on the chart.
        Group {
            if client.currentState == .running || client.currentState == .paused {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                    Text(client.status?.profile ?? "—")
                        .font(.subheadline.bold())
                    Text("running").font(.caption).foregroundStyle(.secondary)
                }
            } else if !client.profiles.isEmpty {
                Menu {
                    ForEach(client.profiles) { p in
                        Button(p.name) { client.previewProfileName = p.name }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text(client.displayProfile?.name ?? "Select profile")
                            .font(.subheadline.bold())
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chartLegend: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Capsule().fill(Color.orange).frame(width: 14, height: 3)
                Text("Actual").font(.caption2)
            }
            HStack(spacing: 4) {
                Capsule().fill(Color.green.opacity(0.6)).frame(width: 14, height: 3)
                Text("Schedule").font(.caption2)
            }
        }
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private var statusCard: some View {
        let status = client.status
        let temp = status?.temperature ?? 0
        let target = status?.target ?? 0
        let units = client.displayConfig.tempScale
        let progress = Format.progress(
            runtime: status?.runtime, total: status?.totaltime
        )
        return VStack(spacing: 16) {
            // Temperature centred, with target underneath.
            VStack(spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(Int(temp.rounded()))")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(units.lowercased() == "f" ? "°F" : "°C")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                Text("TARGET \(Int(target.rounded()))°")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .tint(.orange)
                HStack {
                    Text(Format.clock(status?.runtime))
                    Spacer()
                    Text(Format.clock(status?.totaltime))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var pidCard: some View {
        let status = client.status
        let cfg = client.displayConfig
        return HStack(spacing: 0) {
            statTile(title: "Heat", value: heatText(status?.heat, pidOut: status?.pidstats?.out, state: status?.state))
            Divider().frame(height: 40)
            statTile(title: "Cost", value: Format.cost(status?.cost, currency: cfg.currencyType, rate: cfg.kwhRate))
        }
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption2).bold().foregroundStyle(.secondary)
            Text(value).font(.subheadline.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private var actionsRow: some View {
        HStack(spacing: 12) {
            switch client.currentState {
            case .idle:
                Button {
                    showStartSheet = true
                } label: {
                    Label("Start Firing", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            case .running:
                Button {
                    Task { await client.pause() }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(role: .destructive) {
                    showStopConfirmation = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            case .paused:
                Button {
                    Task { await client.resume() }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .destructive) {
                    showStopConfirmation = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Helpers

    private func summaryText(_ firing: SessionSummary) -> String {
        var parts: [String] = []
        if let peak = firing.peakTemperature {
            parts.append("peak \(Int(peak.rounded()))°")
        }
        if let runtime = firing.runtime {
            parts.append("took \(Format.clock(runtime))")
        }
        return parts.isEmpty ? "." : " — " + parts.joined(separator: ", ") + "."
    }

    private var stateIcon: String {
        switch client.currentState {
        case .idle: return "circle.dashed"
        case .running: return "flame.fill"
        case .paused: return "pause.circle"
        }
    }

    private var stateColor: Color {
        switch client.currentState {
        case .idle: return .secondary
        case .running: return .orange
        case .paused: return .yellow
        }
    }

    private func heatText(_ heat: Double?, pidOut: Double?, state: HotplateState?) -> String {
        // Only trust the PID output as a heat signal while actively running (it can go stale
        // after the firing stops). The server now reports `heat` accurately in every frame.
        if state != .running && state != .paused { return "OFF" }   // elements can't be on when idle
        if state == .running, let out = pidOut, out > 0.01 { return "ON" }
        guard let heat else { return "OFF" }
        return heat >= 0.5 ? "ON" : "OFF"
    }
}

/// Toolbar flame that gently flickers while a firing program is running.
struct FlickeringFlame: View {
    @State private var flicker = false

    var body: some View {
        Image(systemName: "flame.fill")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.orange)
            .scaleEffect(flicker ? 1.18 : 0.88)
            .opacity(flicker ? 1.0 : 0.7)
            .animation(
                .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                value: flicker
            )
            .onAppear { flicker = true }
    }
}

/// Sheet for choosing a profile + optional start offset before starting a firing.
struct StartFiringSheet: View {
    @Environment(HotplateClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProfile: Profile?
    @State private var startAtSeconds: Double = 0
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    if client.profiles.isEmpty {
                        Text("No profiles. Create one in the Profiles tab.")
                            .foregroundStyle(.secondary)
                    } else {
                        // The profile was already chosen in the dashboard
                        // dropdown — confirm it here, don't ask again.
                        LabeledContent("Profile", value: selectedProfile?.name ?? "—")
                    }
                }
                Section {
                    VStack(alignment: .leading) {
                        Text("Start at: \(Int(startAtSeconds)) s")
                        Slider(value: $startAtSeconds, in: 0...maxSeconds, step: 5)
                        if startAtSeconds > suggestedSeconds {
                            Text("You are skipping ahead of the current temperature.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Skip-ahead") } footer: {
                    Text("Prefilled with where the schedule matches the current hotplate temperature (seek). Drag back to 0 to start from the beginning.")
                }
                if let error = client.lastCommandError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Start Firing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await start() }
                    } label: {
                        if isStarting { ProgressView() } else { Text("Start") }
                    }
                    .disabled(selectedProfile == nil || isStarting)
                }
            }
            .onAppear {
                // Preselect the profile the user picked on the dashboard
                // (falls back to the first profile when none is chosen).
                if selectedProfile == nil {
                    selectedProfile = client.displayProfile ?? client.profiles.first
                }
                prefillSeek()
            }
            .onChange(of: selectedProfile) { _, _ in prefillSeek() }
            .onDisappear {
                startAtSeconds = 0
            }
        }
    }

    /// Slider max: leave at least the last 10 s of the profile so a firing
    /// always runs some of the schedule. Floored at 5 so the Slider always
    /// has a valid non-degenerate range (crashed when 0...0 with a step).
    private var maxSeconds: Double {
        max((selectedProfile?.data.last?.time ?? 0) - 10, 5)
    }

    /// Where the schedule first reaches the current hotplate temperature —
    /// same rule the server used to apply silently. Prefills the slider so
    /// what you see is what will happen; dragging back to 0 forces a cold
    /// start because we now send an explicit startat with seek disabled.
    private var suggestedSeconds: Double {
        guard let profile = selectedProfile,
              let currentTemp = client.status?.temperature else { return 0 }
        return min(profile.seekSeconds(forCurrentTemp: currentTemp), maxSeconds)
    }

    private func prefillSeek() {
        startAtSeconds = min(suggestedSeconds, maxSeconds)
    }

    private func start() async {
        guard let profile = selectedProfile else { return }
        isStarting = true
        await client.run(profile: profile.name, startAt: startAtSeconds)
        isStarting = false
        if client.lastCommandError == nil {
            startAtSeconds = 0   // Reset so next firing starts at 0 s.
            dismiss()
        }
    }
}
