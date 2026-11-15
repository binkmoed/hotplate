# BinkKiln

A WiFi kiln controller for a small glass/kiln studio: a Raspberry Pi drives the
elements through an SSR + safety relay, and a native SwiftUI iOS app monitors
and controls firings over the local network.

```
┌─────────────┐  HTTP + WebSocket (LAN)  ┌──────────────────────┐  GPIO  ┌────────────┐
│  KilnApp    │◄────────────────────────►│ kiln-controller (Pi) │───────►│ SSR/Relay  │──► Elements
│  SwiftUI    │      :8080               │ Bottle + gevent      │        └────────────┘
└─────────────┘                          │ MAX31856 K-type TC   │◄── Thermocouple
                                         └──────────────────────┘
```

## Components

| Directory | What it is |
|---|---|
| `kiln-controller/` | Python backend (Bottle + gevent) running on the Raspberry Pi. PID control, safety interlocks, session logging, profile storage, REST + WebSocket API. Entry point: `kiln-controller.py`, libs in `lib/`. |
| `KilnApp/` | SwiftUI iOS app: live dashboard with temperature chart, profile editor, firing history, settings. Talks to the controller via WebSockets. |
| `api.md` | Full API reference (REST routes, WebSocket channels, data models). |

**Documentation**

- 📱 **iOS app**: [`KilnApp/README.md`](KilnApp/README.md) — features, build steps, source layout, architecture.
- 🖥️ **Server**: [`kiln-controller/README.md`](kiln-controller/README.md) — features, install, config, API summary, safety notes.
- 📖 **User manual**: [`docs/USER_MANUAL.md`](docs/USER_MANUAL.md) — end-user guide to running firings.
- 🔌 **API reference**: [`api.md`](api.md) — REST routes, WebSocket channels, data models.

## What's new (Nov 2026)

- **In-app server restart** — `POST /api/system/restart` + *Restart Server*
  button in the app (Settings → Server) with running/restarting/stopped
  status. Needs the sudoers rule in [`kiln-controller/deploy/README.md`](kiln-controller/deploy/README.md).
- **Full-length charts** — live dashboard and history now show the entire
  firing curve (the old client capped at one hour of samples); the server
  refuses to log non-monotonic samples that truncated history charts.
- **Settings hot-reload** — kp/ki/kd, control window and duty cycle apply
  to a running firing on the next duty cycle; no restart, no schedule reset.
  Duty cycle is validated to a minimum of `temp_settle_time + 1s`.
- **Single profile prompt** — the Start Firing sheet confirms the profile
  chosen on the dashboard instead of asking again.
- **Crash fix** — auto-restart after an unclean shutdown no longer fails
  starting the watcher thread twice; each duty cycle no longer wastes a
  duplicate temperature-settle sleep.

## Quick start (controller)

```bash
# On the Raspberry Pi (Bookworm, SPI enabled)
sudo apt install -y python3-venv libgpiod-dev
python3 -m venv venv && source venv/bin/activate
pip install -r kiln-controller/requirements.txt
python3 kiln-controller/kiln-controller.py
```

For production, install as a systemd service:

```bash
sudo cp kiln-controller/scripts/kiln-controller.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now kiln-controller
```

See [kiln-controller/QUICK_START.md](kiln-controller/QUICK_START.md) for the
guided install and [kiln-controller/deploy/README.md](kiln-controller/deploy/README.md)
for deployment + hardware-watchdog setup.

## Quick start (iOS app)

1. Open `KilnApp/` in Xcode (project generated via `project.yml` / XcodeGen, but
   the `.xcodeproj` is committed).
2. Build & run on a device on the same WiFi as the Pi.
3. In the app's connection screen, enter the Pi's address (default port 8080).

Command-line build:

```bash
cd KilnApp
xcodebuild -scheme KilnApp -destination 'id=<UDID>' build
xcrun devicectl device install app --device <UDID> <path-to-DerivedData>/Debug-iphoneos/Kiln.app
```

## Configuration

All runtime config lives in `kiln-controller/config.json` (also editable from
the app's Settings tab): hardware pins, thermocouple type, PID parameters,
safety limits (emergency shutoff temp, max sensor error rate), tariffs for
cost tracking, alerting (email/SMS), and restart behaviour. A firing profile
is a list of `[seconds, °C]` points stored in `storage/profiles/*.json`.

## Safety design

- **SSR + hardware safety relay**: every abort drops the safety relay, cutting
  element power independently of the SSR.
- **Abort conditions**: over-temperature (default 1300 °C), excessive
  thermocouple error rate, **heating stall** (PID ≥90 % duty for the stall
  window — 600 s — with less than 2 °C rise ⇒ element/SSR/thermocouple fault),
  lid switch, controller restart while firing.
- **Heating history**: every firing is logged as JSONL in `storage/sessions/`
  (samples + events + outcome), with dangling sessions finalised on startup.
- **Hardware watchdog**: BCM watchdog reboots the Pi if the process is killed
  while the SSR is energised; systemd restarts the controller, whose GPIO init
  drives SSR/relay pins LOW. See `kiln-controller/deploy/README.md`.

## Tests

```bash
cd kiln-controller
source ../.venv/bin/activate   # or any venv with the requirements
python tests/test_oven_safety.py   # 15 tests: aborts, stall detection, session logs
python tests/test_sessionlog.py
```

## Repository layout (extras)

- `spec.md` / `plan.md` / `IMPLEMENTATION_PLAN.md` — original design notes.
- `ESP32_FEASIBILITY.md` — notes on a possible ESP32 port.
