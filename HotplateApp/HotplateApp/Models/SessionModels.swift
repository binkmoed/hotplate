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
    var samples: [HotplateStatus]
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
                if var s = try? decoder.decode(HotplateStatus.self, from: data) {
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
    /// Chart history reconstructed from the session samples. Runtime is
    /// expected to be monotonically increasing; any sample that goes back
    /// (e.g. a stray post-stop IDLE sample with runtime 0 in old logs) is
    /// dropped so the line doesn't snap back to the origin.
    var chartHistory: [ChartSample] {
        var result: [ChartSample] = []
        var lastRuntime = -1.0
        for s in samples {
            guard let t = s.runtime, let temp = s.temperature, t >= lastRuntime else { continue }
            lastRuntime = t
            result.append(ChartSample(runtime: t, temperature: temp, target: s.target ?? 0))
        }
        return result
    }
}
