# Kiln Controller Implementation Plan
## Complete iOS Swift Frontend + Python Backend on Raspberry Pi 3 B

---

## Executive Summary

This plan outlines the complete implementation of a kiln control system consisting of:
- **iOS Swift Frontend**: SwiftUI-based mobile application for monitoring and controlling a kiln
- **Python Backend**: Bottle + gevent server running on Raspberry Pi 3 B for hardware control
- **Communication**: REST API + 4 independent WebSocket connections
- **Hardware**: Raspberry Pi 3 B, MAX31855/56 thermocouple reader, SSR relay, safety relay with lid switch

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Python Backend Implementation](#2-python-backend-implementation)
3. [iOS Swift Frontend Implementation](#3-ios-swift-frontend-implementation)
4. [Hardware Integration](#4-hardware-integration)
5. [Deployment & Installation](#5-deployment--installation)
6. [Testing Strategy](#6-testing-strategy)
7. [Timeline & Milestones](#7-timeline--milestones)
8. [Risk Assessment](#8-risk-assessment)

---

## 1. Architecture Overview

### 1.1 System Components

```
┌─────────────────────────────────────────────────────────────┐
│                      iOS Swift App                           │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────┐ │
│  │  Dashboard  │  │  Programs   │  │      Settings        │ │
│  │   View      │  │    View     │  │       View           │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬───────────┘ │
│         │                │                     │             │
│  ┌──────▼────────────────▼─────────────────────▼───────────┐ │
│  │              WebSocketService (4 sockets)               │ │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │ │
│  │  │/status  │ │/control │ │/storage │ │/config  │        │ │
│  │  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘        │ │
│  └───────┼─────────────┼─────────────┼─────────────┼────────┘ │
│          │             │             │             │           │
└──────────┼─────────────┼─────────────┼─────────────┼───────────┘
           │             │             │             │
           └─────────────┴─────────────┴─────────────┘
                     HTTP/WS over LAN (port 8080)
           ┌─────────────┴─────────────┴─────────────┐
           │  Raspberry Pi 3 B - Python Backend      │
           │  ┌─────────────────────────────────────┐ │
           │  │    kiln-controller.py               │ │
           │  │  (Bottle + gevent server)           │ │
           │  └──────────┬──────────────────────────┘ │
           │  ┌──────────▼──────────────────────────┐ │
           │  │    Oven Core (lib/oven.py)          │ │
           │  │  - PID Controller                   │ │
           │  │  - Profile Interpolation            │ │
           │  │  - SSR Timing                       │ │
           │  │  - State Machine                    │ │
           │  └──────────┬──────────────────────────┘ │
           │  ┌──────────▼──────────────────────────┐ │
           │  │    OvenWatcher (lib/ovenWatcher.py) │ │
           │  │  - State Broadcaster                │ │
           │  │  - Backlog Management               │ │
           │  └──────────┬──────────────────────────┘ │
           │  ┌──────────▼──────────────────────────┐ │
           │  │    TempSensor (lib/tempSensor.py)   │ │
           │  │  - MAX31855/56 Reader               | |
           |  |  - When SSR is off (heating off )   │ │
           │  └──────────┬──────────────────────────┘ │
           │  ┌──────────▼──────────────────────────┐ │
           │  │    Hardware Interface               │ │
           │  │  - GPIO/SSR Control                 │ │
           │  │  - Safety Relay                     │ │
           │  │  - Lid Switch                       │ │
           │  └──────────┬──────────────────────────┘ │
           │  ┌──────────▼──────────────────────────┐ │
           │  │    Storage                          │ │
           │  │  - storage/profiles/*.json          │ │
           │  │  - state.json                       │ │
           │  └──────────┬──────────────────────────┘ │
           │  ┌──────────▼──────────────────────────┐ │
           │  │    Config (config.py)               │ │
           │  │  - PID Gains                        │ │
           │  │  - Hardware Settings                │ │
           │  │  - Display Settings                 │ │
           │  └─────────────────────────────────────┘ │
           └───────────────────────────────────────────┘
```

### 1.2 Communication Protocol

**REST API (POST /api, GET /api/stats):**
- Commands: run, pause, resume, stop, memo, stats
- Health checks
- Command acknowledgements

**4 Independent WebSocket Connections:**
1. `/status` - Live state push (every 3 seconds)
2. `/control` - Run/stop commands
3. `/storage` - Profile CRUD operations
4. `/config` - Controller configuration

**Note:** No multiplexing, no authentication by default, plain HTTP/WS

---

## 2. Python Backend Implementation

### 2.1 Core Components

#### 2.1.1 kiln-controller.py (Main Entry Point)

**Dependencies:**
```python
# requirements.txt
bottle==0.12.25
gevent==23.9.1
gevent-websocket==0.10.1
RPi.GPIO==0.7.1
spidev==3.5
```

**Key Functions:**
```python
def start_server():
    # Initialize global oven and ovenWatcher instances
    # Setup Bottle routes and WebSocket handlers
    # Run gevent WSGIServer on 0.0.0.0:8080
    pass

@route('/')
def redirect_to_ui():
    redirect('/picoreflow/index.html')

@post('/api')
def handle_api_command():
    # Parse JSON body with cmd field
    # Execute: run, pause, resume, stop, memo, stats
    # Return {"success": bool, "error": string|None}
    pass

@get('/api/stats')
def get_pid_stats():
    # Return current pidstats as JSON
    # Empty body when idle
    pass

# WebSocket Handlers
@get('/status', apply=[websocket])
def handle_status(ws):
    # Subscribe observer
    # Send backlog immediately
    # Push state every sensor_time_wait
    pass

@get('/control', apply=[websocket])
def handle_control(ws):
    # Receive RUN, STOP, SIMULATE commands
    # No acknowledgement (check /status for confirmation)
    pass

@get('/storage', apply=[websocket])
def handle_storage(ws):
    # Handle GET (list), PUT (save), DELETE operations
    # Support force flag for overwrites
    pass

@get('/config', apply=[websocket])
def handle_config(ws):
    # Send config object on each message received
    pass
```

#### 2.1.2 lib/oven.py (Oven Core)

**Class Structure:**
```python
class Oven(threading.Thread):
    def __init__(self, config):
        # Initialize PID controller
        # Setup GPIO pins
        # Load configuration
        pass

    def run_profile(self, profile, startat=0, allow_seek=True):
        # Start firing sequence
        # Set state to RUNNING
        pass

    def pause(self):
        # Set state to PAUSED
        # Hold current position
        pass

    def resume(self):
        # Set state to RUNNING
        pass

    def abort_run(self):
        # Stop firing
        # Reset to IDLE
        # Write state.json
        pass

    def get_state(self):
        # Return current state dict with:
        # - cost, runtime, temperature, target, state
        # - heat, heat_rate, totaltime, kwh_rate
        # - currency_type, profile, pidstats, catching_up
        pass

    def _control_loop(self):
        while True:
            # 1. update_cost()
            # 2. save_automatic_restart_state()
            # 3. kiln_must_catch_up()
            # 4. update_runtime()
            # 5. update_target_temp()
            # 6. heat_then_cool()
            # 7. reset_if_emergency()
            # 8. reset_if_schedule_ended()
            pass

class PID:
    def compute(self, setpoint, input):
        # Compute PID output
        # Return pidstats dict
        pass
```

#### 2.1.3 lib/ovenWatcher.py (State Broadcaster)

```python
class OvenWatcher(threading.Thread):
    def __init__(self, oven):
        # Maintain list of WebSocket observers
        # Build backlog from oven log
        pass

    def add_observer(self, ws):
        # Send backlog immediately
        # Add to observers list
        pass

    def remove_observer(self, ws):
        # Remove from observers
        pass

    def run(self):
        while True:
            # Poll oven.get_state() every sensor_time_wait
            # Push to all observers
            # Sleep sensor_time_wait
            pass

    def record(self, profile):
        # Reset backlog
        # Store profile for backlog
        pass
```

#### 2.1.4 lib/tempSensor.py (Temperature Reading)

```python
class TempSensor(threading.Thread):
    def __init__(self, config):
        # Setup SPI for MAX31855/56
        # Configure thermocouple type
        pass

    def read_temperature(self):
        # Read from MAX31855/56 via SPI
        # Return temperature in config temp_scale
        # Apply offset if configured
        pass

    def run(self):
        while True:
            # read temperature when SSR is off ( ONly read temp when heating is off due to EMI)
            # Store latest reading
            # Sleep briefly
            pass
```

### 2.2 Configuration (config.py)

```python
# Hardware Configuration
SPI_HARDWARE = True  # True for hardware SPI, False for software
SENSOR_TYPE = "MAX31856"  # or "MAX31855"
THERMOCOUPLE_TYPE = "K"  # K, J, etc.

# GPIO Pin Configuration
PIN_SSR = 18  # Main SSR control
PIN_SAFETY_RELAY = 23  # Safety relay control
PIN_LID_SWITCH = 24  # Lid switch input

# Oven Parameters
KW_ELEMENTS = 7.1  # Heating element power in kW
EMERGENCY_SHUTOFF_TEMP = 2264  # Safety limit (configurable scale bug)
MAX_SSR_ON_TIME = 6  # Maximum SSR on-time per cycle

# PID Parameters
PID_KP = 3
PID_KI = 75
PID_KD = 12
PID_CONTROL_WINDOW = 50  # Temperature window for catching up

# Timing
SENSOR_TIME_WAIT = 3  # Seconds between readings
DUTY_CYCLE = SENSOR_TIME_WAIT

# Display Configuration
TEMP_SCALE = "c"  # "c" or "f"
TIME_SCALE_SLOPE = "h"  # Slope display: s/m/h
TIME_SCALE_PROFILE = "m"  # Profile time: s/m/h
KWH_RATE = 0.25  # Price per kWh
CURRENCY_TYPE = "€"

# Restart Configuration
AUTOMATIC_RESTARTS = True
AUTOMATIC_RESTART_WINDOW = 15  # Minutes
SEEK_START = True  # Auto-seek on hot start

# Storage Paths
STORAGE_DIR = "storage"
PROFILES_DIR = "storage/profiles"
STATE_FILE = "state.json"
```

### 2.3 Data Models

#### 2.3.1 Profile Model
```python
class Profile:
    def __init__(self, name, data, temp_units="c"):
        self.name = name
        self.type = "profile"
        self.data = data  # [[seconds, temperature], ...]
        self.temp_units = temp_units

    def get_target_temperature(self, time):
        # Linear interpolation between data points
        # Return 0 if beyond last point
        pass

    def duration(self):
        # Return max time in seconds
        pass

    def to_json(self):
        # Serialize to JSON
        pass

    @classmethod
    def from_json(cls, json_str):
        # Deserialize from JSON
        pass
```

### 2.4 Emergency & Safety Features

```python
class Oven:
    def reset_if_emergency(self):
        # Check temperature >= emergency_shutoff_temp
        # Check thermocouple error rate > limit
        # Check individual TC faults
        # Abort if any condition met (unless ignored)
        pass

    def check_thermocouple_errors(self):
        # Count errors over sample window
        # Return error rate
        pass
```

### 2.5 Automatic Restart

```python
class Oven:
    def save_automatic_restart_state(self):
        # Write current state to state.json every duty cycle
        # Include: profile, runtime, state, timestamp
        pass

    @classmethod
    def check_automatic_restart(cls):
        # On boot, check if state.json exists
        # Check if state is RUNNING and recent
        # Reload profile and resume at runtime
        pass
```

### 2.6 systemd Service

**File: /etc/systemd/system/kiln-controller.service**
```ini
[Unit]
Description=Kiln Controller Service
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/kiln-controller
Environment=PATH=/home/pi/kiln-controller/venv/bin
ExecStart=/home/pi/kiln-controller/venv/bin/python kiln-controller.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

## 3. iOS Swift Frontend Implementation

### 3.1 Project Structure

```
KilnControllerV2/
├── App/
│   ├── KilnControllerApp.swift        # App entry point
│   ├── AppDelegate.swift              # App lifecycle
│   └── SceneDelegate.swift            # Scene management
├── Models/
│   ├── Profile.swift                  # Firing profile model
│   ├── KilnState.swift                # Current kiln state
│   ├── PIDStats.swift                 # PID statistics
│   ├── ControllerConfig.swift         # Configuration
│   ├── BacklogMessage.swift           # Backlog message
│   └── WebSocketMessage.swift         # Generic WS message
├── ViewModels/
│   ├── DashboardViewModel.swift       # Dashboard logic
│   ├── ProgramsViewModel.swift        # Programs list logic
│   ├── ProgramEditorViewModel.swift   # Profile editing logic
│   ├── GraphViewModel.swift           # Temperature graph logic
│   ├── SettingsViewModel.swift        # Settings logic
│   └── ConnectionViewModel.swift      # Connection management
├── Views/
│   ├── Dashboard/
│   │   ├── DashboardView.swift        # Main dashboard
│   │   ├── StatusCardView.swift       # Status display
│   │   ├── TemperatureGaugeView.swift # Temperature visualization
│   │   └── QuickActionsView.swift     # Quick action buttons
│   ├── Programs/
│   │   ├── ProgramsListView.swift     # Profile list
│   │   ├── ProgramEditorView.swift    # Profile editor
│   │   ├── ProgramCardView.swift      # Profile card
│   │   └── SegmentRowView.swift       # Temperature point row
│   ├── Graph/
│   │   └── GraphView.swift            # Temperature chart
│   ├── Settings/
│   │   ├── SettingsView.swift         # Settings screen
│   │   └── ConnectionSetupView.swift  # Connection configuration
│   └── Components/
│       ├── TempDisplay.swift          # Temperature display
│       ├── ConnectionIndicator.swift  # Connection status
│       └── LoadingOverlay.swift       # Loading spinner
├── Services/
│   ├── WebSocketService.swift         # WebSocket manager (4 sockets)
│   ├── ControllerAPI.swift            # REST API client
│   ├── KeychainService.swift          # Secure storage
│   └── ReachabilityService.swift      # Network connectivity
├── Utilities/
│   ├── TemperatureFormatter.swift     # Temperature formatting
│   ├── Extensions.swift               # Swift extensions
│   └── HapticsManager.swift           # Haptic feedback
├── Resources/
│   ├── Assets.xcassets                # Images, colors
│   └── Localizable.strings            # Localization
└── Tests/
    ├── KilnControllerV2Tests/         # Unit tests
    └── KilnControllerV2UITests/       # UI tests
```

### 3.2 Models

#### 3.2.1 Profile.swift
```swift
struct Profile: Codable, Identifiable {
    let id = UUID()
    let type: String  // Always "profile"
    var name: String
    var tempUnits: String  // "c" or "f"
    var data: [[Double]]  // [[seconds, temperature], ...]

    enum CodingKeys: String, CodingKey {
        case type, name, tempUnits = "temp_units", data
    }

    func getTargetTemperature(at time: Double) -> Double {
        // Linear interpolation between data points
        // Return 0 if beyond last point
        let sortedData = data.sorted { $0[0] < $1[0] }
        guard let lastPoint = sortedData.last else { return 0 }

        if time >= lastPoint[0] {
            return 0
        }

        for i in 0..<sortedData.count - 1 {
            let current = sortedData[i]
            let next = sortedData[i + 1]

            if time >= current[0] && time <= next[0] {
                let ratio = (time - current[0]) / (next[0] - current[0])
                return current[1] + ratio * (next[1] - current[1])
            }
        }

        return 0
    }

    var duration: Double {
        return data.map { $0[0] }.max() ?? 0
    }
}
```

#### 3.2.2 KilnState.swift
```swift
struct KilnState: Codable {
    let cost: Double
    let runtime: Double
    let temperature: Double
    let target: Double
    let state: OvenState
    let heat: Double  // 0.0 off / 1.0 on
    let heatRate: Double  // degrees per hour
    let totalTime: Double
    let kwhRate: Double
    let currencyType: String
    let profile: String?
    let pidstats: PIDStats?
    let catchingUp: Bool

    enum CodingKeys: String, CodingKey {
        case cost, runtime, temperature, target, state
        case heat, heatRate = "heat_rate", totalTime = "totaltime"
        case kwhRate = "kwh_rate", currencyType = "currency_type"
        case profile, pidstats, catchingUp = "catching_up"
    }
}

enum OvenState: String, Codable {
    case idle = "IDLE"
    case running = "RUNNING"
    case paused = "PAUSED"
}
```

#### 3.2.3 PIDStats.swift
```swift
struct PIDStats: Codable {
    let time: Double  // Unix timestamp
    let timeDelta: Double  // Seconds since previous compute
    let setpoint: Double  // Target temp
    let ispoint: Double  // Measured temp
    let err: Double  // setpoint - ispoint
    let errDelta: Double  // err - lastErr
    let p: Double  // kp * err
    let i: Double  // integral term
    let d: Double  // kd * dErr
    let kp: Double  // proportional gain
    let ki: Double  // integral gain
    let kd: Double  // derivative gain
    let pid: Double  // raw combined output
    let out: Double  // normalised 0..1 output

    var heatPercentage: Double {
        return out * 100
    }
}
```

#### 3.2.4 ControllerConfig.swift
```swift
struct ControllerConfig: Codable {
    let tempScale: String  // "c" or "f"
    let timeScaleSlope: String  // s/m/h
    let timeScaleProfile: String  // s/m/h
    let kwhRate: Double
    let currencyType: String

    enum CodingKeys: String, CodingKey {
        case tempScale = "temp_scale"
        case timeScaleSlope = "time_scale_slope"
        case timeScaleProfile = "time_scale_profile"
        case kwhRate = "kwh_rate"
        case currencyType = "currency_type"
    }
}
```

#### 3.2.5 BacklogMessage.swift
```swift
struct BacklogMessage: Codable {
    let type: String  // "backlog"
    let profile: Profile?
    let log: [KilnState]

    enum CodingKeys: String, CodingKey {
        case type, profile, log
    }
}
```

### 3.3 Services

#### 3.3.1 WebSocketService.swift

```swift
import Foundation
import Combine

class WebSocketService: ObservableObject {
    private let baseURL: String
    private let port: Int

    // Four independent WebSocket connections
    private var statusTask: URLSessionWebSocketTask?
    private var controlTask: URLSessionWebSocketTask?
    private var storageTask: URLSessionWebSocketTask?
    private var configTask: URLSessionWebSocketTask?

    // Published state
    @Published var isConnected = false
    @Published var currentProfile: Profile?
    @Published var temperatureHistory: [(time: Double, temp: Double)] = []

    // Callbacks
    var onStateUpdate: ((KilnState) -> Void)?
    var onConfigUpdate: ((ControllerConfig) -> Void)?
    var onProfilesUpdate: (([Profile]) -> Void)?
    var onConnectionError: ((Error) -> Void)?

    init(baseURL: String, port: Int = 8080) {
        self.baseURL = baseURL
        self.port = port
    }

    func connect() {
        connectStatus()
        connectControl()
        connectStorage()
        connectConfig()
    }

    func disconnect() {
        statusTask?.cancel()
        controlTask?.cancel()
        storageTask?.cancel()
        configTask?.cancel()
        isConnected = false
    }

    // MARK: - /status WebSocket

    private func connectStatus() {
        let url = URL(string: "ws://\(baseURL):\(port)/status")!
        statusTask = URLSession.shared.webSocketTask(with: url)

        statusTask?.resume()
        receiveStatusMessages()
        isConnected = true
    }

    private func receiveStatusMessages() {
        statusTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleStatusMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleStatusMessage(text)
                    }
                @unknown default:
                    break
                }
                self?.receiveStatusMessages()  // Continue receiving
            case .failure(let error):
                self?.onConnectionError?(error)
                self?.isConnected = false
                // Reconnect with backoff
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self?.connectStatus()
                }
            }
        }
    }

    private func handleStatusMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        // Try to decode as BacklogMessage first
        if let backlog = try? JSONDecoder().decode(BacklogMessage.self, from: data),
           backlog.type == "backlog" {
            // Handle backlog
            currentProfile = backlog.profile
            temperatureHistory = backlog.log.map { (time: $0.runtime, temp: $0.temperature) }
            onStateUpdate?(backlog.log.last ?? KilnState.placeholder)
            return
        }

        // Otherwise, it's a live state update
        if let state = try? JSONDecoder().decode(KilnState.self, from: data) {
            onStateUpdate?(state)
            temperatureHistory.append((time: state.runtime, temp: state.temperature))
        }
    }

    // MARK: - /control WebSocket

    private func connectControl() {
        let url = URL(string: "ws://\(baseURL):\(port)/control")!
        controlTask = URLSession.shared.webSocketTask(with: url)
        controlTask?.resume()
    }

    func sendRunCommand(profile: Profile) {
        let message = [
            "cmd": "RUN",
            "profile": profile
        ] as [String : Any]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }

        controlTask?.send(.string(text)) { error in
            if let error = error {
                print("Error sending RUN command: \(error)")
            }
        }
    }

    func sendStopCommand() {
        let message = ["cmd": "STOP"]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }

        controlTask?.send(.string(text)) { error in
            if let error = error {
                print("Error sending STOP command: \(error)")
            }
        }
    }

    // MARK: - /storage WebSocket

    private func connectStorage() {
        let url = URL(string: "ws://\(baseURL):\(port)/storage")!
        storageTask = URLSession.shared.webSocketTask(with: url)
        storageTask?.resume()
        receiveStorageMessages()
    }

    private func receiveStorageMessages() {
        storageTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleStorageMessage(text)
                default:
                    break
                }
                self?.receiveStorageMessages()
            case .failure(let error):
                print("Storage WebSocket error: \(error)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self?.connectStorage()
                }
            }
        }
    }

    private func handleStorageMessage(_ text: String) {
        // Try to decode as profile array first
        if let data = text.data(using: .utf8),
           let profiles = try? JSONDecoder().decode([Profile].self, from: data) {
            onProfilesUpdate?(profiles)
            return
        }

        // Handle PUT/DELETE responses
        if let data = text.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let resp = dict["resp"] as? String {
            if resp == "OK" {
                // Success - request full list
                requestProfilesList()
            }
        }
    }

    func requestProfilesList() {
        storageTask?.send(.string("GET")) { error in
            if let error = error {
                print("Error requesting profiles: \(error)")
            }
        }
    }

    func saveProfile(_ profile: Profile, force: Bool = false) {
        let message: [String: Any] = [
            "cmd": "PUT",
            "profile": profile,
            "force": force
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }

        storageTask?.send(.string(text)) { error in
            if let error = error {
                print("Error saving profile: \(error)")
            }
        }
    }

    func deleteProfile(name: String) {
        let message: [String: Any] = [
            "cmd": "DELETE",
            "profile": ["name": name]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }

        storageTask?.send(.string(text)) { error in
            if let error = error {
                print("Error deleting profile: \(error)")
            }
        }
    }

    // MARK: - /config WebSocket

    private func connectConfig() {
        let url = URL(string: "ws://\(baseURL):\(port)/config")!
        configTask = URLSession.shared.webSocketTask(with: url)
        configTask?.resume()
        receiveConfigMessages()
        requestConfig()
    }

    private func receiveConfigMessages() {
        configTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleConfigMessage(text)
                default:
                    break
                }
                self?.receiveConfigMessages()
            case .failure(let error):
                print("Config WebSocket error: \(error)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self?.connectConfig()
                }
            }
        }
    }

    private func handleConfigMessage(_ text: String) {
        if let data = text.data(using: .utf8),
           let config = try? JSONDecoder().decode(ControllerConfig.self, from: data) {
            onConfigUpdate?(config)
        }
    }

    func requestConfig() {
        configTask?.send(.string("GET")) { error in
            if let error = error {
                print("Error requesting config: \(error)")
            }
        }
    }
}

