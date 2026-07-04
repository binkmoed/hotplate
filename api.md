# Kiln Controller — Full API Reference (`api.md`)

Base URL on the LAN: `http://192.168.178.120:8080`
Protocol: plain HTTP/1.1 + WebSocket (no TLS, no auth) by default.

All request/response bodies are JSON (`application/json`) unless noted. The
server is a single-process Bottle app on gevent; WebSockets are handled by
`geventwebsocket`.

This reference is derived directly from the source
(`kiln-controller.py`, `lib/oven.py`, `lib/ovenWatcher.py`, `config.py`).

---

## Table of contents

1. [REST routes](#1-rest-routes)
   - [1.1 `GET /`](#11-get-)
   - [1.2 `GET /state`](#12-get-state)
   - [1.3 `GET /picoreflow/<filename>`](#13-get-picoreflowfilename-static)
   - [1.4 `POST /api`](#14-post-api)
     - [`run`](#cmd-run), [`pause`](#cmd-pause), [`resume`](#cmd-resume),
       [`stop`](#cmd-stop), [`memo`](#cmd-memo), [`stats`](#cmd-stats)
   - [1.5 `GET /api/stats`](#15-get-apistats)
2. [WebSockets](#2-websockets)
   - [2.1 `/status`](#21-status) — live state push
   - [2.2 `/control`](#22-control) — run/stop commands
   - [2.3 `/storage`](#23-storage) — profile CRUD
   - [2.4 `/config`](#24-config) — controller config
3. [Data models](#3-data-models)
   - [3.1 Profile](#31-profile)
   - [3.2 State object (`get_state()`)](#32-state-object-get_state)
   - [3.3 PID stats (`pidstats`)](#33-pid-stats-pidstats)
   - [3.4 Config object](#34-config-object)
4. [Error handling & edge cases](#4-error-handling--edge-cases)
5. [Example iOS flows](#5-example-ios-flows)
6. [Known backend quirks affecting clients](#6-known-backend-quirks-affecting-clients)

---

# 1. REST routes

## 1.1 `GET /`

**Effect:** `302` redirect to `/picoreflow/index.html`.

The iOS app does not need this; it exists for browser entry.

## 1.2 `GET /state`

**Effect:** `302` redirect to `/picoreflow/state.html`.

## 1.3 `GET /picoreflow/<filename>` (static)

Serves files from the `public/` directory. Used for the web UI assets.
The iOS app will not consume this route.

## 1.4 `POST /api`

The main command endpoint. Body is a JSON object with a `cmd` field.

**Request headers:** `Content-Type: application/json`
**Request body:** `{"cmd": "<command>", ...}`

**Success response:** `200` `{"success": true}`
**Error responses:** `200` `{"success": false, "error": "<message>"}` for
validation errors; exceptions during `run` return
`{"success": false, "error": "Failed to run profile: ..."}`.

> Note: the server always returns HTTP 200 with a JSON body, even on logical
> errors (it does not use 4xx/5xx for command failures). Inspect `success`.

### Request parsing

- If the body is not valid JSON → `{"success": false, "error": "Invalid JSON"}`.
- If the body is valid JSON but not an object →
  `{"success": false, "error": "Invalid request format"}`.
- If `cmd` is missing → `{"success": false, "error": "Missing cmd parameter"}`.

### `cmd: run`

Start (or restart) a profile by name, optionally skipping ahead.

**Body:**
```json
{
  "cmd": "run",
  "profile": "Bisque",
  "startat": 0
}
```

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `cmd` | string | yes | — | must be `"run"` |
| `profile` | string | yes | — | the profile `name` (not filename) |
| `startat` | number | no | `0` | minutes to skip into the schedule. If `> 0`, seek-start is disabled. Must be numeric or a numeric string. |

**Behaviour:**
- Looks up the profile by name among all files in `storage/profiles/`.
- If not found → `{"success": false, "error": "profile <name> not found"}`.
- Constructs a `Profile` object and calls `oven.run_profile(profile, startat=startat, allow_seek=...)`.
- Calls `ovenWatcher.record(profile)` (resets the live log + backlog).
- Returns `{"success": true}`.

**Example:**
```bash
curl -X POST http://192.168.178.120:8080/api \
  -H "Content-Type: application/json" \
  -d '{"cmd":"run","profile":"Bisque"}'
```

Restart at minute 60:
```bash
curl -X POST http://192.168.178.120:8080/api \
  -H "Content-Type: application/json" \
  -d '{"cmd":"run","profile":"Bisque","startat":60}'
```

> The success response is returned **immediately**; the run starts
> asynchronously in the oven thread. Verify via `/status`.

### `cmd: pause`

Pause the running profile (hold the current schedule position; PID continues
to hold temperature). REST-only (no WebSocket equivalent).

**Body:** `{"cmd":"pause"}`
**Response:** `{"success": true}`

> Bug note: no state guard — sending `pause` while `IDLE` can crash the oven
> thread (see issue 1.4). The iOS app should only send `pause` when
> `state == "RUNNING"`.

### `cmd: resume`

Resume a paused run.

**Body:** `{"cmd":"resume"}`
**Response:** `{"success": true}`

> Same guard caveat: only send when `state == "PAUSED"`.

### `cmd: stop`

Abort the current run and return to `IDLE`. Safe to call from any state.

**Body:** `{"cmd":"stop"}`
**Response:** `{"success": true}`

### `cmd: memo`

Append a message to the server log only (no state change).

**Body:** `{"cmd":"memo","memo":"any text"}`
**Response:** `{"success": true}`

### `cmd: stats`

Return the current `pidstats` object (identical to `GET /api/stats`).

**Body:** `{"cmd":"stats"}`
**Response:** `200` with body = `json.dumps(oven.pid.pidstats)` (a JSON-encoded
string of the pidstats object). Empty/`null` if no PID has computed yet.

> Quirk: this returns a pre-serialised JSON string, whereas other `cmd`s return
> dicts. The effective payload is still the pidstats object; clients should
> parse the body as JSON (handling the double-encoded string is not required
> because Bottle serves the string as the body).

### Unknown `cmd`

Returns `{"success": false, "error": "Unknown command: <cmd>"}`.

## 1.5 `GET /api/stats`

Returns the current PID statistics for a running schedule. Used by `watcher.py`
and suitable as a lightweight health check.

**Response:**
- If a PID exists and has computed: `200`, body = `json.dumps(pidstats)` (see
  [§3.3](#33-pid-stats-pidstats)). Content-Type is `text/html` (Bottle default
  for a raw string return).
- If idle (no PID yet): `200` with an empty body (`None` returned → empty).
  **Treat an empty 200 body as "idle/healthy".**

**Example:**
```bash
curl http://192.168.178.120:8080/api/stats
# {"time": 1719400000, "setpoint": 300.0, "ispoint": 287.3, "err": 12.7, ...}
```

---

# 2. WebSockets

The server exposes **four independent** WebSocket endpoints. There is **no**
multiplexing and **no** subscribe handshake. Open one socket per concern.

WebSocket URL scheme: `ws://<host>:<port>/<path>` (or `wss://` behind a TLS
proxy). All frames are **text** (JSON).

## 2.1 `/status`

**Purpose:** receive live oven state and historical backlog.

**Direction:** primarily server→client; the server reads from the socket but
only echoes `"Your message was: <input>"` (clients should not send anything).

**Lifecycle:**
1. On connect, the server adds the socket as an observer and immediately sends
   a **backlog** frame.
2. The `OvenWatcher` thread then pushes a **state** frame every
   `config.sensor_time_wait` (default 3 s) for the lifetime of the connection.

### Backlog frame (first message)

```jsonc
{
  "type": "backlog",
  "profile": {                       // null if no profile has run this session
    "name": "Bisque",
    "data": [[0,25],[3600,300],[7200,600],[19800,1220]],
    "type": "profile"
  },
  "log": [ <state-obj>, <state-obj>, ... ]   // down-sampled to ~50 points
}
```

Each `<state-obj>` in `log` has the same shape as the live state frame below.

### State frame (every 3 s)

A single object — the return of `oven.get_state()` — with **no** `type` field:
see [§3.2](#32-state-object-get_state).

**Example:**
```jsonc
{
  "cost": 0.42,
  "runtime": 1840.0,
  "temperature": 421.0,
  "target": 430.0,
  "state": "RUNNING",
  "heat": 1.0,
  "heat_rate": 180.0,
  "totaltime": 19800.0,
  "kwh_rate": 0.25,
  "currency_type": "€",
  "profile": "Bisque",
  "pidstats": { /* see §3.3 */ },
  "catching_up": false
}
```

**Client guidance:** distinguish backlog vs. state by checking for
`obj.type === "backlog"`. If backlog: seed the live chart from `log` (x =
`runtime`, y = `temperature`) and set the selected profile from `profile.name`.
Otherwise: update the dashboard and append `(runtime, temperature)` to the live
chart.

**Disconnects:** the server removes the observer on `WebSocketError`. There is
**no server-initiated reconnect** — the client must reconnect with backoff.

## 2.2 `/control`

**Purpose:** send run/stop commands (alternative to REST `POST /api`).

**Direction:** client→server. The server logs received messages but sends **no
acknowledgement** (except for the SIMULATE path, which is a no-op).

**Messages:**

```jsonc
// Start a run with a full profile object
{
  "cmd": "RUN",
  "profile": {
    "name": "Bisque",
    "type": "profile",
    "data": [[0,25],[3600,300],[7200,600],[19800,1220]],
    "temp_units": "c"
  }
}

// Stop the current run
{ "cmd": "STOP" }

// (No-op in current build) Begin a simulation
{ "cmd": "SIMULATE", "profile": { ... } }
```

**Notes:**
- Unlike REST `run`, the WebSocket `RUN` takes the **full profile object**
  (not the name) and does **not** support `startat`.
- `pause`/`resume` are **not** supported over `/control`; use REST.
- Confirm success by observing the next `/status` frame's `state`.

## 2.3 `/storage`

**Purpose:** list, save, and delete firing profiles.

**Direction:** bidirectional. The protocol is loose: the client may send the
bare string `"GET"` or a JSON object.

### List profiles

Send the text frame: `GET`

**Response:** a JSON text frame containing an array of profile objects (already
unit-converted to the server's `temp_scale`). Example:
```jsonc
[
  {"type":"profile","name":"Bisque","temp_units":"c","data":[[0,25],[3600,300],[7200,600],[19800,1220]]}
]
```

### Save / overwrite a profile

Send:
```jsonc
{
  "cmd": "PUT",
  "profile": {
    "name": "MyGlaze",
    "type": "profile",
    "data": [[0,25],[3600,600],[10800,1220]],
    "temp_units": "c"
  },
  "force": false
}
```

**Response flow:**
- If `force` is `false` and a file with that name exists, the server replies
  `{"cmd":"PUT","profile":{...},"resp":"FAIL"}`. The client should prompt and
  re-send with `"force": true` to overwrite.
- On success, the server replies `{"...","resp":"OK"}` and then immediately
  sends the full profile list (as if `GET` were called).

> `temp_units`: the server adds `"temp_units":"c"` on save if absent and
> converts from the configured scale to °C before writing. The iOS app should
> always send `"temp_units":"c"` and °C data to avoid ambiguity.

### Delete a profile

Send:
```jsonc
{
  "cmd": "DELETE",
  "profile": { "name": "MyGlaze" }
}
```

**Response:** the same object echoed with `resp` added:
`{"cmd":"DELETE","profile":{"name":"MyGlaze"},"resp":"OK"}` (or `"FAIL"` if the
file did not exist).

## 2.4 `/config`

**Purpose:** retrieve controller display configuration.

**Direction:** client sends a message (typically the string `"GET"`) to trigger a
response; the server replies with the config object on **each** received
message.

**Send:** `GET`

**Response:** see [§3.4](#34-config-object). Example:
```jsonc
{
  "temp_scale": "c",
  "time_scale_slope": "h",
  "time_scale_profile": "m",
  "kwh_rate": 0.25,
  "currency_type": "€"
}
```

---

# 3. Data models

## 3.1 Profile

```ts
interface Profile {
  type: "profile";            // always "profile"
  name: string;               // filesystem-safe; becomes <name>.json
  temp_units: "c" | "f";      // storage unit; server normalises to "c" on save
  data: [number, number][];   // [seconds, temperature] points, ascending by time
}
```

- `data` must be sorted ascending by time. The server re-sorts on load.
- Duration = `max(data[*][0])` seconds.
- Target temperature at time `t` = linear interpolation between surrounding
  points; `0` if `t` beyond the last point (run ends).

**Wire note:** `data` elements are JSON arrays `[seconds, temperature]`, not
objects. In Swift, decode as `(Double, Double)` tuples or `[[Double]]`.

## 3.2 State object (`get_state()`)

Pushed on `/status` (after the backlog). All fields are always present when
`state == "RUNNING"`; some are `0`/`null`/`{}` when `IDLE`.

```ts
interface KilnStateFrame {
  cost: number;              // running energy cost (currency from /config)
  runtime: number;           // seconds since profile start
  temperature: number;       // current oven temp, in temp_scale, incl. offset
  target: number;            // current profile target temp
  state: "IDLE" | "RUNNING" | "PAUSED";
  heat: number;              // 0.0 off / 1.0 on (RealOven); on-seconds (SimulatedOven)
  heat_rate: number;         // degrees per hour (computed in get_state; see issue 2.5)
  totaltime: number;         // profile duration in seconds
  kwh_rate: number;          // echoed from config
  currency_type: string;     // e.g. "€"
  profile: string | null;    // profile name or null
  pidstats: PIDStats | {};    // see §3.3; {} right after reset()
  catching_up: boolean;      // true while schedule waits for temp to catch up
}
```

Fields the web UI reads but the server **never** sends: `cool`, `air`, `door`
(bug 1.5). `hazard` is computed client-side from `temperature`.

## 3.3 PID stats (`pidstats`)

```ts
interface PIDStats {
  time: number;          // unix timestamp (seconds) of the compute
  timeDelta: number;     // seconds since previous compute
  setpoint: number;      // target temp at compute time
  ispoint: number;       // measured temp at compute time
  err: number;           // setpoint - ispoint
  errDelta: number;      // err - lastErr
  p: number;             // kp * err
  i: number;             // integral term (iterm)
  d: number;             // kd * dErr
  kp: number;            // proportional gain
  ki: number;            // integral gain (note: used as 1/ki internally)
  kd: number;            // derivative gain
  pid: number;           // raw combined output, windowed to ±100
  out: number;           // normalised output, 0..1 (SSR on-fraction)
}
```

- `out` is the value to display as "heat %" (`out * 100`).
- Right after `reset()`, `pidstats` is `{}` (empty object). Decode defensively
  (all keys optional). `GET /api/stats` returns empty in this case.
- `ki` in the config is used as `1/ki` in the integral computation; the value
  in `pidstats.ki` is the raw config value (e.g. 75), not the reciprocal.

## 3.4 Config object

Returned by `/config` WebSocket and (partly) echoed in each state frame.

```ts
interface ControllerConfig {
  temp_scale: "c" | "f";
  time_scale_slope: "s" | "m" | "h";
  time_scale_profile: "s" | "m" | "h";
  kwh_rate: number;       // price per kWh
  currency_type: string;  // currency symbol
}
```

**Not exposed** via `/config` (only inside `pidstats` or `config.py`):
`kw_elements` (element kW), `emergency_shutoff_temp`, `pid_kp/ki/kd`,
`sensor_time_wait`, `max_ssr_on_time`. The iOS app cannot read these today
(except the PID gains, which appear in each `pidstats` frame).

---

# 4. Error handling & edge cases

| Situation | Server behaviour | Client should |
|---|---|---|
| `POST /api` invalid JSON | `{"success":false,"error":"Invalid JSON"}` | Show error. |
| `POST /api` missing `cmd` | `{"success":false,"error":"Missing cmd parameter"}` | — |
| `run` profile not found | `{"success":false,"error":"profile X not found"}` | Refresh profile list. |
| `run` non-numeric `startat` | `{"success":false,"error":"Invalid startat value"}` | Validate input. |
| `pause`/`resume` while `IDLE` | No guard → may crash oven thread (bug 1.4) | Only send when state is RUNNING/PAUSED. |
| `GET /api/stats` while idle | `200` empty body | Treat empty 200 as healthy/idle. |
| Non-WebSocket request to `/status` etc. | `NameError` → 500 (bug 1.1) | Don't hit these via plain HTTP; use WS upgrade. |
| WebSocket disconnect | Observer removed silently | Reconnect with backoff; re-send any needed `GET`. |
| Profile name with path separators | Writes outside profile dir (bug 1.9) | Send safe names; rely on server fix. |

The server does **not** set `Content-Type: application/json` consistently for
all JSON returns (some returns are pre-serialised strings served as
`text/html`). Clients should parse the body as JSON regardless of content type.

---

# 5. Example iOS flows

### 5.1 Connect & show live status
1. Store `host`/`port` in Keychain.
2. `GET http://<host>:<port>/api/stats` — if HTTP 200 (even empty), mark
   connection OK.
3. Open `ws://<host>:<port>/status`.
4. First frame: parse `backlog`; seed chart + selected profile.
5. Subsequent frames: update dashboard; append `(runtime, temperature)`.

### 5.2 List & edit profiles
1. Open `ws://<host>:<port>/storage`.
2. Send `GET`; parse the returned array into `[Profile]`.
3. To save: send `{"cmd":"PUT","profile":{...},"force":false}`. On `resp:"FAIL"`,
   prompt and resend with `"force":true`.
4. To delete: send `{"cmd":"DELETE","profile":{"name":<name>}}`; check `resp`.
5. After PUT/DELETE success, the server re-sends the full list — refresh from it.

### 5.3 Start a run
1. (Profile selected by name from the `/storage` list.)
2. `POST /api` with `{"cmd":"run","profile":"<name>"}` (optionally `startat`).
3. Watch `/status`: expect `state` to become `"RUNNING"`, `profile` to equal the
   name, `totaltime` populated.

### 5.4 Pause / resume / stop
- `POST /api` `{"cmd":"pause"}` — only when `state == "RUNNING"`.
- `POST /api` `{"cmd":"resume"}` — only when `state == "PAUSED"`.
- `POST /api` `{"cmd":"stop"}` — anytime.

### 5.5 Load config
1. Open `ws://<host>:<port>/config`.
2. Send `GET`.
3. Decode config object; apply temp scale & currency to the UI.

---

# 6. Known backend quirks affecting clients

(See `issue-list.md` for full detail.)

- **`GET /api/stats` empty when idle** — treat empty 200 as "healthy/idle".
- **`pause`/`resume` unguarded** — only send in the correct state or the oven
  thread may crash.
- **`cool`/`air`/`door` never sent** — don't rely on them.
- **`pidstats` is `{}` after reset** — decode all fields as optional.
- **No ack on `/control`** — confirm via `/status`.
- **`/storage` `GET` is a bare string** — handle both string (`"GET"`) send and
  JSON-array receive.
- **`out` is 0..1**, not 0..100; multiply by 100 for a percentage.
- **`heat_rate` is degrees/hour**, though the label in the old UI omits `/hr`.
- **No auth/TLS** — use plain `http`/`ws` until a reverse proxy + token is added.
- **Seek-start offset is currently lost after one cycle** (bug 1.2) — until
  fixed, `startat` restart may not honour the temperature-matched seek.
- **Emergency shutoff temperature may be in the wrong scale** (bug 1.3) — do
  not rely on the server's over-temp protection until confirmed/fixed.
