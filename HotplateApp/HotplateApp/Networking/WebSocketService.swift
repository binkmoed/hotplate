import Foundation

/// Receives decoded WebSocket events on the main actor.
@MainActor
protocol WebSocketServiceDelegate: AnyObject {
    func statusSocket(didReceiveBacklog message: BacklogMessage)
    func statusSocket(didReceiveStatus status: HotplateStatus)
    func storageSocket(didReceiveProfiles profiles: [Profile])
    func storageSocket(didReceiveResponse resp: String, cmd: String?, profile: Profile?)
    func configSocket(didReceiveConfig config: DisplayConfig)
    func webSocketSocket(_ path: String, didChangeConnected connected: Bool)
}

/// Manages the four hotplate-controller WebSockets (`/status`, `/control`, `/storage`, `/config`)
/// with independent receive loops and exponential reconnect backoff. Decoded payloads are
/// forwarded to a `@MainActor` delegate.
final class WebSocketService: @unchecked Sendable {
    static let statusPath = "/status"
    static let controlPath = "/control"
    static let storagePath = "/storage"
    static let configPath = "/config"

    private weak var delegate: (any WebSocketServiceDelegate)?
    private let session: URLSession
    private var base: URL?
    private let decoder = JSONDecoder()

    private let lock = NSLock()
    private var tasks: [String: URLSessionWebSocketTask] = [:]
    private var loops: [String: Task<Void, Never>] = [:]
    private var stopping = false

    init(delegate: any WebSocketServiceDelegate, session: URLSession = .shared) {
        self.delegate = delegate
        self.session = session
    }

    /// Begin all four sockets against the given base URL.
    func connect(to base: URL) {
        Task { @MainActor in Logger.shared.debug("WebSocket connect called for \(base)") }
        disconnect()
        stopping = false
        self.base = base
        startLoop(Self.statusPath, receive: { [weak self] in await self?.receiveStatus() })
        startLoop(Self.storagePath, receive: { [weak self] in await self?.receiveStorage() })
        startLoop(Self.configPath, receive: { [weak self] in await self?.receiveConfig() })
        openSocket(Self.controlPath)
    }

    /// Stop every socket and cancel pending reconnect loops.
    func disconnect() {
        stopping = true
        for (_, task) in tasks { task.cancel(with: .goingAway, reason: nil) }
        tasks.removeAll()
        for (_, loop) in loops { loop.cancel() }
        loops.removeAll()
        for path in [Self.statusPath, Self.storagePath, Self.configPath, Self.controlPath] {
            Task { @MainActor in delegate?.webSocketSocket(path, didChangeConnected: false) }
        }
    }

    // MARK: - Outbound (storage / control)

    /// `PUT` (save) a profile via `/storage`. `force` overwrites an existing name.
    func storagePut(profile: Profile, force: Bool) {
        let body: [String: Any] = [
            "cmd": "PUT",
            "profile": profile.asJSONObject,
            "force": force,
        ]
        sendJSON(Self.storagePath, body: body)
    }

    /// `DELETE` a profile by name via `/storage`.
    func storageDelete(name: String) {
        let body: [String: Any] = [
            "cmd": "DELETE",
            "profile": ["name": name],
        ]
        sendJSON(Self.storagePath, body: body)
    }

    /// Request the profile list via `/storage`.
    func storageList() { sendText(Self.storagePath, text: "GET") }

    /// Refresh display config via `/config`.
    func configRefresh() { sendText(Self.configPath, text: "GET") }

    /// Send `STOP` via `/control` (alternative to REST `stop`).
    func controlStop() {
        sendJSON(Self.controlPath, body: ["cmd": "STOP"])
    }

    /// Send `RUN` via `/control` with a full profile object.
    func controlRun(profile: Profile) {
        sendJSON(Self.controlPath, body: [
            "cmd": "RUN",
            "profile": profile.asJSONObject,
        ])
    }

    // MARK: - Internals

