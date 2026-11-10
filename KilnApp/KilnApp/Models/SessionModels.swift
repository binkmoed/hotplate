import Foundation

/// Summary of a recorded firing session, returned by `GET /api/sessions`.
struct SessionSummary: Codable, Identifiable, Sendable, Equatable, Hashable {
    var id: String
    var started: Double?
    var profile: Profile?
    var peakTemperature: Double?
    var runtime: Double?
    var cost: Double?
    var outcome: String?

    enum CodingKeys: String, CodingKey {
        case id, started, profile
        case peakTemperature = "peak_temperature"
        case runtime, cost, outcome
    }
}

/// A discrete event line inside a session log.
struct SessionEvent: Codable, Sendable, Equatable {
    var name: String
    var detail: String?
    var time: Double?
}

/// One parsed firing session (`GET /api/sessions/<id>` — JSON-lines).
struct SessionLog: Sendable, Equatable {
    var id: String
    var started: Double?
    var profile: Profile?
    var outcome: String?
    var samples: [KilnStatus]
    var events: [SessionEvent]
}

enum SessionLogParser {
    /// Parse the newline-delimited JSON returned by the server.
    static func parse(_ text: String, id: String) -> SessionLog {
        let decoder = JSONDecoder()
        var log = SessionLog(id: id, started: nil, profile: nil,
                             outcome: nil, samples: [], events: [])
        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            switch type {
            case "meta":
                log.started = obj["started"] as? Double
                if let pdict = obj["profile"] as? [String: Any],
                   let pdata = try? JSONSerialization.data(withJSONObject: pdict),
                   let profile = try? decoder.decode(Profile.self, from: pdata) {
                    log.profile = profile
                }
            case "sample":
                if var s = try? decoder.decode(KilnStatus.self, from: data) {
                    s.profile = s.profile ?? log.profile?.name
                    log.samples.append(s)
                }
            case "event":
                if let e = try? decoder.decode(SessionEvent.self, from: data) {
                    log.events.append(e)
                }
            case "end":
                log.outcome = obj["outcome"] as? String
            default:
                break
            }
        }
        return log
    }
}

extension SessionLog {
    /// Chart history reconstructed from the session samples.
    var chartHistory: [ChartSample] {
        samples.compactMap { s in
            guard let t = s.runtime, let temp = s.temperature else { return nil }
            return ChartSample(runtime: t, temperature: temp, target: s.target ?? 0)
        }
    }
}
