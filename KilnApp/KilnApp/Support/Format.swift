import Foundation

/// Pure formatting helpers for temperatures, durations, costs and slopes.
enum Format {
    static func temp(_ value: Double?, units: String = "c") -> String {
        guard let value else { return "—" }
        let symbol = units.lowercased() == "f" ? "°F" : "°C"
        return "\(Int(value.rounded()))\(symbol)"
    }

    /// Duration from seconds using the given scale.
    static func duration(_ seconds: Double?, scale: String = "m") -> String {
        guard let seconds else { return "—" }
        switch scale.lowercased() {
        case "s": return "\(Int(seconds))s"
        case "h":
            let h = seconds / 3600
            return String(format: "%.\(abs(h) < 10 ? 1 : 0)f h", h)
        default:
            let m = seconds / 60
            return String(format: "%.\(abs(m) < 10 ? 1 : 0)f m", m)
        }
    }

    /// A `h:mm:ss` style clock for runtime.
    static func clock(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "0:00" }
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    static func slope(_ degPerHour: Double?) -> String {
        guard let degPerHour, degPerHour != 0 else { return "0°" }
        return String(format: "%+.0f°", degPerHour)
    }

    static func cost(_ value: Double?, currency: String, rate: Double?) -> String {
        guard let value else { return String(format: "%@0.00", currency) }
        return String(format: "%@%.2f", currency, value)
    }

    /// Progress 0..1 through the profile based on runtime / totaltime.
    static func progress(runtime: Double?, total: Double?) -> Double {
        guard let runtime, let total, total > 0 else { return 0 }
        return min(max(runtime / total, 0), 1)
    }
}
