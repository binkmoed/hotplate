# Kiln Controller — Specification (`spec.md`)

This document describes the **actual** behaviour of a kiln controller. It is the source of truth
for building a new iOS front-end. The authoritative wire-protocol reference is
`api.md`; this document explains the concepts, data model, and state machine.

## 1. Overview

A Raspberry Pi runs `kiln-controller.py`, a single-process Bottle + gevent
server. It:

- Reads a thermocouple (MAX31855 / MAX31856 ) every duty cycle
  (`config.sensor_time_wait`, default 3 s).
- Runs a PID controller (`lib/oven.py::PID`) to decide the SSR on-fraction
  for each duty cycle.
- When firing is started it Drives a Safety SSR relay to bring power to the Main SSR.
- Safety SSR has Normally closed lid switch in series with the driving signal. If Lid is opened firing is stopped and signal dropped to safety SSR.
- When Firing is active Main SSR drives heating elements. 
- Tracks runtime, actual and target temperature, cost, heat rate, and PID stats.
- Serves a web UI and a small HTTP/WebSocket API on `0.0.0.0:8080`.
- Persists firing profiles as JSON files in `storage/profiles/`.
- Writes a restart state file (`state.json`) every duty cycle for power-loss
  recovery.
- Runs an `OvenWatcher` thread that pushes state to all WebSocket observers.

There is **no database**. Profiles and restart state are flat JSON files.
There is **no authentication** and **no TLS** by default (open LAN service).

### Processes / components

| Component | File | Role |
|---|---|---|
| HTTP + WS server | `kiln-controller.py` | Serves static UI, REST `/api`, four WebSockets |
| Oven core | `lib/oven.py` | PID, profile interpolation, SSR timing, state machine |
| State broadcaster | `lib/ovenWatcher.py` | Pushes state to `/status` observers; keeps a backlog |
| Config | `config.py` | All tunables: hardware pins, PID, scales, limits |
| Watchdog (optional) | `watcher.py` | External script polling `/api/stats`, alerts Slack |
| Loggers (optional) | `kiln-logger.py`, `kiln-logger-period.py` | WebSocket loggers → CSV |
| Tuner (optional) | `kiln-tuner.py` | Step-response PID autotune |
| systemd | `lib/init/kiln-controller.service` | Auto-start on boot |

### Threading model

- `Oven` (real or simulated) is a `threading.Thread` running the control loop.
- `OvenWatcher` is a `threading.Thread` polling `oven.get_state()` every
  `sensor_time_wait` and pushing to observers.
- `TempSensor` (real) is a `threading.Thread` sampling the thermocouple.
- Bottle/gevent handles HTTP and WebSockets on a greenlet pool.

A single global `oven` instance and a single `ovenWatcher` instance are created
at startup.

---

## 2. Firing profile model

A profile is a JSON object stored as `storage/profiles/<name>.json`:

```json
{
  "type": "profile",
  "name": "Bisque",
  "temp_units": "c",
  "data": [
    [0, 25],
    [3600, 300],
    [7200, 600],
    [19800, 1220]
  ]
}
```

- `data` is an array of `[time_seconds, temperature]` points, sorted ascending
  by time. The controller interpolates linearly between consecutive points to
  find the target temperature at any `runtime`.
- `temp_units` is `"c"` (Celsius) or `"f"` (Fahrenheit). Profiles are stored in
  °C internally; the server converts to the configured `temp_scale` for
  display when serving (one-way only today — see issues).
- `type` is always `"profile"` (legacy field).
- Duration of the profile = `max(time)` across all points (seconds).

The **only** profile representation over the wire is this point-list format.
There is no "segment with rate + hold" model. The iOS app must edit/store
profiles in this exact `[[seconds, temp], ...]` form.

### Interpolation

`Profile.get_target_temperature(time)`:
- If `time` is beyond the last point → returns `0` (and `reset_if_schedule_ended`
  ends the run).
- Otherwise linearly interpolates between the two surrounding points.

### Seek-start behaviour

When starting a profile and `config.seek_start == True` and the kiln is already
hotter than the first point + 5°, the controller advances the schedule start to
the time whose target temperature matches the current temperature
(`get_start_from_temperature`). This is suppressed when `startat > 0` and on
automatic restarts. (Note: bug 1.2 currently loses this offset after one
cycle — to be fixed.)

---

## 3. Controller state machine