    private func startLoop(_ path: String, receive: @escaping () async -> Void) {
        loops[path]?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.reconnectLoop(path, receive: receive)
        }
        loops[path] = task
    }

    private func reconnectLoop(_ path: String, receive: @escaping () async -> Void) async {
        var attempt = 0
        while !stopping {
            let socket = openSocket(path)
            if socket == nil { break }
            await receive()
            // receive() returns only on close/error.
            closeSocket(path)
            Task { @MainActor in delegate?.webSocketSocket(path, didChangeConnected: false) }
            if stopping { break }
            attempt = min(attempt + 1, 6)
            let delay = pow(2.0, Double(attempt))   // 2s..64s
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    @discardableResult
    private func openSocket(_ path: String) -> URLSessionWebSocketTask? {
        guard let base else { return nil }
        let url = base.appendingPathComponent(path)
        Task { @MainActor in Logger.shared.debug("Opening socket: \(url.path)") }
        let task = session.webSocketTask(with: url)
        lock.lock()
        tasks[path]?.cancel(with: .goingAway, reason: nil)
        tasks[path] = task
        lock.unlock()
        task.resume()
        Task { @MainActor in delegate?.webSocketSocket(path, didChangeConnected: true) }
        return task
    }

    private func closeSocket(_ path: String) {
        lock.lock()
        let t = tasks.removeValue(forKey: path)
        lock.unlock()
        t?.cancel(with: .goingAway, reason: nil)
    }

    private func currentTask(_ path: String) -> URLSessionWebSocketTask? {
        lock.lock(); defer { lock.unlock() }
        return tasks[path]
    }

    // MARK: Receive handlers

    private func receiveStatus() async {
        guard let task = currentTask(Self.statusPath) else { return }
        do {
            while !stopping {
                let msg = try await task.receive()
                guard case .data(let data) = msg, !data.isEmpty else {
                    if case .string(let s) = msg, let d = s.data(using: .utf8) {
                        try await routeStatusData(d)
                    }
                    continue
                }
                try await routeStatusData(data)
            }
        } catch {
            // loop will reconnect
        }
    }

    private func routeStatusData(_ data: Data) async throws {
        // First frame on /status is the backlog message {"type":"backlog",...}.
        if let peek = try? decoder.decode(BacklogMessage.self, from: data), peek.type == "backlog" {
            await MainActor.run { delegate?.statusSocket(didReceiveBacklog: peek) }
            return
        }
        let status = try decoder.decode(HotplateStatus.self, from: data)
        await MainActor.run { delegate?.statusSocket(didReceiveStatus: status) }
    }

    private func receiveStorage() async {
        guard let task = currentTask(Self.storagePath) else { return }
        do {
            while !stopping {
                let msg = try await task.receive()
                let data: Data
                switch msg {
                case .data(let d): data = d
                case .string(let s): data = s.data(using: .utf8) ?? Data()
                @unknown default: continue
                }
                try routeStorageData(data)
            }
        } catch {}
    }

    private func routeStorageData(_ data: Data) throws {
        // The /storage socket emits two kinds of frames:
        //   1. a JSON array of profiles (on connect, and after PUT/DELETE via list_profiles())
        //   2. a response object {"cmd":"PUT"/"DELETE","profile":{...},"resp":"OK"/"FAIL"}
        if data.first == 0x5B {   // '['
            if let profiles = try? decoder.decode([Profile].self, from: data) {
                Task { @MainActor in delegate?.storageSocket(didReceiveProfiles: profiles) }
                return
            }
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let resp = (obj["resp"] as? String) ?? ""
            let cmd = obj["cmd"] as? String
            var profile: Profile?
            if let pdict = obj["profile"] as? [String: Any],
               let pdata = try? JSONSerialization.data(withJSONObject: pdict) {
                profile = try? decoder.decode(Profile.self, from: pdata)
            }
            Task { @MainActor in delegate?.storageSocket(didReceiveResponse: resp, cmd: cmd, profile: profile) }
        }
    }

    private func receiveConfig() async {
        guard let task = currentTask(Self.configPath) else { return }
        do {
            while !stopping {
                let msg = try await task.receive()
                let data: Data
                switch msg {
                case .data(let d): data = d
                case .string(let s): data = s.data(using: .utf8) ?? Data()
                @unknown default: continue
                }
                if let cfg = try? decoder.decode(DisplayConfig.self, from: data) {
                    await MainActor.run { delegate?.configSocket(didReceiveConfig: cfg) }
                }
            }
        } catch {}
    }

    // MARK: Send helpers

    private func sendText(_ path: String, text: String) {
        guard let task = currentTask(path) else { return }
        task.send(.string(text)) { _ in }
    }

    private func sendJSON(_ path: String, body: [String: Any]) {
        guard let task = currentTask(path),
              let data = try? JSONSerialization.data(withJSONObject: body),
              let str = String(data: data, encoding: .utf8) else { return }
        task.send(.string(str)) { _ in }
    }
}

extension Profile {
    /// JSON dictionary form for outbound messages (matches wire schema).
    var asJSONObject: [String: Any] {
        [
            "type": "profile",
            "name": name,
            "temp_units": tempUnits,
            "data": data.map { [$0.time, $0.temp] },
        ]
    }
}
