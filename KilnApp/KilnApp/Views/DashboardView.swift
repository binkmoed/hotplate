import SwiftUI

/// The live dashboard: current temperature, target, progress, runtime and controls.
struct DashboardView: View {
    @Environment(KilnClient.self) private var client

    @State private var showStopConfirmation = false
    @State private var showStartSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    profilePicker
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
            .navigationTitle(client.displayProfile?.name ?? "Kiln")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: stateIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(stateColor)
                }
            }
            .sheet(isPresented: $showStartSheet) {
                StartFiringSheet()
                    .presentationDetents([.medium])
            }
            .confirmationDialog(
                "Stop firing?",
                isPresented: $showStopConfirmation,
                titleVisibility: .visible
            ) {
                Button("Stop", role: .destructive) {
                    Task { await client.stop() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will abort the current firing and return the kiln to idle. The elements will be de-energised.")
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

    private var statusCard: some View {
        let status = client.status
        let temp = status?.temperature ?? 0
        let target = status?.target ?? 0
        let units = client.displayConfig.tempScale
        let progress = Format.progress(
            runtime: status?.runtime, total: status?.totaltime
        )
        return VStack(spacing: 16) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(Int(temp.rounded()))")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(units.lowercased() == "f" ? "°F" : "°C")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("TARGET")
                        .font(.caption2).bold()
                        .foregroundStyle(.secondary)
                    Text("\(Int(target.rounded()))°")
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
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
            statTile(title: "Deg/h", value: Format.slope(status?.heatRate))
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

    private func heatText(_ heat: Double?, pidOut: Double?, state: KilnState?) -> String {
        // Only trust the PID output as a heat signal while actively running (it can go stale
        // after the firing stops). The server now reports `heat` accurately in every frame.
        if state == .running, let out = pidOut, out > 0.01 { return "ON" }
        guard let heat else { return "OFF" }
        return heat >= 0.5 ? "ON" : "OFF"
    }
}

/// Sheet for choosing a profile + optional start offset before starting a firing.
struct StartFiringSheet: View {
    @Environment(KilnClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProfile: Profile?
    @State private var startAtMinutes: Double = 0
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    if client.profiles.isEmpty {
                        Text("No profiles. Create one in the Profiles tab.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Profile", selection: $selectedProfile) {
                            ForEach(client.profiles) { Text($0.name).tag(Optional($0)) }
                        }
                    }
                }
                Section {
                    VStack(alignment: .leading) {
                        Text("Start at: \(Int(startAtMinutes)) min")
                        Slider(value: $startAtMinutes, in: 0...300, step: 5)
                    }
                } header: { Text("Skip-ahead") } footer: {
                    Text("Optional: begin the profile this many minutes in. Leave at 0 for a normal start.")
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
                if selectedProfile == nil { selectedProfile = client.profiles.first }
            }
        }
    }

    private func start() async {
        guard let profile = selectedProfile else { return }
        isStarting = true
        await client.run(profile: profile.name, startAt: startAtMinutes * 60)
        isStarting = false
        if client.lastCommandError == nil {
            dismiss()
        }
    }
}
