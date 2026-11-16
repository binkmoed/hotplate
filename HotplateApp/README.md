# HotplateApp — iOS Controller App

Native SwiftUI app for iPhone that monitors and controls the Hotplate
Raspberry Pi controller over the local network (HTTP + WebSocket, port 8080).
Companion backend: [`../hotplate-controller`](../hotplate-controller) — see
[`../api.md`](../api.md) for the wire protocol.

## Features

- **Live dashboard** — current temperature, target, PID info, runtime, cost,
  state badge (idle / running / paused), live temperature chart drawn against
  the firing profile schedule, animated flame 🔥 while firing.
- **Firing control** — start a profile (optionally seeking to the current
  temperature), pause/resume, stop with confirmation, and automatic
  **"Firing Completed"** / **"Firing Aborted"** alerts (with abort reason
  pulled from the session log; user-initiated stops stay silent).
- **Profile editor** — create/edit firing profiles as `[time, temperature]`
  segments with an auto-scaling chart (peak ×1.25 headroom, 1500 °C ceiling).
- **History** — past sessions rendered from JSONL logs: temperature curve,
  event list with real clock timestamps + muted runtime offsets, outcome
  (completed / aborted), peak temperature and energy cost.
- **Settings** — view and update the controller config (PID, safety limits,
  tariffs, display units) from the phone.
- **Connection management** — server address saved (credentials in Keychain),
  reconnect, offline indicator.

## Requirements

- Xcode 15+ / iOS 17+
- iPhone on the same WiFi as the Pi controller
- The [hotplate-controller](../hotplate-controller) running and reachable

## Building

Open `HotplateApp.xcodeproj` in Xcode and run on a device, or from the CLI:

```bash
cd HotplateApp
xcodebuild -scheme HotplateApp -destination 'id=<UDID>' build

# Install on device
xcrun devicectl device install app --device <UDID> \
  <DerivedData>/Build/Products/Debug-iphoneos/HotplateApp.app
```

The project file is generated from `project.yml` (XcodeGen) but the
`.xcodeproj` is committed, so XcodeGen is only needed after adding files.

## Source layout

```
HotplateApp/
├── App/            HotplateAppApp.swift — entry point, HotplateClient environment
├── Models/
│   ├── HotplateStatus.swift     Live status/state types
│   ├── Profile.swift        Firing profile model ([time, °C] points)
│   ├── SessionModels.swift  Session log JSONL models (meta/sample/event/end)
│   └── Messages.swift       WebSocket message decoding
├── Networking/
│   ├── HotplateClient.swift     @Observable client: state, commands, alerts
│   ├── WebSocketService.swift  Persistent /status /control /storage /config sockets
│   ├── ControllerAPI.swift  REST endpoints (sessions, config, history)
│   └── KeychainStore.swift  Credential storage
├── Components/     ProfileChart, TemperatureChart (Swift Charts)
├── Views/
│   ├── RootView.swift            Connection gate
│   ├── ConnectionSetupView.swift Enter/scan server address
│   ├── MainTabView.swift         Tab container
│   ├── DashboardView.swift       Live firing view + controls
│   ├── ProfileListView.swift     Profile CRUD
│   ├── ProfileEditorView.swift   Segment editor + live chart
│   ├── HistoryView.swift         Past sessions, events, outcomes
│   └── SettingsView.swift        Controller config editor
└── Support/        Format.swift, Logger.swift, NotificationManager.swift
```

## Architecture notes

- **`HotplateClient`** (`@Observable`) is the single source of truth, injected via
  `.environment()`. It owns the WebSocket service and exposes commands
  (`run`, `pause`, `resume`, `stop`), config updates, profile CRUD and the
  alert state (`completedFiring`, `abortedFiring`/`abortReason`).
- **Live updates** arrive on the `/status` WebSocket; a backlog message
  backfills the session history when connecting mid-firing. Chart history
  drops non-monotonic runtime samples so old logs render cleanly.
- **Completion detection**: when the oven transitions to IDLE with an
  outcome, the client raises the appropriate alert and records it; the flag
  `userStoppedFiring` distinguishes user stops from safety aborts.
- No cloud: everything stays on the LAN. Local notifications are used for
  firing-completed alerts.

## User guide

See [`../docs/USER_MANUAL.md`](../docs/USER_MANUAL.md) for end-user
documentation (day-in-the-life firing walkthrough).
