import Foundation
import SwiftUI

/// High-level connection state surfaced to the UI.
enum ConnectionPhase: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

/// The single source of truth for the app. Owns the REST client and the WebSocket service,
/// exposes observable state for SwiftUI, and is driven entirely on the main actor.
@MainActor
@Observable
final class KilnClient: WebSocketServiceDelegate {

    // MARK: Published state

    /// Saved host/port (nil until first setup). Use `configure(host:port:)` to set.
    private(set) var connection: ServerConnection?

    /// Overall phase shown by the connect banner.
    private(set) var phase: ConnectionPhase = .disconnected

    /// Per-socket online indicator.
    private(set) var socketState: [String: Bool] = [:]

    /// Latest live status (nil until first frame).
    private(set) var status: KilnStatus?

    /// Active profile (from the backlog message).
    private(set) var activeProfile: Profile?

    /// Profile chosen on the dashboard to preview when idle. Persists across sessions
    /// via UserDefaults; defaults to the first profile on the server.
    var previewProfileName: String? {
        get { UserDefaults.standard.string(forKey: "kiln.previewProfile") }
        set { UserDefaults.standard.set(newValue, forKey: "kiln.previewProfile") }
    }

    /// The profile whose schedule the dashboard should show right now:
    /// the active firing profile if running, otherwise the user's selected preview profile.
    var displayProfile: Profile? {
        if currentState == .running || currentState == .paused,
           let name = status?.profile, let p = profiles.first(where: { $0.name == name }) {
            return p
        }
        if let preview = previewProfileName, let p = profiles.first(where: { $0.name == preview }) {
            return p
        }
        return profiles.first
    }

    /// Temperature history seeded from the backlog log, appended each status frame.
    private(set) var history: [ChartSample] = []

    /// Offset (seconds) applied to actual-temperature x-values when a firing is
    /// started with skip-ahead. Keeps the orange line aligned with the schedule.
    private(set) var firingStartOffset: Double = 0

    /// Profiles on the server.
    private(set) var profiles: [Profile] = []

    /// Display config (units, currency, kWh rate, element power).
    private(set) var displayConfig: DisplayConfig = .defaultConfig

    /// Full config document from `GET /api/config`.
    private(set) var fullConfig: FullConfig?

    /// Last server-side error from a REST command (cleared on next success).
    private(set) var lastCommandError: String?

    /// Set when a firing finishes on its own (runs to completion). The dashboard
    /// shows an acknowledgement alert until the user dismisses it.
    private(set) var completedFiring: SessionSummary?
    /// Set when a firing ends aborted for a non-user reason (safety abort,
    // stall, sensor fault…). User-initiated stops do not raise an alert.
    private(set) var abortedFiring: SessionSummary?
    private(set) var abortReason: String?
    private var userStoppedFiring = false

    func acknowledgeCompletedFiring() { completedFiring = nil }
    func acknowledgeAbortedFiring() { abortedFiring = nil; abortReason = nil }

    // MARK: Internals

    private let session: URLSession
    private var ws: WebSocketService?
    private var rest: ControllerAPI?
    private var lastStateForNotifications: KilnState?

    init(session: URLSession = .shared) {
        self.session = session
        if let saved = ServerConnection.saved {
            self.connection = saved
        }
    }

    var isConnected: Bool { phase == .connected }
    var currentState: KilnState { status?.state ?? .idle }

    var restAPI: ControllerAPI? { rest }

    // Guard against concurrent/repeated connect attempts causing loops.
    private(set) var isConnecting = false

    // MARK: - Connection lifecycle

    /// Validate and persist a host/port, then connect all sockets.
    func connect(to newConnection: ServerConnection) async {
        // Re-entry guard: prevent the flashing loop when multiple connect
        // calls overlap (e.g. auto-reconnect + manual retry).
        guard !isConnecting else {
            Logger.shared.debug("connect() called while already connecting — ignoring")
            return
        }
        isConnecting = true
        defer { isConnecting = false }

        Logger.shared.debug("Attempting to connect to \(newConnection.host):\(newConnection.port)")
        disconnect()
        phase = .connecting
        let rest = ControllerAPI(baseURL: newConnection.httpBase, session: session)
        self.rest = rest
        do {
            Logger.shared.debug("Checking server health")
            _ = try await rest.checkHealth()
            Logger.shared.info("Server health check passed")
        } catch {
            Logger.shared.error("Connection failed: \(error.localizedDescription)")
            // Clear the stale REST client so nothing tries to use it.
            self.rest = nil
            // Use a clear, user-facing message.
            phase = .failed("Cannot connect to server")
            return
        }
        // Only persist the connection AFTER the health check passes —
        // a failed attempt must not leave a stale host that triggers loops.
        connection = newConnection
        newConnection.save()
        let service = WebSocketService(delegate: self, session: session)
        self.ws = service
        Logger.shared.debug("Connecting WebSocket to \(newConnection.wsBase)")
        service.connect(to: newConnection.wsBase)
        Task { await self.refreshFullConfig() }
        phase = .connected
        Logger.shared.info("Successfully connected to server")
    }

