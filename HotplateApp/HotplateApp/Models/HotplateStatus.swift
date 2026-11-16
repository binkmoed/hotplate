import Foundation

/// Hotplate controller state machine.
enum HotplateState: String, Codable, Sendable {
    case idle = "IDLE"
    case running = "RUNNING"
    case paused = "PAUSED"
}

/// PID statistics pushed inside each `/status` frame and returned by `GET /api/stats`.
struct PIDStats: Codable, Equatable, Sendable {
    var time: Double?
    var timeDelta: Double?
    var setpoint: Double?
    var ispoint: Double?
    var err: Double?
    var errDelta: Double?
    var p: Double?
    var i: Double?
    var d: Double?
    var kp: Double?
    var ki: Double?
    var kd: Double?
    var pid: Double?
    var out: Double?            // normalised 0..1 SSR fraction
}

/// One sample on the live temperature chart.
struct ChartSample: Identifiable, Hashable, Sendable {
    let id = UUID()
    let runtime: Double        // seconds since profile start
    let temperature: Double
    let target: Double
}

/// Live hotplate status. Mirrors `Oven.get_state()`.
struct HotplateStatus: Codable, Equatable, Sendable {
    var cost: Double?
    var runtime: Double?
    var temperature: Double?
    var target: Double?
    var state: HotplateState?
    var heat: Double?           // 0.0 off / 1.0 on
    var heatRate: Double?
    var totaltime: Double?
    var kwhRate: Double?
    var currencyType: String?
    var profile: String?
    var pidstats: PIDStats?
    var catchingUp: Bool?

    enum CodingKeys: String, CodingKey {
        case cost, runtime, temperature, target, state, heat
        case heatRate = "heat_rate"
        case totaltime
        case kwhRate = "kwh_rate"
        case currencyType = "currency_type"
        case profile
        case pidstats
        case catchingUp = "catching_up"
    }
}