extension KilnState {
    static var placeholder: KilnState {
        return KilnState(
            cost: 0,
            runtime: 0,
            temperature: 0,
            target: 0,
            state: .idle,
            heat: 0,
            heatRate: 0,
            totalTime: 0,
            kwhRate: 0.25,
            currencyType: "€",
            profile: nil,
            pidstats: nil,
            catchingUp: false
        )
    }
}
```

#### 3.3.2 ControllerAPI.swift

```swift
import Foundation
import Combine

class ControllerAPI {
    private let baseURL: String
    private let port: Int
    private let session: URLSession

    init(baseURL: String, port: Int = 8080) {
        self.baseURL = baseURL
        self.port = port
        self.session = URLSession(configuration: .default)
    }

    private func buildURL(path: String) -> URL {
        return URL(string: "http://\(baseURL):\(port)\(path)")!
    }

    // MARK: - Health Check

    func checkConnection() -> AnyPublisher<Bool, Error> {
        let url = buildURL(path: "/api/stats")

        return session.dataTaskPublisher(for: url)
            .map { data, response in
                // Treat empty 200 body as healthy/idle
                if let httpResponse = response as? HTTPURLResponse {
                    return httpResponse.statusCode == 200
                }
                return false
            }
            .catch { _ in
                Just(false)
                    .setFailureType(to: Error.self)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Commands

    func runProfile(name: String, startAt: Int = 0) -> AnyPublisher<Bool, Error> {
        let url = buildURL(path: "/api")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "cmd": "run",
            "profile": name,
            "startat": startAt
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return session.dataTaskPublisher(for: request)
            .map { data, _ in
                guard let response = try? JSONDecoder().decode(CommandResponse.self, from: data) else {
                    return false
                }
                return response.success
            }
            .eraseToAnyPublisher()
    }

    func pause() -> AnyPublisher<Bool, Error> {
        return sendCommand("pause")
    }

    func resume() -> AnyPublisher<Bool, Error> {
        return sendCommand("resume")
    }

    func stop() -> AnyPublisher<Bool, Error> {
        return sendCommand("stop")
    }

    func sendMemo(_ text: String) -> AnyPublisher<Bool, Error> {
        let url = buildURL(path: "/api")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "cmd": "memo",
            "memo": text
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return session.dataTaskPublisher(for: request)
            .map { data, _ in
                guard let response = try? JSONDecoder().decode(CommandResponse.self, from: data) else {
                    return false
                }
                return response.success
            }
            .eraseToAnyPublisher()
    }

    func getStats() -> AnyPublisher<PIDStats?, Error> {
        let url = buildURL(path: "/api/stats")

        return session.dataTaskPublisher(for: url)
            .map { data, _ in
                // Empty body means idle
                guard !data.isEmpty else { return nil }
                return try? JSONDecoder().decode(PIDStats.self, from: data)
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Helpers

    private func sendCommand(_ cmd: String) -> AnyPublisher<Bool, Error> {
        let url = buildURL(path: "/api")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["cmd": cmd]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return session.dataTaskPublisher(for: request)
            .map { data, _ in
                guard let response = try? JSONDecoder().decode(CommandResponse.self, from: data) else {
                    return false
                }
                return response.success
            }
            .eraseToAnyPublisher()
    }
}

struct CommandResponse: Codable {
    let success: Bool
    let error: String?
}
```

#### 3.3.3 KeychainService.swift

```swift
import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()

    private let service = "com.kilncontroller"

    private init() {}

    func save(_ data: Data, forKey key: String) -> Bool {
        let query = [
            kSecValueData: data,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked
        ] as CFDictionary

        SecItemDelete(query)  // Delete existing item if any

        let status = SecItemAdd(query, nil)
        return status == errSecSuccess
    }

    func load(forKey key: String) -> Data? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query, &dataTypeRef)

        if status == errSecSuccess {
            return dataTypeRef as? Data
        }

        return nil
    }

    func delete(forKey key: String) -> Bool {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ] as CFDictionary

        let status = SecItemDelete(query)
        return status == errSecSuccess
    }
}