    /// Reconnect using the previously saved connection (if any).
    func reconnect() async {
        guard let connection else { return }
        await connect(to: connection)
    }

    func disconnect() {
        Logger.shared.info("Disconnecting from server")
        ws?.disconnect()
        ws = nil
        phase = .disconnected
        socketState.removeAll()
    }

    /// Forget the saved connection entirely.
    func forgetConnection() {
        Logger.shared.info("Forgetting server connection")
        disconnect()
        ServerConnection.clear()
        connection = nil
        rest = nil
        isConnecting = false
        status = nil
        activeProfile = nil
        history.removeAll()
        firingStartOffset = 0
        profiles.removeAll()
        fullConfig = nil
    }

    // MARK: - Commands (REST)

    func run(profile name: String, startAt: Double? = nil) async {
        guard let rest else { return }
        // The server's runtime already includes the start offset
        // (run_profile sets start_time = now - startat), so the chart must
        // NOT add it again — that double-counted and shifted the line.
        firingStartOffset = 0
        history.removeAll()
        status = nil
        userStoppedFiring = false
        do {
            try await rest.run(profile: name, startAt: startAt, seek: false)
            lastCommandError = nil
        } catch {
            lastCommandError = error.localizedDescription
        }
    }

    func stop() async {
        guard let rest else { return }
        userStoppedFiring = true
        do {
            try await rest.stop()
            lastCommandError = nil
        } catch {
            lastCommandError = error.localizedDescription
        }
    }

    func pause() async {
        guard let rest else { return }
        do { try await rest.pause(); lastCommandError = nil }
        catch { lastCommandError = error.localizedDescription }
    }

    func resume() async {
        guard let rest else { return }
        do { try await rest.resume(); lastCommandError = nil }
        catch { lastCommandError = error.localizedDescription }
    }

    // MARK: - Config

    func refreshFullConfig() async {
        guard let rest else { return }
        if let cfg = try? await rest.getConfig() {
            self.fullConfig = cfg
        }
    }

    @discardableResult
    func updateConfig(_ updates: [String: Any]) async -> (Bool, String) {
        guard let rest else { return (false, "Not connected") }
        do {
            let res = try await rest.updateConfig(updates)
            lastCommandError = nil
            await refreshFullConfig()
            return (true, res.message + (res.restartRequired ? " (restart required)" : ""))
        } catch {
            lastCommandError = error.localizedDescription
            return (false, error.localizedDescription)
        }
    }

    // MARK: - WebSocketServiceDelegate

    nonisolated func statusSocket(didReceiveBacklog message: BacklogMessage) {
        Task { @MainActor in
            self.activeProfile = message.profile
            // Seed the live chart from the backlog log, if any.
            // Apply the firing-start offset so actual lines up with schedule.
            if let log = message.log, !log.isEmpty {
                let offset = self.firingStartOffset
                // Only seed from RUNNING/PAUSED frames: an IDLE frame after a
                // stop/abort carries runtime=0 + current temperature, which
                // would draw a vertical line at x=0 up to the current temp.
                self.history = log.compactMap { s in
                    guard s.state == .running || s.state == .paused,
                          let t = s.runtime, let temp = s.temperature else { return nil }
                    return ChartSample(runtime: t + offset, temperature: temp, target: s.target ?? 0)
                }
                self.status = log.last
                // If a firing is in progress the backlog only holds the last
                // ~50 samples — fetch the full persisted session to close
                // the gap after a reconnect.
                if log.last?.state == .running || log.last?.state == .paused {
                    self.backfillLiveHistory()
                }
            } else {
                self.history = []
            }
        }
    }

    /// Fetch the in-progress session log from the server and replace the
    /// 50-sample backlog seed with the full firing history.
    private func backfillLiveHistory() {
        guard let rest else { return }
        let offset = firingStartOffset
        Task.detached(priority: .utility) { [weak self] in
            guard let summaries = try? await rest.getSessions(),
                  let latest = summaries.first else { return }
            guard let session = try? await rest.getSessionLog(id: latest.id) else { return }
            let samples = session.samples.compactMap { s -> ChartSample? in
                guard let t = s.runtime, let temp = s.temperature else { return nil }
                return ChartSample(runtime: t + offset, temperature: temp, target: s.target ?? 0)
            }
            guard !samples.isEmpty else { return }
            await MainActor.run { [weak self] in
                guard let self, self.currentState == .running || self.currentState == .paused else { return }
                // Only replace if we actually gained data vs. the backlog seed.
                if samples.count > self.history.count {
                    self.history = samples
                }
            }
        }
    }

