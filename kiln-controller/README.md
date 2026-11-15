# Kiln Controller — Python Backend

Bottle + gevent server that runs on a Raspberry Pi (the "Oven") and drives a
kiln through an SSR and a hardware safety relay, using a MAX31855/56 K-type
thermocouple for feedback. Provides REST + WebSocket APIs consumed by the
[KilnApp iOS app](../KilnApp) and any browser client.

Wire protocol reference: [`../api.md`](../api.md)

## Features

- **PID temperature control** with time-slice duty cycling of the SSR
  (configurable window, max on-time, max duty %).
- **EMI-safe temperature sampling** — the thermocouple is *only* read in
  the quiet window: each duty cycle switches the SSR off, waits
  `temp_settle_time` (0.5 s) for switching EMI to dissipate, reads the
  MAX31856, and only then energises the elements. The settle time is
  reserved out of the SSR's maximum on-time (`_calc_on_time()`) so a
  heating burst can never crowd out the next read. This is essential at
  high temperatures, where the air around the elements ionizes and
  becomes conductive, skewing SPI thermocouple measurements — a falsely
  low mid-heat sample would make the PID over-drive an already-hot kiln.
  Sensor read failures fall back to the last known good temperature,
  log a `sensor_retry` event, and abort after repeated failures instead
  of heating blind.
- **Firing profiles** — `[seconds, °C]` ramps/soaks stored as JSON in
  `storage/profiles/`; seek-start (jump to where the kiln already is) and
  catch-up after restarts.
- **Safety interlocks** (all aborts cut the safety relay):
  - Over-temperature emergency shutoff (default 1300 °C)
  - Excessive thermocouple error rate (default 30 %)
  - **Heating stall**: ≥90 % duty for the stall window (600 s) with <2 °C
    rise ⇒ element/SSR/thermocouple fault. The window starts when the PID
    first saturates, not at a fixed runtime.
  - Lid switch input
- **Session logging** — JSONL per firing in `storage/sessions/`
  (`meta` / `sample` / `event` / `end` lines), events include run, pause,
  resume, completed, abort(reason), heating_stalled, sensor_retry. Dangling
  sessions are finalised on startup.
- **Cost tracking** — kWh rate × element rating accumulates per firing.
- **Alerting** (optional) — email/SMS on completion/abort via `lib/alerting.py`.
- **Automatic restarts** — after a crash/reboot the controller can resume a
  firing within a configurable window.

## Layout

```
kiln-controller/
├── kiln-controller.py   Bottle app: REST routes, WebSockets, Controller class
├── config.py            Config loader (config.json)
├── config.json          All runtime settings (pins, PID, safety, tariffs…)
├── lib/
│   ├── oven.py          Oven thread: PID, control cycle, stall detection,
│   │                    safety checks, abort_run(), session events, state
│   ├── ovenWatcher.py   Polls the oven, drains events, broadcasts state,
│   │                    writes session logs (session_logger)
│   ├── sessionlog.py    JSONL session writer / finalise dangling sessions
│   ├── tempSensor.py    Sensor abstraction with retry/error-rate tracking
│   ├── max31855.py / max31856.py  SPI thermocouple drivers
│   ├── hardware.py      GPIO: SSR, safety relay, lid switch
│   └── alerting.py      Email/SMS alert manager
├── public/              Static web UI files
├── storage/
│   ├── profiles/        Firing profiles (JSON)
│   ├── sessions/        Session logs (JSONL)
│   └── state.json       Persisted oven state for restart/recovery
├── scripts/             install.sh, systemd unit, API smoke test
├── deploy/              Hardened systemd unit + Pi watchdog setup guide
└── tests/               Safety & session-log test suites
```

## Installation

See [QUICK_START.md](QUICK_START.md) for the full guide. Short version:

```bash
sudo apt install -y python3-venv libgpiod-dev
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
# Enable SPI (raspi-config) — required for the thermocouple — then:
python3 kiln-controller.py
```

Production (systemd, starts on boot, restarts on crash):

```bash
sudo cp scripts/kiln-controller.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now kiln-controller
```

Recommended extra: enable the BCM hardware watchdog so a hung Pi reboots
instead of leaving the SSR energised — see [deploy/README.md](deploy/README.md).

## Configuration

Everything lives in `config.json` (hot-editable via `GET/POST /api/config`
or the app's Settings tab). Highlights:

| Section | Key settings |
|---|---|
| `hardware` | SPI bus/device, sensor type, GPIO pins (SSR, safety relay, lid switch), element kW |
| `pid` | kp/ki/kd, control window, duty cycle, max SSR on-time & % |
| `safety` | emergency shutoff temp, max thermocouple error rate |
| `display` | °C/°F, kWh rate & currency for cost display |
| `restart` | automatic restarts, window, seek-start |
| `alerting` | email/SMS credentials & recipients |

Profile format (`storage/profiles/Name.json`):

```json
{
  "type": "profile", "name": "Example_Bisque", "temp_units": "c",
  "data": [[0, 25], [3600, 100], [7200, 200], [14400, 600],
           [21600, 960], [32400, 1050], [36000, 1050], [39600, 100], [43200, 25]]
}
```

## API summary

- `POST /api` — commands: `run` (profile, startat), `pause`, `resume`,
  `stop`, `memo`, `stats`
- `GET /api/stats` — PID stats while firing
- `GET|POST /api/config` — read/update config. All `pid.*` values
  (kp/ki/kd, control_window, duty_cycle) **hot-reload** into a running
  firing on the next duty cycle; `hardware.*` requires a restart.
  `pid.duty_cycle` is validated: minimum `temp_settle_time + 1s` so the
  quiet-period temperature read is never crowded out.
- `POST /api/system/restart` — restarts the systemd service (used by the
  app's *Restart Server* button to apply hardware changes). Requires a
  sudoers rule, see `deploy/README.md`. Refuses while a firing is active.
- `GET /api/sessions`, `GET /api/sessions/<id>`, `DELETE /api/sessions/<id>` — history
- WebSockets: `/status` (live state + backlog), `/control` (commands),
  `/storage` (profile CRUD), `/config` (config push)

Full details, payloads and known quirks: [`../api.md`](../api.md).

## Tests

```bash
source ../.venv/bin/activate        # any venv with the requirements works
python tests/test_oven_safety.py    # 15 tests: aborts, stall detection, session events
python tests/test_sessionlog.py     # JSONL logging & dangling-session finalisation
python scripts/test_api.py          # live API smoke test (needs running server)
```

## Safety notes

- The safety relay is the hard cutout: every abort path (`abort_run()`)
  drops it and resets runtime/profile/cost.
- After any abort, check the session log's `abort` event for the reason
  (e.g. "full power for 602s but temperature rose only -17.2° — element,
  SSR or thermocouple suspect") before re-firing.
- Only restart the service when no firing is running.
- This software is a hobby project: keep independent over-temperature
  protection on the kiln itself.