// Convenience methods for connection settings
extension KeychainService {
    private enum Keys {
        static let host = "host"
        static let port = "port"
    }

    func saveConnection(host: String, port: Int) {
        if let hostData = host.data(using: .utf8) {
            save(hostData, forKey: Keys.host)
        }
        if let portData = String(port).data(using: .utf8) {
            save(portData, forKey: Keys.port)
        }
    }

    func loadConnection() -> (host: String, port: Int)? {
        guard let hostData = load(forKey: Keys.host),
              let portData = load(forKey: Keys.port),
              let host = String(data: hostData, encoding: .utf8),
              let portString = String(data: portData, encoding: .utf8),
              let port = Int(portString) else {
            return nil
        }
        return (host, port)
    }

    func clearConnection() {
        delete(forKey: Keys.host)
        delete(forKey: Keys.port)
    }
}
```

### 3.4 ViewModels

#### 3.4.1 DashboardViewModel.swift

```swift
import Foundation
import Combine

class DashboardViewModel: ObservableObject {
    @Published var currentState: KilnState = .placeholder
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var errorMessage: String?

    private let webSocketService: WebSocketService
    private let controllerAPI: ControllerAPI
    private var cancellables = Set<AnyCancellable>()

    init(webSocketService: WebSocketService, controllerAPI: ControllerAPI) {
        self.webSocketService = webSocketService
        self.controllerAPI = controllerAPI

        setupBindings()
    }

    private func setupBindings() {
        webSocketService.$isConnected
            .assign(to: &$isConnected)

        webSocketService.onStateUpdate = { [weak self] state in
            DispatchQueue.main.async {
                self?.currentState = state
            }
        }

        webSocketService.onConnectionError = { [weak self] error in
            DispatchQueue.main.async {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Commands

    func pause() {
        // Only allow pause when RUNNING (to avoid server bug)
        guard currentState.state == .running else { return }

        controllerAPI.pause()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        self.errorMessage = "Failed to pause: \(error.localizedDescription)"
                    }
                },
                receiveValue: { success in
                    if !success {
                        self.errorMessage = "Pause command failed"
                    }
                }
            )
            .store(in: &cancellables)
    }

    func resume() {
        // Only allow resume when PAUSED (to avoid server bug)
        guard currentState.state == .paused else { return }

        controllerAPI.resume()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        self.errorMessage = "Failed to resume: \(error.localizedDescription)"
                    }
                },
                receiveValue: { success in
                    if !success {
                        self.errorMessage = "Resume command failed"
                    }
                }
            )
            .store(in: &cancellables)
    }

    func stop() {
        controllerAPI.stop()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        self.errorMessage = "Failed to stop: \(error.localizedDescription)"
                    }
                },
                receiveValue: { success in
                    if !success {
                        self.errorMessage = "Stop command failed"
                    }
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Computed Properties

    var temperatureDisplay: String {
        let formatter = TemperatureFormatter()
        return formatter.format(currentState.temperature)
    }

    var targetDisplay: String {
        let formatter = TemperatureFormatter()
        return formatter.format(currentState.target)
    }

    var heatPercentage: Int {
        guard let pidstats = currentState.pidstats else { return 0 }
        return Int(pidstats.heatPercentage)
    }

    var isIdle: Bool {
        return currentState.state == .idle
    }

    var isRunning: Bool {
        return currentState.state == .running
    }

    var isPaused: Bool {
        return currentState.state == .paused
    }

    var elapsedTimeString: String {
        let hours = Int(currentState.runtime) / 3600
        let minutes = (Int(currentState.runtime) % 3600) / 60
        let seconds = Int(currentState.runtime) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var totalTimeString: String {
        let hours = Int(currentState.totalTime) / 3600
        let minutes = (Int(currentState.totalTime) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var costDisplay: String {
        return String(format: "%.2f %@", currentState.cost, currentState.currencyType)
    }

    var heatRateDisplay: String {
        return String(format: "%.1f°/hr", currentState.heatRate)
    }
}
```

#### 3.4.2 ProgramsViewModel.swift

```swift
import Foundation
import Combine

class ProgramsViewModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showDeleteAlert = false
    @Published var profileToDelete: Profile?

    private let webSocketService: WebSocketService
    private var cancellables = Set<AnyCancellable>()

    init(webSocketService: WebSocketService) {
        self.webSocketService = webSocketService

        setupBindings()
    }

    private func setupBindings() {
        webSocketService.onProfilesUpdate = { [weak self] profiles in
            DispatchQueue.main.async {
                self?.profiles = profiles
                self?.isLoading = false
            }
        }
    }

    func loadProfiles() {
        isLoading = true
        webSocketService.requestProfilesList()
    }

    func saveProfile(_ profile: Profile) {
        webSocketService.saveProfile(profile, force: false)
    }

    func forceSaveProfile(_ profile: Profile) {
        webSocketService.saveProfile(profile, force: true)
    }

    func confirmDelete(_ profile: Profile) {
        profileToDelete = profile
        showDeleteAlert = true
    }

    func deleteProfile() {
        guard let profile = profileToDelete else { return }

        webSocketService.deleteProfile(name: profile.name)
        profileToDelete = nil
        showDeleteAlert = false
    }
}
```

### 3.5 Views

#### 3.5.1 DashboardView.swift

```swift
import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @State private var showingSettings = false

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status
                    ConnectionIndicator(
                        isConnected: viewModel.isConnected,
                        errorMessage: viewModel.errorMessage
                    )

                    if viewModel.isConnected {
                        // Temperature Gauge
                        TemperatureGaugeView(
                            current: viewModel.currentState.temperature,
                            target: viewModel.currentState.target,
                            state: viewModel.currentState.state
                        )

                        // Status Card
                        StatusCardView(viewModel: viewModel)

                        // Quick Actions
                        QuickActionsView(viewModel: viewModel)

                        // Additional Stats
                        StatsView(viewModel: viewModel)
                    }
                }
                .padding()
            }
            .navigationTitle("Kiln Controller")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}