    nonisolated func statusSocket(didReceiveStatus status: KilnStatus) {
        Task { @MainActor in
            let wasActive = self.status?.state == .running || self.status?.state == .paused
            self.status = status

            // When the kiln returns to idle (e.g. after Stop), clear the
            // firing history but keep the IDLE status itself — it carries
            // the current temperature (truthful, heat=0, runtime=0), which
            // the Start Firing sheet uses to prefill the seek slider.
            if status.state == .idle {
                if wasActive {
                    firingTransitionTime = Date()
                    self.history.removeAll()
                    self.checkForCompletedFiring()
                }
                self.firingStartOffset = 0
                self.handleStateNotifications(status.state)
                return
            }

            // Only accumulate chart samples while running or paused.
            if status.state == .running || status.state == .paused,
               let t = status.runtime, let temp = status.temperature {
                self.history.append(ChartSample(
                    runtime: t + self.firingStartOffset,
                    temperature: temp,
                    target: status.target ?? 0
                ))
                // Cap history length to keep the chart responsive over long firings.
                if self.history.count > 1200 {
                    self.history.removeFirst(self.history.count - 1200)
                }
            }
            self.handleStateNotifications(status.state)
        }
    }

    nonisolated func storageSocket(didReceiveProfiles profiles: [Profile]) {
        Task { @MainActor in self.profiles = profiles.sorted { $0.name < $1.name } }
    }

    nonisolated func storageSocket(didReceiveResponse resp: String, cmd: String?, profile: Profile?) {
        // Responses are handled imperatively by the editor via refreshStorage() after writes.
    }

    nonisolated func configSocket(didReceiveConfig config: DisplayConfig) {
        Task { @MainActor in self.displayConfig = config }
    }

    nonisolated func webSocketSocket(_ path: String, didChangeConnected connected: Bool) {
        Task { @MainActor in self.socketState[path] = connected }
    }

    // MARK: - Completion detection

    /// After the kiln goes idle, poll the session list briefly: the watcher
    /// writes the 'end' record on its next duty cycle, so the outcome may not
    /// be visible immediately. 'completed' raises the success alert; 'aborted'
    /// raises an alert too — unless the user stopped the firing themselves
    /// (they know, no alert wanted) — with the abort reason from the log.
    private func checkForCompletedFiring() {
        guard let rest else { return }
        let transition = firingTransitionTime
        Task {
            for _ in 0..<6 {
                if Task.isCancelled { return }
                if let sessions = try? await rest.getSessions(),
                   let latest = sessions.first,
                   let started = latest.started,
                   let runtime = latest.runtime {
                    // The newest session must be the one that *just* ended:
                    // its end time (started + runtime) should match the
                    // active→idle transition. (`started` alone is when the
                    // firing began, which is always long before.)
                    let ended = started + runtime
                    guard ended > transition.timeIntervalSince1970 - 30 else {
                        try? await Task.sleep(for: .seconds(2))
                        continue
                    }
                    if latest.outcome == "completed" {
                        self.completedFiring = latest
                        return
                    }
                    if latest.outcome == "aborted" && !self.userStoppedFiring {
                        var reason: String?
                        if let log = try? await rest.getSessionLog(id: latest.id) {
                            reason = log.events.last(where: { $0.name == "abort" })?.detail
                        }
                        self.abortReason = reason
                        self.abortedFiring = latest
                        return
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Wall-clock time of the last active→idle transition.
    private var firingTransitionTime: Date {
        get { UserDefaults.standard.object(forKey: "kiln.firingTransition") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "kiln.firingTransition") }
    }

    // MARK: - Outbound via WS

    func refreshStorage() { ws?.storageList() }
    func saveProfile(_ profile: Profile, force: Bool, completion: @escaping (Bool) -> Void) {
        guard let ws else { completion(false); return }
        ws.storagePut(profile: profile, force: force)
        // The server pushes the updated list right after a successful PUT; rely on the
        // list update rather than a per-write ack. Optimistic completion after a tick.
        completion(true)
    }
    func deleteProfile(name: String) { ws?.storageDelete(name: name) }

    // MARK: - Notifications

    private func handleStateNotifications(_ newState: KilnState?) {
        guard let newState else { return }
        let previous = lastStateForNotifications
        lastStateForNotifications = newState
        guard previous != newState else { return }
        NotificationManager.shared.notifyStateChange(from: previous, to: newState, status: status)
    }
}
