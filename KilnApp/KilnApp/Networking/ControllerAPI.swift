import Foundation

/// Errors returned by the controller's REST API.
enum APIError: Error, LocalizedError, Equatable {
    case invalidResponse
    case http(Int)
    case server(String)        // { "success": false, "error": "..." }
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .http(let code): return "HTTP \(code)"
        case .server(let msg): return msg
        case .decoding(let msg): return "Decoding error: \(msg)"
        case .transport(let msg): return msg
        }
    }
}

/// REST client for the kiln controller. Stateless except for the base URL, which
/// makes it cheap to recreate when the connection changes.
struct ControllerAPI: Sendable {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Health / stats

    /// Health check. Returns true if the server responds with HTTP 200 on `/api/stats`.
    /// An empty body is a valid "idle" response.
    func checkHealth() async throws -> Bool {
        let (data, resp) = try await data(for: .get, path: "/api/stats")
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
        _ = data
        return true
    }

    /// `GET /api/stats` — PID stats when running, nil when idle (empty body).
    func getStats() async throws -> PIDStats? {
        let (data, resp) = try await data(for: .get, path: "/api/stats")
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
        if data.isEmpty { return nil }
        return try decode(PIDStats.self, data)
    }

    // MARK: - Commands (POST /api)

    /// `POST /api {"cmd":"run","profile":"<name>","startat":<sec>}`
    @discardableResult
    func run(profile: String, startAt: Double? = nil, seek: Bool = true) async throws -> Bool {
        var body: [String: Any] = ["cmd": "run", "profile": profile]
        if let startAt { body["startat"] = startAt }
        if !seek { body["seek"] = false }   // explicit offset: honour it exactly
        return try await sendCommand(body)
    }

    func stop() async throws { try await sendCommand(["cmd": "stop"]) }
    func pause() async throws { try await sendCommand(["cmd": "pause"]) }
    func resume() async throws { try await sendCommand(["cmd": "resume"]) }

    @discardableResult
    private func sendCommand(_ body: [String: Any]) async throws -> Bool {
        let (data, _) = try await postJSON(body, path: "/api")
        // Response shape: { "success": true } or { "success": false, "error": "..." }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let success = obj["success"] as? Bool, !success {
                let msg = (obj["error"] as? String) ?? "Command failed"
                throw APIError.server(msg)
            }
            return true
        }
        return true
    }

    // MARK: - Config

    /// `GET /api/config` — full config document.
    func getConfig() async throws -> FullConfig {
        let (data, resp) = try await data(for: .get, path: "/api/config")
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        return try decode(FullConfig.self, data)
    }

    /// `POST /api/config` with dot-notation updates. e.g. `["pid.kp": 4.0]`.
    @discardableResult
    func updateConfig(_ updates: [String: Any]) async throws -> (restartRequired: Bool, message: String) {
        let (data, _) = try await postJSON(updates, path: "/api/config")
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let success = obj["success"] as? Bool ?? false
        if !success {
            throw APIError.server((obj["error"] as? String) ?? "Config update failed")
        }
        return (
            restartRequired: (obj["restart_required"] as? Bool) ?? false,
            message: (obj["message"] as? String) ?? "Configuration updated"
        )
    }

    // MARK: - Sessions

    /// `GET /api/sessions` — list of recorded firings (newest first).
    func getSessions() async throws -> [SessionSummary] {
        let (data, resp) = try await data(for: .get, path: "/api/sessions")
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        return try decode([SessionSummary].self, data)
    }

    /// `GET /api/sessions/<id>` — full JSON-lines log for one firing.
    func getSessionLog(id: String) async throws -> SessionLog {
        // IDs are server-generated filenames; encode to keep '/' safe.
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let (data, resp) = try await data(for: .get, path: "/api/sessions/\(encoded)")
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw APIError.decoding("Session log is not UTF-8")
        }
        return SessionLogParser.parse(text, id: id)
    }

    /// `DELETE /api/sessions/<id>` — remove one recorded firing.
    func deleteSession(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/sessions/\(encoded)"))
        req.httpMethod = "DELETE"
        req.timeoutInterval = 8
        let (_, resp): (Data, URLResponse)
        do { (_, resp) = try await session.data(for: req) }
        catch { throw APIError.transport(error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - Low-level helpers

    private enum Method: String { case get = "GET", post = "POST" }

    private func data(for method: Method, path: String) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method.rawValue
        req.timeoutInterval = 8
        do {
            return try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func postJSON(_ body: [String: Any], path: String) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw APIError.decoding("Could not encode request body")
        }
        do {
            return try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decoding("\(error)") }
    }
}
