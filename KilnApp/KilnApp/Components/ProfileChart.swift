import SwiftUI
import Charts
import UIKit

/// Interactive profile editor chart. Drag any point to set its time/temperature;
/// long-press a point to delete it (with haptic feedback).
struct ProfileChart: View {
    @Binding var points: [Profile.Point]
    var tempUnits: String

    @State private var draggingIndex: Int?
    @State private var lastTouch: CGPoint?
    @State private var deletionFlash: Int?

    private let yMaxTemp: Double = 1250

    /// Domain upper bound: one hour past the last point's time (minimum 1 to avoid an empty range).
    private var xMaxMinutes: Double {
        max(1, (points.last?.time ?? 0) / 60 + 60)
    }

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.element) { idx, point in
                LineMark(
                    x: .value("Time", point.time / 60),
                    y: .value("Temp", point.temp)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(Color.orange)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            ForEach(Array(points.enumerated()), id: \.element) { idx, point in
                PointMark(
                    x: .value("Time", point.time / 60),
                    y: .value("Temp", point.temp)
                )
                .foregroundStyle(pointColor(idx))
                .symbolSize(idx == draggingIndex ? 200 : 130)
            }
        }
        .chartXScale(domain: 0...xMaxMinutes)
        .chartYScale(domain: 0...yMaxTemp)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { v in
                AxisGridLine()
                AxisValueLabel { if let m = v.as(Double.self) { Text(formatHours(m)) } }
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
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(combinedGesture(proxy: proxy, geo: geo))
            }
        }
    }

    private func pointColor(_ idx: Int) -> Color {
        if draggingIndex == idx { return .red }
        if deletionFlash == idx { return .red.opacity(0.4) }
        return .orange
    }

    // MARK: Gesture

    private func combinedGesture(proxy: ChartProxy, geo: GeometryProxy) -> some Gesture {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                lastTouch = value.location
                guard let plotFrame = proxy.plotFrame else { return }
                let origin = geo[plotFrame].origin
                guard let mins = proxy.value(atX: value.location.x - origin.x, as: Double.self),
                      let temp = proxy.value(atY: value.location.y - origin.y, as: Double.self) else { return }
                if draggingIndex == nil {
                    draggingIndex = nearestIndex(toMinutes: mins, temp: temp)
                }
                guard let i = draggingIndex, points.indices.contains(i) else { return }
                var newTime = max(0, mins * 60)
                if i == 0 { newTime = min(newTime, points.count > 1 ? points[1].time - 60 : newTime) }
                if i == points.count - 1 && i > 0 {
                    newTime = max(newTime, points[i - 1].time + 60)
                }
                if i > 0 { newTime = max(newTime, points[i - 1].time + 30) }
                if i < points.count - 1 { newTime = min(newTime, points[i + 1].time - 30) }
                points[i].time = newTime
                points[i].temp = min(max(0, temp), yMaxTemp)
            }
            .onEnded { _ in draggingIndex = nil }

        let longPress = LongPressGesture(minimumDuration: 0.45, maximumDistance: 18)
            .onEnded { _ in
                handleLongPress(proxy: proxy, geo: geo)
            }

        return drag.simultaneously(with: longPress)
    }

    private func handleLongPress(proxy: ChartProxy, geo: GeometryProxy) {
        guard let touch = lastTouch,
              let plotFrame = proxy.plotFrame,
              let mins = proxy.value(atX: touch.x - geo[plotFrame].origin.x, as: Double.self),
              let temp = proxy.value(atY: touch.y - geo[plotFrame].origin.y, as: Double.self) else { return }
        let i = nearestIndex(toMinutes: mins, temp: temp)
        guard points.indices.contains(i) else { return }
        // Don't delete below two points.
        guard points.count > 2 else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            deletionFlash = i
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { deletionFlash = nil }
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        deletionFlash = i
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if points.indices.contains(i) {
                points.remove(at: i)
            }
            deletionFlash = nil
        }
    }

    // MARK: Helpers

    private func nearestIndex(toMinutes m: Double, temp t: Double) -> Int {
        var best = 0
        var bestDist = Double.infinity
        for (i, p) in points.enumerated() {
            let dx = (p.time / 60 - m)
            let dy = (p.temp - t) / 50      // scale temp for fair distance
            let d = dx * dx + dy * dy
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }

    private func formatHours(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }
}

/// Row-based fallback editor shown below the chart for precise numeric edits.
/// Time is entered in whole minutes and temperature in whole degrees.
struct ProfilePointList: View {
    @Binding var points: [Profile.Point]

    var body: some View {
        ForEach(Array(points.enumerated()), id: \.offset) { idx, point in
            HStack(spacing: 16) {
                fieldColumn(
                    title: "TIME",
                    value: Binding(
                        get: { Int((point.time / 60).rounded()) },
                        set: { points[idx].time = max(0, Double($0) * 60) }
                    ),
                    unit: "min",
                    range: 0...1440
                )

                Divider().frame(height: 36)

                fieldColumn(
                    title: "TEMP",
                    value: Binding(
                        get: { Int(point.temp.rounded()) },
                        set: { points[idx].temp = max(0, Double($0)) }
                    ),
                    unit: "°",
                    range: 0...1500
                )
            }
            .swipeActions {
                Button(role: .destructive) {
                    if points.count > 2 { points.remove(at: idx) }
                } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .onMove { from, to in
            points.move(fromOffsets: from, toOffset: to)
            points.sort { $0.time < $1.time }
        }
        Button {
            let last = points.last?.time ?? 0
            points.append(.init(time: last + 3600, temp: points.last?.temp ?? 200))
            points.sort { $0.time < $1.time }
        } label: {
            Label("Add Point", systemImage: "plus")
        }
    }

    /// One labelled numeric entry field with a unit suffix and clamping on commit.
    private func fieldColumn(title: String, value: Binding<Int>, unit: String, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("", value: value, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .multilineTextAlignment(.leading)
                    .onSubmit {
                        if value.wrappedValue < range.lowerBound { value.wrappedValue = range.lowerBound }
                        if value.wrappedValue > range.upperBound { value.wrappedValue = range.upperBound }
                    }
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
