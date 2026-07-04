import SwiftUI
import UIKit

/// Display settings + hot-reload PID tuning, plus server connection management.
struct SettingsView: View {
    @Environment(KilnClient.self) private var client

    @State private var kwhRate: Double = 0.25
    @State private var currency: String = "€"
    @State private var tempScale: String = "c"
    @State private var kp: Double = 3
    @State private var ki: Double = 75
    @State private var kd: Double = 12
    @State private var sensorType: String = "MAX31856"
    @State private var thermocouple: String = "K"
    @State private var feedback: String?

    /// Thermocouple types supported by each sensor board, per the controller docs.
    private let supportedTC: [String: [String]] = [
        "MAX31855": ["K"],
        "MAX31856": ["B", "E", "J", "K", "N", "R", "S", "T"],
    ]

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                displaySection
                pidSection
                hardwareSection
                aboutSection
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
            }
            .onAppear { syncFromConfig() }
            .onChange(of: client.displayConfig) { _, _ in syncFromConfig() }
            .onChange(of: client.fullConfig) { _, _ in syncFromConfig() }
        }
    }

    // MARK: Sections

    private var connectionSection: some View {
        Section {
            if let conn = client.connection {
                LabeledContent("Host", value: conn.host)
                LabeledContent("Port", value: "\(conn.port)")
                Button("Reconnect", systemImage: "arrow.clockwise") {
                    Task { await client.reconnect() }
                }
                Button("Disconnect", role: .destructive) {
                    client.forgetConnection()
                }
            }
        } header: {
            Text("Server")
        } footer: {
            Text("Connected to your kiln controller over the local network.")
        }
    }

    private var displaySection: some View {
        Section {
            HStack {
                Stepper(value: $kwhRate, in: 0...1, step: 0.01) {
                    LabeledContent("kWh Rate", value: String(format: "%.2f", kwhRate))
                }
            }
            HStack {
                TextField("Currency", text: $currency)
                    .frame(width: 60)
                Spacer()
                Picker("Units", selection: $tempScale) {
                    Text("°C").tag("c")
                    Text("°F").tag("f")
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            Button("Apply Display Settings") {
                Task { await applyDisplay() }
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Applied immediately. Currency and units affect how values are shown on this device and the controller's UI.")
        }
    }

    private var pidSection: some View {
        Section {
            sliderRow(title: "Kp", value: $kp, range: 0...20, step: 0.1, format: "%.1f")
            sliderRow(title: "Ki", value: $ki, range: 0...300, step: 1, format: "%.0f")
            sliderRow(title: "Kd", value: $kd, range: 0...100, step: 0.5, format: "%.1f")
            Button("Apply PID Gains") {
                Task { await applyPID() }
            }
            if let full = client.fullConfig, let pid = full.pid {
                let window = pid["control_window"]?.numberValue ?? 50
                LabeledContent("Control window", value: "\(Int(window))°")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("PID Tuning")
        } footer: {
            Text("Kp/Ki/Kd hot-reload. Control window, duty cycle and SSR timing require a server restart.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("App", value: "Kiln 1.0")
            LabeledContent("Server", value: serverVersionText)
            if let feedback {
                Label(feedback, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        } header: {
            Text("About")
        }
    }

    private var hardwareSection: some View {
        Section {
            Picker("Sensor Board", selection: $sensorType) {
                ForEach(supportedTC.keys.sorted(), id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: sensorType) { _, new in
                // If the currently-selected thermocouple isn't supported by the new board,
                // snap it down to a valid value (K for MAX31855).
                if !supportedTC[new, default: []].contains(thermocouple) {
                    thermocouple = supportedTC[new, default: ["K"]].first ?? "K"
                }
            }

            Picker("Thermocouple Type", selection: $thermocouple) {
                ForEach(supportedTC[sensorType, default: ["K"]], id: \.self) {
                    Text("Type \($0)").tag($0)
                }
            }

            Button("Apply Hardware Settings") {
                Task { await applyHardware() }
            }
        } header: {
            Text("Hardware")
        } footer: {
            Text("Requires a server restart to take effect. The kiln will not pick up the new sensor until the service restarts.")
        }
    }

    // MARK: Helpers

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        HStack {
            Text(title).frame(width: 40, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(String(format: format, value.wrappedValue))
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }

    private var serverVersionText: String {
        guard let hw = client.fullConfig?.hardware,
              let sensor = hw["sensor_type"]?.stringValue,
              let tc = hw["thermocouple_type_max31856"]?.stringValue else {
            return "—"
        }
        return "\(sensor) · TC \(tc)"
    }

    private func syncFromConfig() {
        // Display values: prefer fullConfig (fresh from REST after updates);
        // fall back to displayConfig (pushed by the /config WebSocket).
        if let display = client.fullConfig?.display {
            kwhRate = display["kwh_rate"]?.numberValue ?? client.displayConfig.kwhRate
            currency = display["currency_type"]?.stringValue ?? client.displayConfig.currencyType
            tempScale = display["temp_scale"]?.stringValue ?? client.displayConfig.tempScale
        } else {
            let cfg = client.displayConfig
            kwhRate = cfg.kwhRate
            currency = cfg.currencyType
            tempScale = cfg.tempScale
        }
        if let pid = client.fullConfig?.pid {
            kp = pid["kp"]?.numberValue ?? 3
            ki = pid["ki"]?.numberValue ?? 75
            kd = pid["kd"]?.numberValue ?? 12
        }
        if let hw = client.fullConfig?.hardware {
            sensorType = hw["sensor_type"]?.stringValue ?? "MAX31856"
            let key = sensorType == "MAX31855" ? "thermocouple_type_max31855" : "thermocouple_type_max31856"
            thermocouple = hw[key]?.stringValue ?? "K"
        }
    }

    private func applyDisplay() async {
        let (ok, msg) = await client.updateConfig([
            "display.kwh_rate": kwhRate,
            "display.currency_type": currency,
            "display.temp_scale": tempScale,
        ])
        feedback = ok ? "Saved · \(msg)" : msg
    }

    private func applyPID() async {
        let (ok, msg) = await client.updateConfig([
            "pid.kp": kp, "pid.ki": ki, "pid.kd": kd,
        ])
        feedback = ok ? "Saved · \(msg)" : msg
    }

    private func applyHardware() async {
        let tcKey = sensorType == "MAX31855"
            ? "hardware.thermocouple_type_max31855"
            : "hardware.thermocouple_type_max31856"
        let (ok, msg) = await client.updateConfig([
            "hardware.sensor_type": sensorType,
            tcKey: thermocouple,
        ])
        feedback = ok ? "Saved · \(msg)" : msg
    }
}