States are uppercase strings: `IDLE`, `RUNNING`, `PAUSED`.
(The source defines no `COMPLETE`/`ERROR`; the run simply returns to `IDLE`.)

```
                 run_profile()
        ┌────────────────────────► RUNNING
 IDLE ──┤                            │
        │  automatic_restart()       │ pause
        │  (on boot if state.json    ▼
        │   says RUNNING & fresh)   PAUSED
        │                            │
        └────────────────────────────┘ resume
                     ▲   │
                     │   │ stop / abort_run()
                     │   │ schedule ended
                     │   │ emergency (temp too high / TC errors)
                     └───┘
```

- `run_profile(profile, startat=minutes, allow_seek=bool)` sets state `RUNNING`.
- `abort_run()` (stop / emergency / schedule end) calls `reset()` → state `IDLE`
  and writes `state.json`.
- `pause`/`resume` directly set the state string (no guards today — bug 1.4).

### What happens each duty cycle while RUNNING

1. `update_cost()` — add power cost for this cycle.
2. `save_automatic_restart_state()` — write `state.json`.
3. `kiln_must_catch_up()` — if actual temp is outside `pid_control_window` of
   target, shift `start_time` so the schedule waits (prevents the profile
   running away while the kiln can't keep up). Sets `catching_up`.
4. `update_runtime()` — `runtime = now - start_time`.
5. `update_target_temp()` — interpolate profile at `runtime`.
6. `heat_then_cool()` — compute PID, energise SSR for `heat_on` seconds, then
   cool for the rest of `sensor_time_wait`.
7. `reset_if_emergency()` — abort on over-temp or excessive TC errors.
8. `reset_if_schedule_ended()` — abort when `runtime > totaltime`.

### Emergency conditions

- Current temp ≥ `emergency_shutoff_temp` (unless `ignore_temp_too_high`).
- Thermocouple error rate > `limit` (30 %) over the sample window (unless
  `ignore_tc_too_many_errors`).
- Individual thermocouple faults can each be ignored via `config.ignore_tc_*`.

---

## 4. Configuration (`config.py`)

Key values the iOS app should know about (read via `/config` WebSocket):

| Config key | Default | Meaning |
|---|---|---|
| `temp_scale` | `"c"` | Display unit: `"c"` or `"f"` |
| `time_scale_slope` | `"h"` | Slope display unit: s/m/h |
| `time_scale_profile` | `"m"` | Profile time display unit: s/m/h |
| `kwh_rate` | `0.25` | Energy price per kWh |
| `currency_type` | `"€"` | Currency symbol |
| `kw_elements` | `7.1` | Element power in kW (NOT currently sent over `/config`; the UI hardcodes 3850 W — bug 3.1) |
| `pid_kp`/`pid_ki`/`pid_kd` | 3/75/12 | PID gains (in pidstats, not `/config`) |
| `emergency_shutoff_temp` | 2264 | Safety limit (scale bug — issue 1.3) |
| `sensor_time_wait` | 3 | Duty cycle seconds; also the state push interval |
| `max_ssr_on_time` | 6 | Cap on SSR on-time per cycle |

`/config` currently returns only `temp_scale`, `time_scale_slope`,
`time_scale_profile`, `kwh_rate`, `currency_type`. PID gains and limits are
**not** exposed via the API (only inside each `/status` message's `pidstats`).

---

## 5. Networking — protocol summary

(See `api.md` for the full, exact reference.)

### 5.1 REST

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` | Redirect → `/flow/index.html` |
| `GET` | `/state` | Redirect → `/flow/state.html` |
| `GET` | `/flow/<file>` | Static UI assets |
| `POST` | `/api` | Command endpoint: `run`, `pause`, `resume`, `stop`, `memo`, `stats` |
| `GET` | `/api/stats` | Current PID stats (empty when idle) |

### 5.2 WebSockets (four independent sockets)

| Path | Direction | Content |
|---|---|---|
| `/status` | server→client push | `backlog` message on connect, then a state dict every `sensor_time_wait` |
| `/control` | client→server | `{"cmd":"RUN","profile":{...}}`, `{"cmd":"STOP"}`, `{"cmd":"SIMULATE",...}` |
| `/storage` | bidirectional | `GET` (string), `{"cmd":"DELETE","profile":{...}}`, `{"cmd":"PUT","profile":{...},"force":bool}` |
| `/config` | server→client push | config JSON on each received message (client sends `"GET"` to trigger) |

Important protocol notes for the iOS app:
- There is **no single multiplexed socket** and **no `subscribe` handshake**.
  Open four sockets.
- The `/status` socket receives JSON objects. The first is `{"type":"backlog",...}`;
  subsequent ones are the live `get_state()` dict (no `type` field).
- The server never sends an acknowledgement to `/control` `RUN`/`STOP`. The app
  learns success from the next `/status` message's `state`.
- `/storage` responses are loose: a `DELETE`/`PUT` echoes the request back with
  a `resp` field (`"OK"`/`"FAIL"`); a `GET` (string) returns the profile array.
- All messages are JSON text frames (no binary).

---

## 6. State object (`get_state()`)

Pushed on `/status` every `sensor_time_wait` (3 s). Field types observed from
`Oven.get_state()`:

```jsonc
{
  "cost": 1.23,                 // running energy cost, currency from /config
  "runtime": 1234.0,             // seconds since profile start
  "temperature": 612.5,         // current oven temp (in temp_scale), incl. offset
  "target": 620.0,              // current profile target temp
  "state": "RUNNING",            // "IDLE" | "RUNNING" | "PAUSED"
  "heat": 1.0,                  // SSR indicator: 0.0 off / 1.0 on (real); on-seconds (sim)
  "heat_rate": 150.0,           // degrees per hour (NOTE: bug 2.5 side-effect)
  "totaltime": 19800.0,         // profile duration in seconds
  "kwh_rate": 0.25,             // echoed from config
  "currency_type": "€",
  "profile": "Bisque",          // profile name or null
  "pidstats": {                 // see §7
    "time": 1719400000,
    "timeDelta": 3.0,
    "setpoint": 620.0,
    "ispoint": 612.5,
    "err": 7.5,
    "errDelta": ...,
    "p": ..., "i": ..., "d": ...,
    "kp": 3, "ki": 75, "kd": 12,
    "pid": ...,                 // raw (pre-normalise) output
    "out": 0.45                 // normalised 0..1 SSR fraction
  },
  "catching_up": false          // true when schedule is held waiting for temp
}
```

Fields the front-end reads but the server **never** sends: `cool`, `air`,
`door` (bug 1.5). `hazard` is derived client-side from temperature.

### Backlog message (first `/status` frame)

```jsonc
{
  "type": "backlog",
  "profile": { "name": "Bisque", "data": [[0,25],...], "type": "profile" },  // or null
  "log": [ <state>, <state>, ... ]   // down-sampled to ~50 points
}
```

---

## 7. PID stats (`pidstats`)

Populated only after the first `PID.compute()`. When idle just after `reset()`,
`pidstats == {}` (empty). Fields:

| Field | Meaning |
|---|---|
| `time` | Unix timestamp of the compute |
| `timeDelta` | Seconds since previous compute |
| `setpoint` | Target temperature at compute time |
| `ispoint` | Measured temperature |
| `err` | `setpoint - ispoint` |
| `errDelta` | `err - lastErr` |
| `p`,`i`,`d` | P/I/D output components (`kp*err`, `iterm`, `kd*dErr`) |
| `kp`,`ki`,`kd` | Current gains |
| `pid` | Raw combined output before normalisation (windowed to ±100) |
| `out` | Normalised output, 0..1 (SSR on-fraction) |

`GET /api/stats` returns this same `pidstats` object (as a JSON string) when a
PID exists; otherwise empty.

---

## 8. Profile storage operations

All over the `/storage` WebSocket:

- **List:** send the string `GET`. Server replies with a JSON array of all
  profile objects (already unit-converted for display).
- **Save/overwrite:** send `{"cmd":"PUT","profile":{...},"force":false}`. If a
  profile with that name exists and `force` is false, server replies
  `{"...,"resp":"FAIL"}`; the client re-sends with `"force":true` to overwrite.
  On success server replies `resp:"OK"` then immediately the full profile list.
- **Delete:** send `{"cmd":"DELETE","profile":{"name":"Bisque"}}`. Server
  replies with the same object plus `resp:"OK"`/`"FAIL"`.

Profile names become filenames (`<name>.json`); names must be filesystem-safe
(path-traversal bug 1.9 — to be fixed server-side; the app should still send
safe names).

---

## 9. Control commands

Via REST `POST /api` (body `{"cmd":...}`) **or** the `/control` WebSocket:

| cmd | REST body | WS body | Effect |
|---|---|---|---|
| run | `{"cmd":"run","profile":"Bisque","startat":0}` | `{"cmd":"RUN","profile":{...}}` | Start/resume a profile |
| stop | `{"cmd":"stop"}` | `{"cmd":"STOP"}` | Abort the run → IDLE |
| pause | `{"cmd":"pause"}` | — | Set state PAUSED (REST only) |
| resume | `{"cmd":"resume"}` | — | Set state RUNNING (REST only) |
| memo | `{"cmd":"memo","memo":"text"}` | — | Logs a message only |
| stats | `{"cmd":"stats"}` (POST) | — | Returns pidstats |
| SIMULATE | — | `{"cmd":"SIMULATE",...}` | No-op (commented out in server) |

Notes:
- REST `run` takes the **profile name**; WS `RUN` takes the **full profile
  object**. The iOS app should prefer the REST `run` (simpler) but must support
  `startat` for skip-ahead/restart.
- `pause`/`resume` are **REST-only** on the real backend.

---

## 10. Automatic restart

If `config.automatic_restarts == True`:
- Every duty cycle the oven writes `state.json` (in the script directory) with
  the current `get_state()` output.
- On boot, if `state.json` exists, is younger than `automatic_restart_window`
  minutes (default 15), and its `state` was `RUNNING`, the oven reloads the
  named profile and resumes at the recorded `runtime` (as `startat`), with
  `allow_seek=False`.

The iOS app can observe this by watching the first `/status` frame after
connecting — if the kiln is already `RUNNING` on connect, it was (likely) an
auto-restart.

---

## 11. Recommended backend additions for the iOS client

These are **not** required (the app can be built today against the existing
protocol), but would meaningfully improve the client:

1. **`GET /api/stats` idle response** — return `{}` (or a real idle status with
   `state:"IDLE"`) instead of an empty body, so the app's health-check and the
   watcher (`watcher.py`) don't choke. (issue 1.14 / 4.2)
2. **Optional auth token** — a shared-secret header on `POST /api` and the
   WebSockets so the iOS app can pass a passcode. (issue 1.11)
3. **Expose `kw_elements` via `/config`** — so the app can show an accurate
   pre-run cost estimate instead of hardcoding power. (issue 3.1)
4. **Fix pause/resume guards & emergency-shutoff scale** — safety. (issues 1.3,
   1.4)
5. **Single multiplexed status JSON with `type`** — optional convenience; the
   app can handle the current backlog/live distinction.

Until #1 and #2 land, the iOS app must:
- treat an empty `GET /api/stats` body as "idle/healthy",
- connect via plain `ws://`/`http://` (no auth).

---

## 12. iOS app architecture guidance

Given the real protocol, the Swift rewrite should:

- **Networking:** one `ControllerAPI` that holds the base URL and a small REST
  client, plus a `WebSocketService` that manages **four** sockets
  (`/status`,`/control`,`/storage`,`/config`) with independent reconnect/backoff.
  (`URLSessionWebSocketTask` per socket.)
- **Models:** drop the segment-based `FiringProgram`; use a point-based
  `Profile { name, tempUnits, data: [(time: Double, temp: Double)] }` matching
  the wire format. `KilnState` should decode `IDLE/RUNNING/PAUSED`. `KilnStatus`
  should mirror `get_state()` fields (`runtime`, `temperature`, `target`,
  `heat`, `heatRate`, `totaltime`, `cost`, `profile`, `catchingUp`,
  `pidstats`).
- **State push:** subscribe to `/status`; on `backlog`, seed the live chart and
  selected profile; on each state dict, update the dashboard + append a chart
  point `(runtime, temperature)`.
- **Programs CRUD:** use `/storage` WS (`GET`/`PUT`/`DELETE`) — *not* REST.
- **Run control:** use REST `POST /api` (`run`/`stop`/`pause`/`resume`) for
  commands; use `/control` WS `RUN`/`STOP` only if needed. The app should read
  back success from `/status` state changes.
- **Config:** open `/config`, send `"GET"`, decode the returned config object;
  refresh on reconnect.
- **Connection setup:** user enters host (e.g. `192.168.178.120`) and port
  (`8080`). Store in Keychain. Validate by calling `GET /api/stats` (accept
  empty body as OK if HTTP 200).
