import SwiftUI
import Charts

/// Live temperature chart overlaying two series:
///   • the full profile schedule (solid grey "plan") spanning 0…total,
///   • the actual measured temperature (thick orange) drawn over it as the firing runs.
/// Axes are scaled to the chosen profile so the whole planned curve is always in view.
struct TemperatureChart: View {
    var history: [ChartSample]
    var total: Double?                          // profile duration in seconds
    var schedule: [Profile.Point]?              // active profile's [time, temp] points

    var body: some View {
        Chart {
            // Full projected firing schedule (whole profile, solid grey "plan").
            if let schedule {
                ForEach(schedule, id: \.time) { p in
                    LineMark(
                        x: .value("Time", p.time / 60),
                        y: .value("Temp", p.temp),
                        series: .value("Series", "schedule")
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(Color.green.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }

            // Actual measured temperature (thick orange), drawn over the schedule as it runs.
            // Long firings produce thousands of samples; stride them so
            // Swift Charts stays responsive without losing the early data.
            ForEach(displayHistory) { sample in
                LineMark(
                    x: .value("Time", sample.runtime / 60),
                    y: .value("Temp", sample.temperature),
                    series: .value("Series", "actual")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(Color.orange)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }

            // End-time label under the last schedule point.
            if let schedule, let lastPoint = schedule.last {
                PointMark(
                    x: .value("Time", lastPoint.time / 60),
                    y: .value("Temp", lastPoint.temp)
                )
                .foregroundStyle(.clear)
                .annotation(position: .bottom, spacing: 2) {
                    Text(formatEndtime(lastPoint.time))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                // Nudge left so the label doesn't run off the right edge.
                .offset(x: -28)
            }
        }
        .chartXAxis {
            AxisMarks(values: [0.0, xUpper]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(formatHours(v)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(stride(from: 0.0, through: yUpper, by: yStride))) { v in
                AxisGridLine()
                if let t = v.as(Double.self) {
                    AxisValueLabel { Text("\(Int(t))°") }
                }
            }
        }
        .chartYScale(domain: 0...yUpper)
        .chartXScale(domain: 0...xUpper)
        .chartLegend(.hidden)
    }

    /// Downsampled view of `history` for drawing (~≤1,500 points), keeping
    /// first and last samples so the curve always reaches the present.
    private var displayHistory: [ChartSample] {
        let maxPoints = 1500
        guard history.count > maxPoints else { return history }
        let stride = Double(history.count) / Double(maxPoints)
        var result: [ChartSample] = []
        result.reserveCapacity(maxPoints + 1)
        var next = 0.0
        while Int(next) < history.count {
            result.append(history[Int(next)])
            next += stride
        }
        if let last = history.last, result.last != last { result.append(last) }
        return result
    }

    /// X-axis upper bound: profile duration + 30 minutes of padding, minimum 1.
    private var xUpper: Double {
        let endMinutes = (total ?? schedule?.last?.time ?? history.last?.runtime ?? 0) / 60
        return Swift.max(1, endMinutes + 30)
    }

    /// Y-axis upper bound: highest of schedule / measured temperature + 10%
    /// headroom, floored at 100° so tiny profiles still get a sensible axis.
    private var yUpper: Double {
        let scheduleMax = schedule?.map(\.temp).max() ?? 0
        let actualMax = history.map(\.temperature).max() ?? 0
        return Swift.max(100, Double(Int(Swift.max(scheduleMax, actualMax) * 1.1)))
    }

    /// A "nice" stride that yields roughly 4–8 labelled gridlines.
    private var yStride: Double {
        let target = yUpper / 6
        for step in [10.0, 25.0, 50.0, 100.0, 200.0, 250.0, 500.0] {
            if step >= target { return step }
        }
        return 500
    }

    private func formatHours(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }

    /// Format the profile end-time (seconds) as "Xh Ym".
    private func formatEndtime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
