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
                    .foregroundStyle(Color.gray.opacity(1.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }

            // Actual measured temperature (thick orange), drawn over the schedule as it runs.
            ForEach(history) { sample in
                LineMark(
                    x: .value("Time", sample.runtime / 60),
                    y: .value("Temp", sample.temperature),
                    series: .value("Series", "actual")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(Color.orange)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
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
            AxisMarks(position: .leading, values: .stride(by: 50)) { v in
                AxisGridLine()
                if let t = v.as(Double.self), Int(t.rounded()) % 250 == 0 {
                    AxisValueLabel { Text("\(Int(t))°") }
                }
            }
        }
        .chartYScale(domain: 0...1250)
        .chartXScale(domain: 0...xUpper)
        .chartLegend(.hidden)
        .overlay(alignment: .topTrailing) { legend.padding(8) }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Capsule().fill(Color.orange).frame(width: 14, height: 3)
                Text("Actual").font(.caption2)
            }
            HStack(spacing: 4) {
                Capsule().fill(Color.gray.opacity(0.5)).frame(width: 14, height: 3)
                Text("Schedule").font(.caption2)
            }
        }
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    /// X-axis upper bound: profile duration + 30 minutes of padding, minimum 1.
    private var xUpper: Double {
        let endMinutes = (total ?? schedule?.last?.time ?? history.last?.runtime ?? 0) / 60
        return Swift.max(1, endMinutes + 30)
    }

    private func formatHours(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }
}
