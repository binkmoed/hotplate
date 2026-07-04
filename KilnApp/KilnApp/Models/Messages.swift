import Foundation

/// The first frame on `/status`: the active profile plus a down-sampled history log.
struct BacklogMessage: Codable, Sendable {
    var type: String
    var profile: Profile?
    var log: [KilnStatus]?
}

/// Subset of config returned by the `/config` WebSocket and used for display formatting.
struct DisplayConfig: Codable, Equatable, Sendable {
    var tempScale: String          // "c" or "f"
    var timeScaleSlope: String     // "s", "m", "h"
    var timeScaleProfile: String   // "s", "m", "h"
    var kwhRate: Double
    var currencyType: String
    var kwElements: Double

    enum CodingKeys: String, CodingKey {
        case tempScale = "temp_scale"
        case timeScaleSlope = "time_scale_slope"
        case timeScaleProfile = "time_scale_profile"
        case kwhRate = "kwh_rate"
        case currencyType = "currency_type"
        case kwElements = "kw_elements"
    }
}

extension DisplayConfig {
    static let defaultConfig = DisplayConfig(
        tempScale: "c",
        timeScaleSlope: "h",
        timeScaleProfile: "m",
        kwhRate: 0.25,
        currencyType: "€",
        kwElements: 7.1
    )
}

/// The full config document returned by `GET /api/config`. Only the sections the app edits
/// are modelled in detail; the rest pass through as `[String: AnyCodable]`.
struct FullConfig: Codable, Equatable, Sendable {
    var hardware: [String: AnyCodable]?
    var pid: [String: AnyCodable]?
    var safety: [String: AnyCodable]?
    var display: [String: AnyCodable]?
    var restart: [String: AnyCodable]?
    var alerting: [String: AnyCodable]?
    var server: [String: AnyCodable]?
}

/// Minimal lossless JSON value wrapper for arbitrary config dictionaries.
indirect enum AnyCodable: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([AnyCodable].self) { self = .array(v); return }
        if let v = try? c.decode([String: AnyCodable].self) { self = .object(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:         try c.encodeNil()
        case .bool(let v):  try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var numberValue: Double? { if case .number(let v) = self { v } else { nil } }
    var stringValue: String? { if case .string(let v) = self { v } else { nil } }
    var boolValue: Bool? { if case .bool(let v) = self { v } else { nil } }
}