```

#### 3.5.2 ProgramsListView.swift

```swift
import SwiftUI

struct ProgramsListView: View {
    @StateObject private var viewModel: ProgramsViewModel
    @State private var showingEditor = false
    @State private var editingProfile: Profile?

    init(viewModel: ProgramsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.isLoading {
                    ProgressView("Loading profiles...")
                } else if viewModel.profiles.isEmpty {
                    Text("No profiles found")
                        .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(viewModel.profiles) { profile in
                            NavigationLink(destination: ProfileDetailView(profile: profile)) {
                                ProgramCardView(profile: profile)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Firing Programs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: createNewProfile) {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                viewModel.loadProfiles()
            }
            .alert("Delete Profile", isPresented: $viewModel.showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    viewModel.deleteProfile()
                }
            } message: {
                if let profile = viewModel.profileToDelete {
                    Text("Are you sure you want to delete \(profile.name)?")
                }
            }
            .sheet(isPresented: $showingEditor) {
                if let profile = editingProfile {
                    ProgramEditorView(profile: profile, onSave: { updatedProfile in
                        viewModel.saveProfile(updatedProfile)
                    })
                } else {
                    ProgramEditorView(profile: Profile(name: "New Profile", tempUnits: "c", data: []), onSave: { newProfile in
                        viewModel.saveProfile(newProfile)
                    })
                }
            }
        }
    }

    private func createNewProfile() {
        editingProfile = Profile(name: "New Profile", tempUnits: "c", data: [])
        showingEditor = true
    }
}

struct ProgramCardView: View {
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(profile.name)
                .font(.headline)

