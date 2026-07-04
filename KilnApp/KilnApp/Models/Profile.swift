import Foundation

/// A firing profile. Wire format is a sorted list of `[time_seconds, temperature]` points.
/// The controller linearly interpolates between consecutive points.
struct Profile: Codable, Identifiable, Hashable, Sendable {
    var type: String = "profile"
    var name: String
    var tempUnits: String          // "c" or "f"
    var data: [Point]              // sorted ascending by time

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case type, name
        case tempUnits = "temp_units"
        case data
    }

    /// A `[time, temperature]` pair received as a JSON array of two numbers.
    struct Point: Codable, Hashable, Sendable {
        var time: Double
        var temp: Double

        init(time: Double, temp: Double) {
            self.time = time
            self.temp = temp
        }

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            // Tolerate either [Double, Double] or nested forms; we expect two numbers.
            self.time = try c.decode(Double.self)
            self.temp = try c.decode(Double.self)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(time)
            try c.encode(temp)
        }

        /// Convenience for SwiftUI charts.
        var asTuple: (time: Double, temp: Double) { (time, temp) }
    }

    init(name: String, tempUnits: String = "c", data: [Point] = []) {
        self.name = name
        self.tempUnits = tempUnits
        self.data = data.sorted { $0.time < $1.time }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? "profile"
        self.name = try c.decode(String.self, forKey: .name)
        self.tempUnits = try c.decodeIfPresent(String.self, forKey: .tempUnits) ?? "c"
        self.data = (try c.decodeIfPresent([Point].self, forKey: .data) ?? [])
            .sorted { $0.time < $1.time }
    }

    /// Total profile duration in seconds (time of the last point).
    var totalDuration: Double { data.last?.time ?? 0 }

    /// Highest temperature reached.
    var peakTemp: Double { data.map(\.temp).max() ?? 0 }

    /// Linearly interpolate the target temperature at the given time.
    /// Matches server `Profile.get_target_temperature(time)`.
    func target(at time: Double) -> Double {
        guard let first = data.first else { return 0 }
        if time <= first.time { return first.temp }
        guard let last = data.last, time < last.time else {
            return data.last?.temp ?? 0
        }
        for i in 1..<data.count {
            let a = data[i - 1]
            let b = data[i]
            if time >= a.time && time <= b.time {
                let span = b.time - a.time
                if span <= 0 { return b.temp }
                let f = (time - a.time) / span
                return a.temp + (b.temp - a.temp) * f
            }
        }
        return data.last?.temp ?? 0
    }
}

extension Profile {
    /// A short starter profile used as the default in the editor for a new profile.
    static var blank: Profile {
        Profile(name: "New Profile", tempUnits: "c", data: [
            .init(time: 0, temp: 25),
            .init(time: 3600, temp: 200),
            .init(time: 7200, temp: 600),
            .init(time: 10800, temp: 25),
        ])
    }
}
