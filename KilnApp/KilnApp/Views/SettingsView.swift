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
    @State private var controlWindow: Double = 50
    @State private var dutyCycle: Double = 3
    @State private var sensorType: String = "MAX31856"
    @State private var thermocouple: String = "K"
    @State private var feedback: String?

    /// Server-side (saved) gains, updated whenever fresh config arrives.
    @State private var savedKp: Double = 3
    @State private var savedKi: Double = 75
    @State private var savedKd: Double = 12
    @State private var savedControlWindow: Double = 50
    @State private var savedDutyCycle: Double = 3

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
                settingsGuide
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
                restartRow
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
            Text("Restart applies pending hardware/config changes. Needs the sudoers rule from the deploy README on the Pi.")
        }
    }

    private var restartRow: some View {
        HStack {
            switch client.restartState {
            case .restarting:
                Label("Restarting…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
            case .running:
                Label("Running", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let msg):
                Label(msg, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            case .idle:
                Label(client.isConnected ? "Running" : "Stopped",
                      systemImage: client.isConnected ? "checkmark.circle.fill" : "stop.circle.fill")
                    .foregroundStyle(client.isConnected ? .green : .red)
            }
            Spacer()
            Button("Restart Server", systemImage: "arrow.triangle.2.circlepath") {
                Task { await client.restartServer() }
            }
            .disabled(client.restartState == .restarting || client.currentState == .running)
        }
    }

    /// Server-side (saved) display values, updated whenever fresh config arrives.
    @State private var savedKwhRate: Double = 0.25
    @State private var savedCurrency: String = "€"
    @State private var savedTempScale: String = "c"

    private var displaySection: some View {
        Section {
            if hasUnsavedDisplay {
                Label("Unsaved changes", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Label("Settings applied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
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
            Button {
                Task { await applyDisplay() }
            } label: {
                Label(
                    hasUnsavedDisplay ? "Apply Display Settings" : "Display Settings Applied",
                    systemImage: hasUnsavedDisplay ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                )
            }
            .foregroundStyle(hasUnsavedDisplay ? .red : .green)
        } header: {
            Text("Display")
        } footer: {
            Text("Applied immediately. Currency and units affect how values are shown on this device and the controller's UI.")
        }
    }

    /// True when the display controls no longer match the values on the server.
    private var hasUnsavedDisplay: Bool {
        kwhRate != savedKwhRate || currency != savedCurrency || tempScale != savedTempScale
    }

    /// True when the sliders no longer match the gains saved on the server.
    private var hasUnsavedPIDGains: Bool {
        kp != savedKp || ki != savedKi || kd != savedKd
            || controlWindow != savedControlWindow || dutyCycle != savedDutyCycle
    }

    private var pidSection: some View {
        Section {
            if hasUnsavedPIDGains {
                Label("Unsaved changes", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Label("Gains applied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            sliderRow(title: "Kp", value: $kp, range: 0...20, step: 0.1, format: "%.1f")
            sliderRow(title: "Ki", value: $ki, range: 0...300, step: 1, format: "%.0f")
            sliderRow(title: "Kd", value: $kd, range: 0...100, step: 0.5, format: "%.1f")
            sliderRow(title: "Ctl win", value: $controlWindow, range: 0...200, step: 5, format: "%.0f°")
            sliderRow(title: "Duty", value: $dutyCycle, range: 2...10, step: 0.5, format: "%.1fs")
            Button {
                Task { await applyPID() }
            } label: {
                Label(
                    hasUnsavedPIDGains ? "Apply PID Gains" : "PID Gains Applied",
                    systemImage: hasUnsavedPIDGains ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                )
            }
            .foregroundStyle(hasUnsavedPIDGains ? .red : .green)
        } header: {
            Text("PID Tuning")
        } footer: {
            Text("All values hot-reload. Control window = degrees from target within which the schedule time runs free; duty cycle = length of one SSR on/off cycle. Output is proportional: PID output 0–100 maps linearly to SSR duty 0–100%. Very short duty cycles wear the SSR and relay.")
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
        } footer: {
            Text("See “Settings Guide” above for what each setting does.")
        }
    }

    /// Plain-language explanation of every setting and how it affects the kiln.
    private var settingsGuide: some View {
        Section {
            guideRow("Kp", "Proportional gain. How strongly the controller reacts to the gap between actual and target temperature. Too low: sluggish, undershoots. Too high: temperature oscillates around the target.")
            guideRow("Ki", "Integral gain. Corrects a persistent small offset (e.g. always 5° below target) by accumulating past error. Too high: overshoot after long ramps.")
            guideRow("Kd", "Derivative gain. Dampens the reaction when temperature is moving fast, reducing overshoot at the top of a ramp. Mostly useful on fast, light loads.")
            guideRow("Control window", "Degrees around the target within which the schedule clock runs free even if the kiln lags behind. Bigger = firing stays on schedule despite slow heating; smaller = schedule waits for the kiln to actually reach temperature.")
            guideRow("Duty cycle", "Length of one SSR on/off cycle. The PID output decides what fraction of each cycle the elements are on. Short = finer control but more relay switching; long = coarser but gentler on hardware.")
            guideRow("Currency · kWh rate", "Used only to display an estimated electricity cost of each firing. No effect on control.")
            guideRow("Element power", "Kiln's power draw in kW. Feeds the cost estimate; no effect on control.")
            guideRow("Sensor · thermocouple", "Which sensor board and thermocouple type the Pi reads. Must match your hardware or temperatures will be wrong. Changing it requires a server restart.")
            guideRow("Restart Server", "Applies pending config changes that need a fresh start (like the sensor choice). Refuses to run while a firing is active, so a firing is never interrupted.")
            guideRow("History · PID tile", "Each recorded firing stores the PID gains in use at every moment. The tile shows the gains (kp/ki/kd); “varied” means you tuned mid-firing — handy for comparing curves.")
        } header: {
            Text("Settings Guide")
        } footer: {
            Text("PID gains, control window and duty cycle all hot-reload: they apply from the next duty cycle, even mid-firing, without restarting.")
        }
    }

    private func guideRow(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// True when the sensor board / thermocouple pickers no longer match the
    /// values saved on the server.
    private var hasUnsavedHardware: Bool {
        guard let hw = client.fullConfig?.hardware else { return false }
        let serverSensor = hw["sensor_type"]?.stringValue ?? "MAX31856"
        let key = serverSensor == "MAX31855" ? "thermocouple_type_max31855" : "thermocouple_type_max31856"
        let serverTC = hw[key]?.stringValue ?? "K"
        return sensorType != serverSensor || thermocouple != serverTC
    }

    private var hardwareSection: some View {
        Section {
            if hasUnsavedHardware {
                Label("Unsaved changes", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else {
                Label("Settings applied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
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

            Button {
                Task { await applyHardware() }
            } label: {
                Label(
                    hasUnsavedHardware ? "Apply Hardware Settings" : "Hardware Settings Applied",
                    systemImage: hasUnsavedHardware ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                )
            }
            .foregroundStyle(hasUnsavedHardware ? .red : .green)
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
        savedKwhRate = kwhRate
        savedCurrency = currency
        savedTempScale = tempScale
        if let pid = client.fullConfig?.pid {
            kp = pid["kp"]?.numberValue ?? 3
            ki = pid["ki"]?.numberValue ?? 75
            kd = pid["kd"]?.numberValue ?? 12
            controlWindow = pid["control_window"]?.numberValue ?? 50
            dutyCycle = pid["duty_cycle"]?.numberValue ?? 3
            savedKp = kp
            savedKi = ki
            savedKd = kd
            savedControlWindow = controlWindow
            savedDutyCycle = dutyCycle
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
        if ok {
            savedKwhRate = kwhRate
            savedCurrency = currency
            savedTempScale = tempScale
        }
    }

    private func applyPID() async {
        let (ok, msg) = await client.updateConfig([
            "pid.kp": kp, "pid.ki": ki, "pid.kd": kd,
            "pid.control_window": controlWindow, "pid.duty_cycle": dutyCycle,
        ])
        feedback = ok ? "Saved · \(msg)" : msg
        if ok {
            savedKp = kp
            savedKi = ki
            savedKd = kd
            savedControlWindow = controlWindow
            savedDutyCycle = dutyCycle
        }
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