            Text("\(profile.data.count) points")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Duration: \(durationString)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var durationString: String {
        let hours = Int(profile.duration) / 3600
        let minutes = (Int(profile.duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct ProfileDetailView: View {
    let profile: Profile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Profile Info
                VStack(alignment: .leading) {
                    Text(profile.name)
                        .font(.title)
                        .bold()

                    Text("Temperature Unit: \(profile.tempUnits.uppercased())")
                        .foregroundColor(.secondary)
                }

                Divider()

                // Temperature Graph
                Text("Temperature Schedule")
                    .font(.headline)

                ProfileGraphView(profile: profile)

                Divider()

                // Temperature Points
                Text("Schedule Points")
                    .font(.headline)

                ForEach(Array(profile.data.enumerated()), id: \.offset) { index, point in
                    HStack {
                        Text("\(timeString(point[0]))")
                            .frame(width: 80, alignment: .leading)

                        Spacer()

                        Text("\(String(format: "%.1f", point[1]))°")
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .navigationTitle("Program Details")
    }

    private func timeString(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return String(format: "%02d:%02d", hours, minutes)
        } else {
            return String(format: "%02d:%02d", 0, minutes)
        }
    }
}

struct ProfileGraphView: View {
    let profile: Profile

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid lines
                Path { path in
                    // Add grid lines here
                }
                .stroke(Color.gray.opacity(0.3))

                // Temperature curve
                Path { path in
                    guard let firstPoint = profile.data.first else { return }

                    let width = geometry.size.width
                    let height = geometry.size.height
                    let maxTime = profile.duration
                    let maxTemp = profile.data.map { $0[1] }.max() ?? 100

                    func mapPoint(_ point: [Double]) -> CGPoint {
                        let x = (point[0] / maxTime) * width
                        let y = height - (point[1] / maxTemp) * height
                        return CGPoint(x: x, y: y)
                    }

                    path.move(to: mapPoint(firstPoint))

                    for point in profile.data {
                        path.addLine(to: mapPoint(point))
                    }
                }
                .stroke(Color.blue, lineWidth: 2)
            }
        }
        .frame(height: 200)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
```

#### 3.5.3 ProgramEditorView.swift

```swift
import SwiftUI

struct ProgramEditorView: View {
    @Environment(\.dismiss) var dismiss
    @State private var profile: Profile
    let onSave: (Profile) -> Void

    @State private var showingAddPoint = false
    @State private var newTime = ""
    @State private var newTemp = ""

    init(profile: Profile, onSave: @escaping (Profile) -> Void) {
        _profile = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile Name")) {
                    TextField("Name", text: $profile.name)
                }

                Section(header: Text("Temperature Points")) {
                    ForEach(Array(profile.data.enumerated()), id: \.offset) { index, point in
                        HStack {
                            Text("\(timeString(point[0]))")
                                .frame(width: 80, alignment: .leading)

                            Text("\(String(format: "%.1f", point[1]))°")
                                .frame(width: 80, alignment: .trailing)

                            Spacer()

                            Button(action: { deletePoint(at: index) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Button(action: { showingAddPoint = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Point")
                        }
                    }
                }
            }
            .navigationTitle("Edit Program")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(profile.name.isEmpty || profile.data.isEmpty)
                }
            }
            .alert("Add Point", isPresented: $showingAddPoint) {
                TextField("Time (seconds)", text: $newTime)
                    .keyboardType(.numberPad)
                TextField("Temperature", text: $newTemp)
                    .keyboardType(.decimalPad)

                Button("Cancel", role: .cancel) { }
                Button("Add") {
                    addPoint()
                }
            }
        }
    }

    private func addPoint() {
        guard let time = Double(newTime),
              let temp = Double(newTemp) else { return }

        profile.data.append([time, temp])
        profile.data.sort { $0[0] < $1[0] }

        newTime = ""
        newTemp = ""
    }

    private func deletePoint(at index: Int) {
        profile.data.remove(at: index)
    }

    private func saveProfile() {
        onSave(profile)
        dismiss()
    }

    private func timeString(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return String(format: "%02d:%02d", hours, minutes)
        } else {
            return String(format: "%02d:%02d", 0, minutes)
        }
    }
}
```

#### 3.5.4 SettingsView.swift

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connection")) {
                    HStack {
                        Text("Host")
                        Spacer()
                        Text(viewModel.host)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Port")
                        Spacer()
                        Text("\(viewModel.port)")
                            .foregroundColor(.secondary)
                    }

                    Button("Test Connection") {
                        viewModel.testConnection()
                    }
                    .disabled(viewModel.isTesting)

                    if viewModel.isTesting {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Testing...")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Temperature Units")) {
                    Picker("Scale", selection: $viewModel.tempScale) {
                        Text("Celsius").tag("c")
                        Text("Fahrenheit").tag("f")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("Cost Calculation")) {
                    HStack {
                        Text("Electricity Rate")
                        Spacer()
                        TextField("€/kWh", value: $viewModel.kwhRate, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Currency")
                        Spacer()
                        TextField("Symbol", text: $viewModel.currencyType)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 50)
                    }
                }

                Section(header: Text("Hardware")) {
                    HStack {
                        Text("Element Power")
                        Spacer()
                        TextField("kW", value: $viewModel.kwElements, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                    }

                    Picker("Sensor Type", selection: $viewModel.sensorType) {
                        Text("MAX31855").tag("MAX31855")
                        Text("MAX31856").tag("MAX31856")
                    }

                    Picker("Thermocouple", selection: $viewModel.thermocoupleType) {
                        Text("Type K").tag("K")
                        Text("Type J").tag("J")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        viewModel.saveSettings()
                        dismiss()
                    }
                }
            }
            .alert("Connection Test", isPresented: $viewModel.showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.alertMessage)
            }
        }
    }
}
```

#### 3.5.5 ConnectionSetupView.swift

```swift
import SwiftUI

struct ConnectionSetupView: View {
    @Environment(\.dismiss) var dismiss
    @State private var host: String = ""
    @State private var port: String = "8080"
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var showError = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Address")) {
                    TextField("Host IP", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .autocapitalization(.none)

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }

                Section {
                    Button(action: testConnection) {
                        HStack {
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Testing...")
                            } else {
                                Text("Test Connection")
                            }
                            Spacer()
                        }
                    }
                    .disabled(host.isEmpty || port.isEmpty || isTesting)

                    if let result = testResult {
                        Text(result)
                            .foregroundColor(result.contains("Success") ? .green : .red)
                    }
                }
            }
            .navigationTitle("Connection Setup")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Connect") {
                        saveAndConnect()
                    }
                    .disabled(host.isEmpty || port.isEmpty)
                }
            }
            .onAppear {
                loadSavedConnection()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(testResult ?? "Unknown error")
            }
        }
    }

    private func loadSavedConnection() {
        if let (savedHost, savedPort) = KeychainService.shared.loadConnection() {
            host = savedHost
            port = String(savedPort)
        }
    }

    private func testConnection() {
        guard let portNum = Int(port) else { return }

        isTesting = true
        testResult = nil

        let api = ControllerAPI(baseURL: host, port: portNum)

        api.checkConnection()
            .sink(
                receiveCompletion: { completion in
                    isTesting = false
                    if case .failure(let error) = completion {
                        testResult = "Failed: \(error.localizedDescription)"
                        showError = true
                    }
                },
                receiveValue: { success in
                    isTesting = false
                    testResult = success ? "Success! Connection established." : "Failed: No response"
                }
            )
            .store(in: &cancellables)
    }

    private func saveAndConnect() {
        guard let portNum = Int(port) else { return }

        KeychainService.shared.saveConnection(host: host, port: portNum)
        dismiss()
    }

    private var cancellables = Set<AnyCancellable>()
}
```

### 3.6 Utilities

#### 3.6.1 TemperatureFormatter.swift

```swift
import Foundation

class TemperatureFormatter {
    private let celsiusToFahrenheit: (Double) -> Double = { c in
        return (c * 9/5) + 32
    }

    private let fahrenheitToCelsius: (Double) -> Double = { f in
        return (f - 32) * 5/9
    }

    enum Unit {
        case celsius
        case fahrenheit
    }

    func format(_ temperature: Double, unit: Unit = .celsius) -> String {
        let value: Double
        let symbol: String

        switch unit {
        case .celsius:
            value = temperature
            symbol = "°C"
        case .fahrenheit:
            value = celsiusToFahrenheit(temperature)
            symbol = "°F"
        }

        return String(format: "%.1f%@", value, symbol)
    }

    func convert(_ temperature: Double, from: Unit, to: Unit) -> Double {
        if from == to {
            return temperature
        }

        switch (from, to) {
        case (.celsius, .fahrenheit):
            return celsiusToFahrenheit(temperature)
        case (.fahrenheit, .celsius):
            return fahrenheitToCelsius(temperature)
        default:
            return temperature
        }
    }
}
```

#### 3.6.2 Extensions.swift

```swift
import SwiftUI

// MARK: - View Extensions

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Array Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - String Extensions

extension String {
    var isValidIP: Bool {
        let pattern = "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$"
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: self)
    }
}
```

#### 3.6.3 HapticsManager.swift

```swift
import UIKit

class HapticsManager {
    static let shared = HapticsManager()

    private init() {}

    enum HapticType {
        case light
        case medium
        case heavy
        case success
        case warning
        case error
    }

    func play(_ type: HapticType) {
        switch type {
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()

        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()

        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)

        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
}
```

### 3.7 Main App Entry Point

```swift
import SwiftUI

@main
struct KilnControllerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            DashboardView(viewModel: appState.dashboardViewModel)
                .tabItem {
                    Label("Dashboard", systemImage: "gauge")
                }

            ProgramsListView(viewModel: appState.programsViewModel)
                .tabItem {
                    Label("Programs", systemImage: "list.bullet")
                }

            GraphView(viewModel: appState.graphViewModel)
                .tabItem {
                    Label("Graph", systemImage: "chart.xyaxis.line")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onAppear {
            appState.connectIfNeeded()
        }
    }
}
```

```swift
import Foundation
import Combine

class AppState: ObservableObject {
    @Published var isConnected = false
    @Published var currentHost: String?
    @Published var currentPort: Int?

    // Services
    let webSocketService: WebSocketService
    let controllerAPI: ControllerAPI

    // ViewModels
    let dashboardViewModel: DashboardViewModel
    let programsViewModel: ProgramsViewModel
    let graphViewModel: GraphViewModel

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Load connection settings
        let (host, port) = KeychainService.shared.loadConnection() ?? ("192.168.178.120", 8080)
        currentHost = host
        currentPort = port

        // Initialize services
        webSocketService = WebSocketService(baseURL: host, port: port)
        controllerAPI = ControllerAPI(baseURL: host, port: port)

        // Initialize ViewModels
        dashboardViewModel = DashboardViewModel(
            webSocketService: webSocketService,
            controllerAPI: controllerAPI
        )

        programsViewModel = ProgramsViewModel(
            webSocketService: webSocketService
        )

        graphViewModel = GraphViewModel(
            webSocketService: webSocketService
        )

        setupBindings()
    }

    private func setupBindings() {
        webSocketService.$isConnected
            .assign(to: &$isConnected)
    }

    func connectIfNeeded() {
        if !isConnected {
            webSocketService.connect()
            programsViewModel.loadProfiles()
        }
    }

    func reconnect() {
        webSocketService.disconnect()
        webSocketService.connect()
        programsViewModel.loadProfiles()
    }

    func updateConnection(host: String, port: Int) {
        currentHost = host
        currentPort = port

        // Recreate services with new connection
        // (In a real app, you'd want to do this more carefully)
    }
}
```

---

## 4. Hardware Integration

### 4.1 Raspberry Pi 3 B Setup

#### 4.1.1 Hardware Requirements

- **Raspberry Pi 3 B** or newer
- **MAX31855** or **MAX31856** thermocouple amplifier
- **Type K Thermocouple** (or other supported type)
- **SSR (Solid State Relay)** for heating element control
- **Safety Relay** with lid switch
- **Power supply** (5V 2.5A for Pi, separate for kiln)
- **SD Card** (16GB+ Class 10)
- **Case** with cooling

#### 4.1.2 Wiring Diagram

```
Raspberry Pi 3 B GPIO
├── SPI0 MOSI (GPIO 10) → MAX31855/56 SDI
├── SPI0 MISO (GPIO 9)  → MAX31855/56 SDO
├── SPI0 SCLK (GPIO 11) → MAX31855/56 SCK
├── SPI0 CE0 (GPIO 8)   → MAX31855/56 CS
├── GPIO 18             → SSR Control
├── GPIO 23             → Safety Relay Control
├── GPIO 24             → Lid Switch Input
└── GND                 → Common Ground

MAX31855/56 Thermocouple Amplifier
├── VCC                 → 3.3V
├── GND                 → GND
├── T+                  → Thermocouple +
├── T-                  → Thermocouple -
└── SPI pins as above

Thermocouple (Type K)
├── Yellow (+)          → MAX31855/56 T+
└── Red (-)             → MAX31855/56 T-

SSR (Solid State Relay)
├── Control +           → GPIO 18
├── Control -           → GND
├── Load +              → Kiln Heating Element
└── Load -              → Power Supply (L2)

Safety Relay
├── Coil +              → GPIO 23
├── Coil -              → GND
├── NO                  → SSR Control +
└── COM                 → Power Supply (L1)

Lid Switch (Normally Open)
├── One side            → GPIO 24
└── Other side          → GND

Kiln Heating Elements
├── Element 1           → SSR Load +
└── Element 2           → Power Supply Neutral
```

#### 4.1.3 GPIO Configuration

```python
# config.py
import RPi.GPIO as GPIO

# Use BCM numbering
GPIO.setmode(GPIO.BCM)

# Output pins
PIN_SSR = 18
PIN_SAFETY_RELAY = 23

# Input pins
PIN_LID_SWITCH = 24

# Setup
GPIO.setup(PIN_SSR, GPIO.OUT)
GPIO.setup(PIN_SAFETY_RELAY, GPIO.OUT)
GPIO.setup(PIN_LID_SWITCH, GPIO.IN, pull_up_down=GPIO.PUD_UP)

# Initial state
GPIO.output(PIN_SSR, GPIO.LOW)  # SSR off
GPIO.output(PIN_SAFETY_RELAY, GPIO.LOW)  # Safety relay off
```

### 4.2 Temperature Sensor Integration

#### 4.2.1 MAX31855/56 SPI Interface

```python
# lib/tempSensor.py
import spidev
import time
from config import SENSOR_TYPE, THERMOCOUPLE_TYPE

class MAX31855:
    def __init__(self, bus=0, device=0):
        self.spi = spidev.SpiDev()
        self.spi.open(bus, device)
        self.spi.max_speed_hz = 5000000  # 5 MHz

    def read_temp_c(self):
        # Read 4 bytes from MAX31855
        data = self.spi.readbytes(4)

        # Convert bytes to 32-bit integer
        value = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3]

        # Check for errors
        if value & 0x7:
            raise ThermocoupleError(f"Thermocouple error: 0x{value & 0x7:02x}")

        # Extract temperature (14-bit, 0.25°C resolution)
        temp_raw = value >> 18

        # Handle signed 14-bit value
        if temp_raw & 0x2000:
            temp_raw -= 0x4000

        # Convert to Celsius
        temp_c = temp_raw * 0.25

        return temp_c

    def close(self):
        self.spi.close()

class MAX31856:
    def __init__(self, bus=0, device=0, thermocouple_type='K'):
        self.spi = spidev.SpiDev()
        self.spi.open(bus, device)
        self.spi.max_speed_hz = 5000000
        self.thermocouple_type = thermocouple_type

        # Configure MAX31856
        self._configure()

    def _configure(self):
        # Set thermocouple type
        type_map = {
            'B': 0b0000,
            'E': 0b0001,
            'J': 0b0010,
            'K': 0b0011,
            'N': 0b0100,
            'R': 0b0101,
            'S': 0b0110,
            'T': 0b0111,
        }

        cr0 = 0x80  # Auto conversion mode
        cr1 = type_map.get(self.thermocouple_type, 0b0011) << 4  # Type K default

        self._write_register(0x80, cr0)  # CR0
        self._write_register(0x81, cr1)  # CR1

    def _write_register(self, reg, value):
        self.spi.xfer2([reg | 0x80, value])  # Write bit set

    def _read_register(self, reg):
        return self.spi.xfer2([reg, 0])[1]

    def read_temp_c(self):
        # Read temperature register
        msb = self._read_register(0x0C)
        lsb = self._read_register(0x0D)

        # Check for faults
        fault = self._read_register(0x0F)
        if fault & 0x1F:
            raise ThermocoupleError(f"Thermocouple fault: 0x{fault:02x}")

        # Combine bytes and convert to temperature
        temp_raw = (msb << 8) | lsb

        # Handle signed value
        if temp_raw & 0x8000:
            temp_raw -= 0x10000

        # Convert to Celsius (0.0078125°C resolution)
        temp_c = temp_raw * 0.0078125

        return temp_c

    def close(self):
        self.spi.close()

class ThermocoupleError(Exception):
    pass
```

#### 4.2.2 TempSensor Thread

```python
# lib/tempSensor.py (continued)
import threading
from config import SENSOR_TIME_WAIT, TEMP_SCALE

class TempSensor(threading.Thread):
    def __init__(self):
        super().__init__()
        self.daemon = True
        self.running = False
        self.temperature = 0.0
        self.error_count = 0
        self.total_readings = 0

        # Initialize sensor based on config
        if SENSOR_TYPE == "MAX31856":
            self.sensor = MAX31856(thermocouple_type=THERMOCOUPLE_TYPE)
        else:
            self.sensor = MAX31855()

    def run(self):
        self.running = True

        while self.running:
            try:
                temp_c = self.sensor.read_temp_c()

                # Convert to configured scale
                if TEMP_SCALE == "f":
                    temp = temp_c * 9/5 + 32
                else:
                    temp = temp_c

                self.temperature = temp
                self.error_count = 0
                self.total_readings += 1

            except ThermocoupleError as e:
                self.error_count += 1
                self.total_readings += 1
                print(f"Thermocouple error: {e}")

            except Exception as e:
                print(f"Sensor error: {e}")

            time.sleep(0.1)  # Read frequently, oven polls at SENSOR_TIME_WAIT

    def get_temperature(self):
        return self.temperature

    def get_error_rate(self):
        if self.total_readings == 0:
            return 0.0
        return self.error_count / self.total_readings

    def stop(self):
        self.running = False
        self.sensor.close()
```

### 4.3 SSR & Safety Relay Control

```python
# lib/hardware.py
import RPi.GPIO as GPIO
from config import PIN_SSR, PIN_SAFETY_RELAY, PIN_LID_SWITCH

class HardwareController:
    def __init__(self):
        GPIO.setmode(GPIO.BCM)
        GPIO.setup(PIN_SSR, GPIO.OUT)
        GPIO.setup(PIN_SAFETY_RELAY, GPIO.OUT)
        GPIO.setup(PIN_LID_SWITCH, GPIO.IN, pull_up_down=GPIO.PUD_UP)

        # Initial state - all off
        self.ssr_on = False
        self.safety_relay_on = False

        GPIO.output(PIN_SSR, GPIO.LOW)
        GPIO.output(PIN_SAFETY_RELAY, GPIO.LOW)

    def enable_safety_relay(self):
        """Enable safety relay (power to SSR)"""
        if not self.is_lid_open():
            GPIO.output(PIN_SAFETY_RELAY, GPIO.HIGH)
            self.safety_relay_on = True
        else:
            print("Cannot enable safety relay: lid is open")

    def disable_safety_relay(self):
        """Disable safety relay (cut power to SSR)"""
        GPIO.output(PIN_SAFETY_RELAY, GPIO.LOW)
        self.ssr_on = False  # Also turn off SSR
        GPIO.output(PIN_SSR, GPIO.LOW)
        self.safety_relay_on = False

    def enable_ssr(self):
        """Enable SSR (power to heating elements)"""
        if self.safety_relay_on and not self.is_lid_open():
            GPIO.output(PIN_SSR, GPIO.HIGH)
            self.ssr_on = True
        else:
            print("Cannot enable SSR: safety relay off or lid open")

    def disable_ssr(self):
        """Disable SSR"""
        GPIO.output(PIN_SSR, GPIO.LOW)
        self.ssr_on = False

    def is_lid_open(self):
        """Check if lid switch is open"""
        return GPIO.input(PIN_LID_SWITCH) == GPIO.LOW  # Active low

    def emergency_shutdown(self):
        """Emergency shutdown - disable everything"""
        self.disable_ssr()
        self.disable_safety_relay()
        print("EMERGENCY SHUTDOWN")

    def cleanup(self):
        GPIO.cleanup()
```

---

## 5. Deployment & Installation

### 5.1 Raspberry Pi Setup

#### 5.1.1 OS Installation

1. Download Raspberry Pi OS Lite (64-bit)
2. Flash to SD card using Raspberry Pi Imager
3. Enable SSH and configure WiFi in `raspi-config`
4. Update system:
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install -y python3 python3-pip python3-venv git
   ```

#### 5.1.2 System Dependencies

```bash
# Install system dependencies
sudo apt install -y python3-dev libgpiod-dev

# Enable SPI
sudo raspi-config nonint do_spi 0

# Enable I2C (if needed)
sudo raspi-config nonint do_i2c 0

# Enable serial (if needed)
sudo raspi-config nonint do_serial 0

# Reboot
sudo reboot
```

#### 5.1.3 Python Environment Setup

```bash
# Create project directory
cd ~
mkdir kiln-controller
cd kiln-controller

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Create directory structure
mkdir -p lib storage/profiles public

# Install Python dependencies
pip install --upgrade pip
pip install bottle gevent gevent-websocket RPi.GPIO spidev

# Save dependencies
pip freeze > requirements.txt
```

#### 5.1.4 Application Deployment

```bash
# Copy files to Raspberry Pi
# (Assuming files are in ~/Downloads/kiln-controller-bug-fixed)
cp -r ~/Downloads/kiln-controller-bug-fixed/* ~/kiln-controller/

# Set ownership
sudo chown -R pi:pi ~/kiln-controller

# Make scripts executable
chmod +x kiln-controller.py

# Test run
cd ~/kiln-controller
source venv/bin/activate
python3 kiln-controller.py
```

#### 5.1.5 systemd Service Setup

```bash
# Create systemd service file
sudo tee /etc/systemd/system/kiln-controller.service > /dev/null <<EOF
[Unit]
Description=Kiln Controller Service
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/kiln-controller
Environment=PATH=/home/pi/kiln-controller/venv/bin
ExecStart=/home/pi/kiln-controller/venv/bin/python3 kiln-controller.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable kiln-controller.service
sudo systemctl start kiln-controller.service

# Check status
sudo systemctl status kiln-controller.service

# View logs
sudo journalctl -u kiln-controller.service -f
```

#### 5.1.6 Network Configuration

**Static IP (Optional but recommended):**

```bash
# Edit dhcpcd configuration
sudo nano /etc/dhcpcd.conf

# Add at the end:
interface eth0
static ip_address=192.168.178.120/24
static routers=192.168.178.1
static domain_name_servers=192.168.178.1

# Reboot
sudo reboot
```

**Firewall Configuration:**

```bash
# Install ufw if not present
sudo apt install -y ufw

# Allow SSH
sudo ufw allow ssh

# Allow kiln controller ports
sudo ufw allow 8080/tcp

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status
```

### 5.2 iOS App Deployment

#### 5.2.1 Development Setup

1. **Prerequisites:**
   - Mac with Xcode 15+
   - iOS 16+ device or simulator
   - Apple Developer account (for TestFlight/App Store)

2. **Project Setup:**
   ```bash
   # Create new Xcode project
   # File → New → Project → iOS → App
   # Name: KilnControllerV2
   # Interface: SwiftUI
   # Language: Swift
   # Storage: None
   ```

3. **Add Dependencies:**
   ```bash
   # Using Swift Package Manager
   # File → Add Package Dependencies
   # Add: Combine (built-in), no external packages needed
   ```

4. **Configure Project:**
   - Set deployment target to iOS 16.0
   - Enable Local Network capability (for LAN communication)
   - Add Info.plist keys:
     ```xml
     <key>NSLocalNetworkUsageDescription</key>
     <string>Required to communicate with the kiln controller on your local network</string>
     <key>NSBonjourServices</key>
     <array>
         <string>_http._tcp</string>
         <string>_ws._tcp</string>
     </array>
     ```

#### 5.2.2 Building for Testing

```bash
# Build for simulator
xcodebuild -scheme KilnControllerV2 -destination 'platform=iOS Simulator,name=iPhone 15' clean build

# Build for device
xcodebuild -scheme KilnControllerV2 -destination 'platform=iOS,name=Your iPhone' clean build
```

#### 5.2.3 TestFlight Distribution

1. **Archive Build:**
   ```bash
   # Archive
   xcodebuild archive -scheme KilnControllerV2 -archivePath ~/Desktop/KilnControllerV2.xcarchive

   # Export for App Store
   xcodebuild -exportArchive -archivePath ~/Desktop/KilnControllerV2.xcarchive -exportPath ~/Desktop/KilnControllerV2-IPA -exportOptionsPlist ExportOptions.plist
   ```

2. **Upload to App Store Connect:**
   ```bash
   xcrun altool --upload-app --type ios --file ~/Desktop/KilnControllerV2-IPA/KilnControllerV2.ipa --apiKey YOUR_API_KEY --apiIssuer YOUR_ISSUER_ID
   ```

3. **Configure TestFlight:**
   - Add internal testers
   - Create beta group
   - Distribute build

#### 5.2.4 Ad-Hoc Distribution (for personal use)

```bash
# Create ExportOptions.plist for ad-hoc
cat > ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>compileBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF

# Export ad-hoc IPA
xcodebuild -exportArchive -archivePath ~/Desktop/KilnControllerV2.xcarchive -exportPath ~/Desktop/KilnControllerV2-AdHoc -exportOptionsPlist ExportOptions.plist
```

#### 5.2.5 App Store Submission

1. **Prepare for Submission:**
   - Create App Store Connect record
   - Add screenshots (required sizes)
   - Write app description
   - Set age rating
   - Add privacy policy URL

2. **Submit:**
   ```bash
   # Use Xcode Organizer or Transporter app
   # Or command line:
   xcrun altool --upload-app --type ios --file ~/Desktop/KilnControllerV2-IPA/KilnControllerV2.ipa --apiKey YOUR_API_KEY --apiIssuer YOUR_ISSUER_ID
   ```

---

## 6. Testing Strategy

### 6.1 Python Backend Testing

#### 6.1.1 Unit Tests

```python
# tests/test_oven.py
import unittest
import time
from unittest.mock import Mock, patch
from lib.oven import Oven, PID
from config import PID_KP, PID_KI, PID_KD

class TestPID(unittest.TestCase):
    def setUp(self):
        self.pid = PID(PID_KP, PID_KI, PID_KD)

    def test_pid_compute(self):
        # Test PID computation
        output = self.pid.compute(setpoint=100, input=90)
        self.assertIsNotNone(output)
        self.assertIn('out', output)
        self.assertIn('pid', output)

    def test_pid_reset(self):
        self.pid.compute(100, 90)
        self.pid.reset()
        # Verify reset state
        self.assertEqual(self.pid.iterm, 0)

class TestOven(unittest.TestCase):
    def setUp(self):
        self.mock_config = Mock()
        self.oven = Oven(self.mock_config)

    def test_get_state(self):
        state = self.oven.get_state()
        self.assertIn('state', state)
        self.assertIn('temperature', state)
        self.assertIn('target', state)

    @patch('lib.oven.time.sleep')
    def test_control_loop(self, mock_sleep):
        # Test control loop iteration
        self.oven.state = "RUNNING"
        self.oven._control_loop()
        # Verify state changes
        self.assertIsNotNone(self.oven.get_state())

class TestProfile(unittest.TestCase):
    def test_profile_interpolation(self):
        from lib.oven import Profile
        profile = Profile("Test", [[0, 25], [3600, 300]])

        # Test interpolation
        temp = profile.get_target_temperature(1800)  # Midpoint
        self.assertAlmostEqual(temp, 162.5, places=1)

    def test_profile_duration(self):
        from lib.oven import Profile
        profile = Profile("Test", [[0, 25], [7200, 600]])
        self.assertEqual(profile.duration(), 7200)

if __name__ == '__main__':
    unittest.main()
```

#### 6.1.2 Integration Tests

```python
# tests/test_integration.py
import unittest
import json
import requests
import time
from threading import Thread
from kiln_controller import start_server

class TestAPI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Start test server
        cls.server_thread = Thread(target=start_server)
        cls.server_thread.daemon = True
        cls.server_thread.start()
        time.sleep(2)  # Wait for server to start

        cls.base_url = "http://localhost:8080"

    def test_health_check(self):
        response = requests.get(f"{self.base_url}/api/stats")
        self.assertEqual(response.status_code, 200)

    def test_run_command(self):
        # Create test profile
        profile = {
            "type": "profile",
            "name": "TestProfile",
            "temp_units": "c",
            "data": [[0, 25], [3600, 300]]
        }

        # Save profile via storage WebSocket
        # (WebSocket testing requires async, simplified here)

        # Run profile
        response = requests.post(
            f"{self.base_url}/api",
            json={"cmd": "run", "profile": "TestProfile"}
        )
        data = response.json()
        self.assertTrue(data.get('success', False))

        # Stop
        response = requests.post(
            f"{self.base_url}/api",
            json={"cmd": "stop"}
        )
        data = response.json()
        self.assertTrue(data.get('success', False))

if __name__ == '__main__':
    unittest.main()
```

#### 6.1.3 Hardware-in-Loop Testing

```python
# tests/test_hardware.py
import unittest
import time
from unittest.mock import patch, MagicMock
from lib.tempSensor import TempSensor, MAX31855
from lib.hardware import HardwareController
import RPi.GPIO as GPIO

class TestTempSensor(unittest.TestCase):
    @patch('lib.tempSensor.spidev.SpiDev')
    def test_max31855_read(self, mock_spi):
        # Mock SPI response
        mock_spi_instance = MagicMock()
        mock_spi.return_value = mock_spi_instance
        mock_spi_instance.readbytes.return_value = [0x00, 0x00, 0x00, 0x0C]  # 25°C

        sensor = MAX31855()
        temp = sensor.read_temp_c()
        self.assertAlmostEqual(temp, 25.0, places=1)

class TestHardwareController(unittest.TestCase):
    @patch('lib.hardware.GPIO')
    def test_ssr_control(self, mock_gpio):
        controller = HardwareController()

        controller.enable_safety_relay()
        mock_gpio.output.assert_called_with(23, mock_gpio.HIGH)

        controller.enable_ssr()
        mock_gpio.output.assert_called_with(18, mock_gpio.HIGH)

        controller.disable_ssr()
        mock_gpio.output.assert_called_with(18, mock_gpio.LOW)

        controller.disable_safety_relay()
        mock_gpio.output.assert_called_with(23, mock_gpio.LOW)

if __name__ == '__main__':
    unittest.main()
```

### 6.2 iOS App Testing

#### 6.2.1 Unit Tests

```swift
// KilnControllerV2Tests/ProfileTests.swift
import XCTest
@testable import KilnControllerV2

class ProfileTests: XCTestCase {
    func testProfileInterpolation() {
        let profile = Profile(
            name: "Test",
            tempUnits: "c",
            data: [[0, 25], [3600, 300]]
        )

        // Test midpoint
        let temp = profile.getTargetTemperature(at: 1800)
        XCTAssertEqual(temp, 162.5, accuracy: 0.1)

        // Test beyond last point
        let endTemp = profile.getTargetTemperature(at: 4000)
        XCTAssertEqual(endTemp, 0)
    }

    func testProfileDuration() {
        let profile = Profile(
            name: "Test",
            tempUnits: "c",
            data: [[0, 25], [7200, 600]]
        )

        XCTAssertEqual(profile.duration, 7200)
    }

    func testProfileCoding() {
        let profile = Profile(
            name: "Test Profile",
            tempUnits: "c",
            data: [[0, 25], [1800, 150]]
        )

        let encoder = JSONEncoder()
        let data = try! encoder.encode(profile)

        let decoder = JSONDecoder()
        let decoded = try! decoder.decode(Profile.self, from: data)

        XCTAssertEqual(profile.name, decoded.name)
        XCTAssertEqual(profile.tempUnits, decoded.tempUnits)
        XCTAssertEqual(profile.data, decoded.data)
    }
}
```

#### 6.2.2 ViewModel Tests

```swift
// KilnControllerV2Tests/DashboardViewModelTests.swift
import XCTest
import Combine
@testable import KilnControllerV2

class DashboardViewModelTests: XCTestCase {
    var viewModel: DashboardViewModel!
    var mockWebSocketService: MockWebSocketService!
    var mockControllerAPI: MockControllerAPI!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        mockWebSocketService = MockWebSocketService()
        mockControllerAPI = MockControllerAPI()
        viewModel = DashboardViewModel(
            webSocketService: mockWebSocketService,
            controllerAPI: mockControllerAPI
        )
        cancellables = Set<AnyCancellable>()
    }

    func testInitialState() {
        XCTAssertFalse(viewModel.isConnected)
        XCTAssertEqual(viewModel.currentState.state, .idle)
    }

    func testPauseWhenRunning() {
        viewModel.currentState = KilnState(
            cost: 0,
            runtime: 100,
            temperature: 200,
            target: 210,
            state: .running,
            heat: 1.0,
            heatRate: 150,
            totalTime: 3600,
            kwhRate: 0.25,
            currencyType: "€",
            profile: "Test",
            pidstats: nil,
            catchingUp: false
        )

        mockControllerAPI.pauseResult = Just(true)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()

        viewModel.pause()

        XCTAssertTrue(mockControllerAPI.pauseCalled)
    }

    func testPauseWhenIdle() {
        viewModel.currentState = .placeholder

        viewModel.pause()

        XCTAssertFalse(mockControllerAPI.pauseCalled)
    }
}

// Mock classes
class MockWebSocketService: WebSocketService {
    var pauseCalled = false
    var resumeCalled = false
    var stopCalled = false
}

class MockControllerAPI: ControllerAPI {
    var pauseCalled = false
    var resumeCalled = false
    var stopCalled = false

    var pauseResult: AnyPublisher<Bool, Error> = Just(false).setFailureType(to: Error.self).eraseToAnyPublisher()
    var resumeResult: AnyPublisher<Bool, Error> = Just(false).setFailureType(to: Error.self).eraseToAnyPublisher()
    var stopResult: AnyPublisher<Bool, Error> = Just(false).setFailureType(to: Error.self).eraseToAnyPublisher()

    override func pause() -> AnyPublisher<Bool, Error> {
        pauseCalled = true
        return pauseResult
    }

    override func resume() -> AnyPublisher<Bool, Error> {
        resumeCalled = true
        return resumeResult
    }

    override func stop() -> AnyPublisher<Bool, Error> {
        stopCalled = true
        return stopResult
    }
}
```

#### 6.2.3 UI Tests

```swift
// KilnControllerV2UITests/DashboardViewUITests.swift
import XCTest
@testable import KilnControllerV2

class DashboardViewUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testDashboardDisplays() {
        // Verify dashboard is displayed
        XCTAssertTrue(app.navigationBars["Kiln Controller"].exists)

        // Verify connection indicator
        XCTAssertTrue(app.staticTexts["Connected"].exists)
    }

    func testTemperatureDisplay() {
        // Wait for temperature data
        let temperatureLabel = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '°'")).firstMatch
        XCTAssertTrue(temperatureLabel.waitForExistence(timeout: 5))
    }

    func testQuickActions() {
        // Test pause button (when running)
        let pauseButton = app.buttons["Pause"]
        if pauseButton.exists {
            pauseButton.tap()
            XCTAssertTrue(app.buttons["Resume"].exists)
        }

        // Test stop button
        let stopButton = app.buttons["Stop"]
        if stopButton.exists {
            stopButton.tap()
            // Verify confirmation dialog
        }
    }

    func testProgramsNavigation() {
        // Tap programs tab
        app.tabBars.buttons["Programs"].tap()

        // Verify programs list
        XCTAssertTrue(app.tables.firstMatch.exists)

        // Test creating new profile
        app.navigationBars.buttons["plus"].tap()
        XCTAssertTrue(app.textFields["Name"].exists)
    }

    func testSettingsNavigation() {
        // Navigate to settings
        app.navigationBars.buttons["gearshape"].tap()

        // Verify settings screen
        XCTAssertTrue(app.navigationBars["Settings"].exists)

        // Test connection test
        app.buttons["Test Connection"].tap()
        // Wait for test result
    }
}
```

### 6.3 End-to-End Testing

#### 6.3.1 Complete Firing Cycle Test

```python
# tests/test_e2e.py
import unittest
import json
import time
import websocket
import requests

class TestEndToEnd(unittest.TestCase):
    def setUp(self):
        self.base_url = "http://192.168.178.120:8080"
        self.ws_url = "ws://192.168.178.120:8080"

        # Create test profile
        self.test_profile = {
            "type": "profile",
            "name": "E2E_Test_Profile",
            "temp_units": "c",
            "data": [[0, 25], [600, 100], [1200, 150], [1800, 100]]
        }

    def test_complete_firing_cycle(self):
        # 1. Connect to /status WebSocket
        ws = websocket.create_connection(f"{self.ws_url}/status")
        backlog = json.loads(ws.recv())
        self.assertEqual(backlog['type'], 'backlog')

        # 2. Save test profile via /storage
        storage_ws = websocket.create_connection(f"{self.ws_url}/storage")
        storage_ws.send(json.dumps({
            "cmd": "PUT",
            "profile": self.test_profile,
            "force": True
        }))
        response = json.loads(storage_ws.recv())
        self.assertEqual(response['resp'], 'OK')

        # 3. Start firing
        response = requests.post(
            f"{self.base_url}/api",
            json={"cmd": "run", "profile": "E2E_Test_Profile"}
        )
        self.assertTrue(response.json()['success'])

        # 4. Monitor state changes
        state_seen = {'IDLE', 'RUNNING'}
        timeout = time.time() + 30

        while time.time() < timeout:
            state_msg = json.loads(ws.recv())
            state = state_msg.get('state')

            if state == 'RUNNING':
                self.assertIn('profile', state_msg)
                self.assertEqual(state_msg['profile'], 'E2E_Test_Profile')
                break

        # 5. Pause
        response = requests.post(
            f"{self.base_url}/api",
            json={"cmd": "pause"}
        )
        self.assertTrue(response.json()['success'])

        # Verify paused state
        state_msg = json.loads(ws.recv())
        self.assertEqual(state_msg['state'], 'PAUSED')

        # 6. Resume
        response = requests.post(
            f"{self.base_url}/api",
            json={"cmd": "resume"}
        )
        self.assertTrue(response.json()['success'])

        # Verify running state
        state_msg = json.loads(ws.recv())
        self.assertEqual(state_msg['state'], 'RUNNING')

        # 7. Stop
        response = requests.post(
            f"{self.base_url}/api",
            json={"cmd": "stop"}
        )
        self.assertTrue(response.json()['success'])

        # Verify idle state
        state_msg = json.loads(ws.recv())
        self.assertEqual(state_msg['state'], 'IDLE')

        # Cleanup
        storage_ws.send(json.dumps({
            "cmd": "DELETE",
            "profile": {"name": "E2E_Test_Profile"}
        }))

        ws.close()
        storage_ws.close()

if __name__ == '__main__':
    unittest.main()
```

---

## 7. Timeline & Milestones

### 7.1 Development Phases

**Phase 1: Foundation (Weeks 1-2)**
- Set up development environment
- Implement basic Python backend structure
- Create iOS project with basic UI scaffolding
- Implement core data models
- Milestone: Running backend with basic API, iOS app with empty screens

**Phase 2: Backend Core (Weeks 3-4)**
- Implement Oven class with PID controller
- Implement TempSensor thread
- Implement OvenWatcher for state broadcasting
- Implement profile storage
- Implement REST API endpoints
- Implement WebSocket handlers
- Milestone: Functional backend with all communication channels

**Phase 3: Frontend Networking (Weeks 5-6)**
- Implement WebSocketService with 4 connections
- Implement ControllerAPI for REST calls
- Implement KeychainService
- Implement connection testing
- Implement error handling
- Milestone: iOS app can connect and communicate with backend

**Phase 4: Frontend UI (Weeks 7-8)**
- Implement DashboardView and components
- Implement ProgramsListView and editor
- Implement GraphView with temperature chart
- Implement SettingsView
- Implement State management
- Milestone: Complete iOS UI with all features

**Phase 5: Hardware Integration (Weeks 9-10)**
- Wire up Raspberry Pi hardware
- Implement MAX31855/56 driver
- Implement GPIO control for SSR and safety relay
- Implement lid switch monitoring
- Implement emergency shutdown
- Milestone: Hardware fully integrated and functional

**Phase 6: Testing & Refinement (Weeks 11-12)**
- Write unit tests for backend
- Write unit tests for iOS
- Write integration tests
- Perform end-to-end testing
- Fix bugs and refine UX
- Milestone: Tested, stable system

**Phase 7: Deployment (Weeks 13-14)**
- Set up Raspberry Pi as production device
- Configure systemd service
- Test iOS TestFlight distribution
- Prepare App Store submission
- Create documentation
- Milestone: Deployed system ready for use

### 7.2 Key Milestones

| Milestone | Date | Deliverables |
|-----------|------|--------------|
| M1: Foundation | Week 2 | Basic backend + iOS scaffold |
| M2: Backend Core | Week 4 | Full backend implementation |
| M3: Frontend Networking | Week 6 | iOS-backend communication |
| M4: Frontend UI | Week 8 | Complete iOS app UI |
| M5: Hardware Integration | Week 10 | Hardware fully functional |
| M6: Testing | Week 12 | Fully tested system |
| M7: Deployment | Week 14 | Production-ready system |

### 7.3 Risk Mitigation Timeline

| Risk | Mitigation | Timeline |
|------|------------|----------|
| Hardware compatibility | Test with actual hardware early | Week 9-10 |
| WebSocket reliability | Implement robust reconnect logic | Week 5-6 |
| iOS app store approval | Prepare documentation early | Week 13-14 |
| Temperature accuracy | Calibrate sensors thoroughly | Week 9-10 |
| Network issues | Implement offline handling | Week 11-12 |

---

## 8. Risk Assessment

### 8.1 Technical Risks

#### 8.1.1 Hardware Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Thermocouple failure | Medium | High | Implement error detection, redundancy, alerts |
| SSR failure | Low | Critical | Use quality components, implement safety relay |
| GPIO pin damage | Low | Medium | Use opto-isolation, current limiting |
| Power supply issues | Medium | High | Use UPS, voltage monitoring |
| Raspberry Pi overheating | Low | Medium | Adequate cooling, temperature monitoring |

#### 8.1.2 Software Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| WebSocket connection drops | High | Medium | Auto-reconnect, state sync on reconnect |
| PID tuning issues | Medium | High | Implement auto-tune, manual override |
| Profile data corruption | Low | High | Validation, backup, versioning |
| Memory leaks | Low | Medium | Regular testing, monitoring |
| Concurrency bugs | Medium | Medium | Proper threading, locks, testing |

#### 8.1.3 Network Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Network partition | Medium | Medium | Offline mode, state persistence |
| IP address changes | High | Low | Static IP, mDNS, user configuration |
| Port conflicts | Low | Medium | Configurable ports, error handling |
| Latency issues | Low | Low | Buffering, timeout handling |

### 8.2 Operational Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Overheating kiln | Low | Critical | Temperature limits, safety shutoff |
| Lid left open | Medium | High | Lid switch, auto-shutoff |
| Power loss | Medium | Medium | Automatic restart, state persistence |
| User error | High | Medium | Clear UI, confirmations, limits |
| Component wear | Medium | High | Maintenance alerts, lifecycle tracking |

### 8.3 Security Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Unauthorized access | Medium | High | Implement authentication (future) |
| Network snooping | Low | Medium | Use TLS (future) |
| Code injection | Low | Critical | Input validation, sanitization |
| Physical access | Low | Medium | Physical security, locked enclosure |

### 8.4 Project Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Timeline delays | Medium | Medium | Buffer time, phased delivery |
| Scope creep | High | Medium | Clear requirements, change control |
| Resource constraints | Low | High | Prioritize features, MVP approach |
| User adoption | Medium | High | User testing, feedback, documentation |

---

## 9. Future Enhancements

### 9.1 Backend Improvements

1. **Authentication:**
   - Add token-based authentication
   - Implement user management
   - Support multiple users with permissions

2. **Enhanced Safety:**
   - Multiple thermocouple support
   - Redundant temperature sensors
   - More sophisticated emergency detection

3. **Data Persistence:**
   - SQLite database for firing history
   - Firing logs and analytics
   - Trend analysis and reporting

4. **Advanced Features:**
   - PID auto-tuning
   - Multiple firing schedules
   - Delayed start
   - Notifications (email, SMS, push)

5. **API Improvements:**
   - RESTful API redesign
   - WebSocket multiplexing
   - GraphQL support

### 9.2 iOS App Improvements

1. **Enhanced UI:**
   - Dark mode support
   - Custom themes
   - Widget support
   - Apple Watch companion app

2. **Advanced Features:**
   - Offline mode with sync
   - Firing history and analytics
   - Push notifications
   - Siri shortcuts

3. **Social Features:**
   - Share profiles
   - Community profile library
   - Firing results sharing

4. **Integration:**
   - HomeKit integration
   - IFTTT support
   - Cloud backup

### 9.3 Hardware Upgrades

1. **Enhanced Sensors:**
   - Multiple thermocouples
   - Ambient temperature monitoring
   - Humidity sensing
   - Power consumption monitoring

2. **Improved Control:**
   - Multi-zone control
   - Advanced SSR with feedback
   - Ventilation control
   - Dampers and airflow control

3. **Safety Systems:**
   - Fire detection
   - Gas monitoring
   - Automatic suppression
   - Remote emergency stop

---

## 10. Conclusion

This implementation plan provides a comprehensive roadmap for building a complete kiln control system with:

- **Robust Python backend** running on Raspberry Pi 3 B with hardware control
- **Modern iOS SwiftUI frontend** with real-time monitoring and control
- **Reliable communication** via REST API and WebSockets
- **Comprehensive safety features** including emergency shutoff and lid switch
- **Thorough testing strategy** covering unit, integration, and end-to-end testing
- **Clear deployment process** for both backend and iOS app

The system is designed to be:
- **Safe**: Multiple safety layers, emergency shutdown, temperature monitoring
- **Reliable**: Robust error handling, automatic restart, state persistence
- **User-friendly**: Intuitive iOS app with clear feedback and controls
- **Extensible**: Modular architecture allowing future enhancements
- **Maintainable**: Clean code, comprehensive tests, detailed documentation

With this plan, the development team can proceed with confidence, knowing they have a clear path from initial implementation to production deployment.

---

## Appendix A: File Structure

### Python Backend

```
kiln-controller/
├── kiln-controller.py          # Main entry point
├── config.py                   # Configuration
├── requirements.txt            # Python dependencies
├── lib/
│   ├── __init__.py
│   ├── oven.py                 # Oven core & PID
│   ├── ovenWatcher.py          # State broadcaster
│   ├── tempSensor.py           # Temperature reading
│   └── hardware.py             # GPIO & hardware control
├── storage/
│   ├── profiles/               # Firing profiles (*.json)
│   └── state.json              # Restart state
├── public/                     # Web UI assets (optional)
├── tests/
│   ├── test_oven.py
│   ├── test_integration.py
│   └── test_hardware.py
└── scripts/
    ├── install.sh              # Installation script
    └── update.sh               # Update script
```

### iOS App

```
KilnControllerV2/
├── KilnControllerApp.swift
├── AppDelegate.swift
├── SceneDelegate.swift
├── Models/
│   ├── Profile.swift
│   ├── KilnState.swift
│   ├── PIDStats.swift
│   ├── ControllerConfig.swift
│   └── BacklogMessage.swift
├── ViewModels/
│   ├── DashboardViewModel.swift
│   ├── ProgramsViewModel.swift
│   ├── ProgramEditorViewModel.swift
│   ├── GraphViewModel.swift
│   └── SettingsViewModel.swift
├── Views/
│   ├── Dashboard/
│   │   ├── DashboardView.swift
│   │   ├── StatusCardView.swift
│   │   ├── TemperatureGaugeView.swift
│   │   └── QuickActionsView.swift
│   ├── Programs/
│   │   ├── ProgramsListView.swift
│   │   ├── ProgramEditorView.swift
│   │   └── ProgramCardView.swift
│   ├── Graph/
│   │   └── GraphView.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   └── ConnectionSetupView.swift
│   └── Components/
│       ├── TempDisplay.swift
│       ├── ConnectionIndicator.swift
│       └── LoadingOverlay.swift
├── Services/
│   ├── WebSocketService.swift
│   ├── ControllerAPI.swift
│   └── KeychainService.swift
├── Utilities/
│   ├── TemperatureFormatter.swift
│   ├── Extensions.swift
│   └── HapticsManager.swift
├── Resources/
│   └── Assets.xcassets
└── Tests/
    ├── KilnControllerV2Tests/
    └── KilnControllerV2UITests/
```

---

## Appendix B: Quick Start Guide

### Raspberry Pi Setup

```bash
# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Install dependencies
sudo apt install -y python3 python3-pip python3-venv git
sudo apt install -y python3-dev libgpiod-dev

# 3. Enable SPI
sudo raspi-config nonint do_spi 0

# 4. Create project
cd ~
mkdir kiln-controller && cd kiln-controller
python3 -m venv venv
source venv/bin/activate

# 5. Install packages
pip install bottle gevent gevent-websocket RPi.GPIO spidev

# 6. Create directories
mkdir -p lib storage/profiles public

# 7. Copy source files
# (Copy all files from this plan)

# 8. Test run
python3 kiln-controller.py

# 9. Install as service
sudo cp scripts/kiln-controller.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kiln-controller
sudo systemctl start kiln-controller
```

### iOS App Development

```bash
# 1. Create Xcode project
# File → New → Project → iOS → App
# Name: KilnControllerV2
# Interface: SwiftUI
# Language: Swift

# 2. Add files
# Copy all files from this plan into the project

# 3. Configure capabilities
# - Add Local Network capability
# - Set deployment target to iOS 16.0

# 4. Build and run
# Product → Run (⌘R)
```

---

## Appendix C: Troubleshooting

### Common Issues

**Backend won't start:**
```bash
# Check logs
sudo journalctl -u kiln-controller -f

# Check port availability
sudo netstat -tlnp | grep 8080

# Test manually
cd ~/kiln-controller
source venv/bin/activate
python3 kiln-controller.py
```

**Temperature reading errors:**
```bash
# Check SPI connection
ls /dev/spidev*

# Test MAX31855/56
python3 -c "
import spidev
spi = spidev.SpiDev()
spi.open(0, 0)
print(spi.readbytes(4))
"
```

**iOS app can't connect:**
- Verify Raspberry Pi is on network
- Check IP address is correct
- Ensure no firewall blocking port 8080
- Test with browser: http://192.168.178.120:8080

**WebSocket disconnects:**
- Check network stability
- Verify gevent-websocket is installed
- Check server logs for errors

**SSR not switching:**
- Verify GPIO wiring
- Check GPIO permissions
- Test with: `gpio -g read 18`

---

## Appendix D: Configuration Examples

### Example Profiles

**Bisque Fire:**
```json
{
  "type": "profile",
  "name": "Bisque",
  "temp_units": "c",
  "data": [
    [0, 25],
    [3600, 300],
    [7200, 600],
    [10800, 900],
    [14400, 1000],
    [18000, 1050],
    [21600, 1080]
  ]
}
```

**Glaze Fire:**
```json
{
  "type": "profile",
  "name": "Glaze",
  "temp_units": "c",
  "data": [
    [0, 25],
    [3600, 500],
    [7200, 900],
    [10800, 1200],
    [12600, 1250],
    [14400, 1250],
    [16200, 800]
  ]
}
```

**Test Ramp:**
```json
{
  "type": "profile",
  "name": "Test_Ramp",
  "temp_units": "c",
  "data": [
    [0, 25],
    [600, 100],
    [1200, 150],
    [1800, 100]
  ]
}
```

---

**END OF IMPLEMENTATION PLAN**