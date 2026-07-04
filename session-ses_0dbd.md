# iOS/Python Raspberry Pi 3 B implementation plan

**Session ID:** ses_0dbdc9198ffemkZV9wMkvUVf39
**Created:** 7/2/2026, 8:42:09 PM
**Updated:** 7/2/2026, 8:53:03 PM

---

## User

please read through the api.md plan.md spec.md and write a complete plan of implementation of a new ios swift front-end and a python back end running on a raspberry pi 3 b

---

## Assistant (Build · GLM-4.7 · 7.3s)

_Thinking:_


The user wants me to read through three files (api.md, plan.md, and spec.md) and create a complete implementation plan for an iOS Swift front-end and a Python back-end running on a Raspberry Pi 3 B.

Let me start by reading these three files to understand what needs to be implemented.

I'll read through those three files to understand the requirements and create a comprehensive implementation plan.

**Tool: read**

**Input:**
```json
{
  "filePath": "/Users/paul/Desktop/BinkKiln/api.md"
}
```

**Output:**
```
<path>/Users/paul/Desktop/BinkKiln/api.md</path>
<type>file</type>
<content>
1: # Kiln Controller — Full API Reference (`api.md`)
2: 
3: Base URL on the LAN: `http://192.168.178.120:8080`
4: Protocol: plain HTTP/1.1 + WebSocket (no TLS, no auth) by default.
5: 
6: All request/response bodies are JSON (`application/json`) unless noted. The
7: server is a single-process Bottle app on gevent; WebSockets are handled by
8: `geventwebsocket`.
9: 
10: This reference is derived directly from the source
11: (`kiln-controller.py`, `lib/oven.py`, `lib/ovenWatcher.py`, `config.py`).
12: 
13: ---
14: 
15: ## Table of contents
16: 
17: 1. [REST routes](#1-rest-routes)
18:    - [1.1 `GET /`](#11-get-)
19:    - [1.2 `GET /state`](#12-get-state)
20:    - [1.3 `GET /picoreflow/<filename>`](#13-get-picoreflowfilename-static)
21:    - [1.4 `POST /api`](#14-post-api)
22:      - [`run`](#cmd-run), [`pause`](#cmd-pause), [`resume`](#cmd-resume),
23:        [`stop`](#cmd-stop), [`memo`](#cmd-memo), [`stats`](#cmd-stats)
24:    - [1.5 `GET /api/stats`](#15-get-apistats)
25: 2. [WebSockets](#2-websockets)
26:    - [2.1 `/status`](#21-status) — live state push
27:    - [2.2 `/control`](#22-control) — run/stop commands
28:    - [2.3 `/storage`](#23-storage) — profile CRUD
29:    - [2.4 `/config`](#24-config) — controller config
30: 3. [Data models](#3-data-models)
31:    - [3.1 Profile](#31-profile)
32:    - [3.2 State object (`get_state()`)](#32-state-object-get_state)
33:    - [3.3 PID stats (`pidstats`)](#33-pid-stats-pidstats)
34:    - [3.4 Config object](#34-config-object)
35: 4. [Error handling & edge cases](#4-error-handling--edge-cases)
36: 5. [Example iOS flows](#5-example-ios-flows)
37: 6. [Known backend quirks affecting clients](#6-known-backend-quirks-affecting-clients)
38: 
39: ---
40: 
41: # 1. REST routes
42: 
43: ## 1.1 `GET /`
44: 
45: **Effect:** `302` redirect to `/picoreflow/index.html`.
46: 
47: The iOS app does not need this; it exists for browser entry.
48: 
49: ## 1.2 `GET /state`
50: 
51: **Effect:** `302` redirect to `/picoreflow/state.html`.
52: 
53: ## 1.3 `GET /picoreflow/<filename>` (static)
54: 
55: Serves files from the `public/` directory. Used for the web UI assets.
56: The iOS app will not consume this route.
57: 
58: ## 1.4 `POST /api`
59: 
60: The main command endpoint. Body is a JSON object with a `cmd` field.
61: 
62: **Request headers:** `Content-Type: application/json`
63: **Request body:** `{"cmd": "<command>", ...}`
64: 
65: **Success response:** `200` `{"success": true}`
66: **Error responses:** `200` `{"success": false, "error": "<message>"}` for
67: validation errors; exceptions during `run` return
68: `{"success": false, "error": "Failed to run profile: ..."}`.
69: 
70: > Note: the server always returns HTTP 200 with a JSON body, even on logical
71: > errors (it does not use 4xx/5xx for command failures). Inspect `success`.
72: 
73: ### Request parsing
74: 
75: - If the body is not valid JSON → `{"success": false, "error": "Invalid JSON"}`.
76: - If the body is valid JSON but not an object →
77:   `{"success": false, "error": "Invalid request format"}`.
78: - If `cmd` is missing → `{"success": false, "error": "Missing cmd parameter"}`.
79: 
80: ### `cmd: run`
81: 
82: Start (or restart) a profile by name, optionally skipping ahead.
83: 
84: **Body:**
85: ```json
86: {
87:   "cmd": "run",
88:   "profile": "Bisque",
89:   "startat": 0
90: }
91: ```
92: 
93: | Field | Type | Required | Default | Notes |
94: |---|---|---|---|---|
95: | `cmd` | string | yes | — | must be `"run"` |
96: | `profile` | string | yes | — | the profile `name` (not filename) |
97: | `startat` | number | no | `0` | minutes to skip into the schedule. If `> 0`, seek-start is disabled. Must be numeric or a numeric string. |
98: 
99: **Behaviour:**
100: - Looks up the profile by name among all files in `storage/profiles/`.
101: - If not found → `{"success": false, "error": "profile <name> not found"}`.
102: - Constructs a `Profile` object and calls `oven.run_profile(profile, startat=startat, allow_seek=...)`.
103: - Calls `ovenWatcher.record(profile)` (resets the live log + backlog).
104: - Returns `{"success": true}`.
105: 
106: **Example:**
107: ```bash
108: curl -X POST http://192.168.178.120:8080/api \
109:   -H "Content-Type: application/json" \
110:   -d '{"cmd":"run","profile":"Bisque"}'
111: ```
112: 
113: Restart at minute 60:
114: ```bash
115: curl -X POST http://192.168.178.120:8080/api \
116:   -H "Content-Type: application/json" \
117:   -d '{"cmd":"run","profile":"Bisque","startat":60}'
118: ```
119: 
120: > The success response is returned **immediately**; the run starts
121: > asynchronously in the oven thread. Verify via `/status`.
122: 
123: ### `cmd: pause`
124: 
125: Pause the running profile (hold the current schedule position; PID continues
126: to hold temperature). REST-only (no WebSocket equivalent).
127: 
128: **Body:** `{"cmd":"pause"}`
129: **Response:** `{"success": true}`
130: 
131: > Bug note: no state guard — sending `pause` while `IDLE` can crash the oven
132: > thread (see issue 1.4). The iOS app should only send `pause` when
133: > `state == "RUNNING"`.
134: 
135: ### `cmd: resume`
136: 
137: Resume a paused run.
138: 
139: **Body:** `{"cmd":"resume"}`
140: **Response:** `{"success": true}`
141: 
142: > Same guard caveat: only send when `state == "PAUSED"`.
143: 
144: ### `cmd: stop`
145: 
146: Abort the current run and return to `IDLE`. Safe to call from any state.
147: 
148: **Body:** `{"cmd":"stop"}`
149: **Response:** `{"success": true}`
150: 
151: ### `cmd: memo`
152: 
153: Append a message to the server log only (no state change).
154: 
155: **Body:** `{"cmd":"memo","memo":"any text"}`
156: **Response:** `{"success": true}`
157: 
158: ### `cmd: stats`
159: 
160: Return the current `pidstats` object (identical to `GET /api/stats`).
161: 
162: **Body:** `{"cmd":"stats"}`
163: **Response:** `200` with body = `json.dumps(oven.pid.pidstats)` (a JSON-encoded
164: string of the pidstats object). Empty/`null` if no PID has computed yet.
165: 
166: > Quirk: this returns a pre-serialised JSON string, whereas other `cmd`s return
167: > dicts. The effective payload is still the pidstats object; clients should
168: > parse the body as JSON (handling the double-encoded string is not required
169: > because Bottle serves the string as the body).
170: 
171: ### Unknown `cmd`
172: 
173: Returns `{"success": false, "error": "Unknown command: <cmd>"}`.
174: 
175: ## 1.5 `GET /api/stats`
176: 
177: Returns the current PID statistics for a running schedule. Used by `watcher.py`
178: and suitable as a lightweight health check.
179: 
180: **Response:**
181: - If a PID exists and has computed: `200`, body = `json.dumps(pidstats)` (see
182:   [§3.3](#33-pid-stats-pidstats)). Content-Type is `text/html` (Bottle default
183:   for a raw string return).
184: - If idle (no PID yet): `200` with an empty body (`None` returned → empty).
185:   **Treat an empty 200 body as "idle/healthy".**
186: 
187: **Example:**
188: ```bash
189: curl http://192.168.178.120:8080/api/stats
190: # {"time": 1719400000, "setpoint": 300.0, "ispoint": 287.3, "err": 12.7, ...}
191: ```
192: 
193: ---
194: 
195: # 2. WebSockets
196: 
197: The server exposes **four independent** WebSocket endpoints. There is **no**
198: multiplexing and **no** subscribe handshake. Open one socket per concern.
199: 
200: WebSocket URL scheme: `ws://<host>:<port>/<path>` (or `wss://` behind a TLS
201: proxy). All frames are **text** (JSON).
202: 
203: ## 2.1 `/status`
204: 
205: **Purpose:** receive live oven state and historical backlog.
206: 
207: **Direction:** primarily server→client; the server reads from the socket but
208: only echoes `"Your message was: <input>"` (clients should not send anything).
209: 
210: **Lifecycle:**
211: 1. On connect, the server adds the socket as an observer and immediately sends
212:    a **backlog** frame.
213: 2. The `OvenWatcher` thread then pushes a **state** frame every
214:    `config.sensor_time_wait` (default 3 s) for the lifetime of the connection.
215: 
216: ### Backlog frame (first message)
217: 
218: ```jsonc
219: {
220:   "type": "backlog",
221:   "profile": {                       // null if no profile has run this session
222:     "name": "Bisque",
223:     "data": [[0,25],[3600,300],[7200,600],[19800,1220]],
224:     "type": "profile"
225:   },
226:   "log": [ <state-obj>, <state-obj>, ... ]   // down-sampled to ~50 points
227: }
228: ```
229: 
230: Each `<state-obj>` in `log` has the same shape as the live state frame below.
231: 
232: ### State frame (every 3 s)
233: 
234: A single object — the return of `oven.get_state()` — with **no** `type` field:
235: see [§3.2](#32-state-object-get_state).
236: 
237: **Example:**
238: ```jsonc
239: {
240:   "cost": 0.42,
241:   "runtime": 1840.0,
242:   "temperature": 421.0,
243:   "target": 430.0,
244:   "state": "RUNNING",
245:   "heat": 1.0,
246:   "heat_rate": 180.0,
247:   "totaltime": 19800.0,
248:   "kwh_rate": 0.25,
249:   "currency_type": "€",
250:   "profile": "Bisque",
251:   "pidstats": { /* see §3.3 */ },
252:   "catching_up": false
253: }
254: ```
255: 
256: **Client guidance:** distinguish backlog vs. state by checking for
257: `obj.type === "backlog"`. If backlog: seed the live chart from `log` (x =
258: `runtime`, y = `temperature`) and set the selected profile from `profile.name`.
259: Otherwise: update the dashboard and append `(runtime, temperature)` to the live
260: chart.
261: 
262: **Disconnects:** the server removes the observer on `WebSocketError`. There is
263: **no server-initiated reconnect** — the client must reconnect with backoff.
264: 
265: ## 2.2 `/control`
266: 
267: **Purpose:** send run/stop commands (alternative to REST `POST /api`).
268: 
269: **Direction:** client→server. The server logs received messages but sends **no
270: acknowledgement** (except for the SIMULATE path, which is a no-op).
271: 
272: **Messages:**
273: 
274: ```jsonc
275: // Start a run with a full profile object
276: {
277:   "cmd": "RUN",
278:   "profile": {
279:     "name": "Bisque",
280:     "type": "profile",
281:     "data": [[0,25],[3600,300],[7200,600],[19800,1220]],
282:     "temp_units": "c"
283:   }
284: }
285: 
286: // Stop the current run
287: { "cmd": "STOP" }
288: 
289: // (No-op in current build) Begin a simulation
290: { "cmd": "SIMULATE", "profile": { ... } }
291: ```
292: 
293: **Notes:**
294: - Unlike REST `run`, the WebSocket `RUN` takes the **full profile object**
295:   (not the name) and does **not** support `startat`.
296: - `pause`/`resume` are **not** supported over `/control`; use REST.
297: - Confirm success by observing the next `/status` frame's `state`.
298: 
299: ## 2.3 `/storage`
300: 
301: **Purpose:** list, save, and delete firing profiles.
302: 
303: **Direction:** bidirectional. The protocol is loose: the client may send the
304: bare string `"GET"` or a JSON object.
305: 
306: ### List profiles
307: 
308: Send the text frame: `GET`
309: 
310: **Response:** a JSON text frame containing an array of profile objects (already
311: unit-converted to the server's `temp_scale`). Example:
312: ```jsonc
313: [
314:   {"type":"profile","name":"Bisque","temp_units":"c","data":[[0,25],[3600,300],[7200,600],[19800,1220]]}
315: ]
316: ```
317: 
318: ### Save / overwrite a profile
319: 
320: Send:
321: ```jsonc
322: {
323:   "cmd": "PUT",
324:   "profile": {
325:     "name": "MyGlaze",
326:     "type": "profile",
327:     "data": [[0,25],[3600,600],[10800,1220]],
328:     "temp_units": "c"
329:   },
330:   "force": false
331: }
332: ```
333: 
334: **Response flow:**
335: - If `force` is `false` and a file with that name exists, the server replies
336:   `{"cmd":"PUT","profile":{...},"resp":"FAIL"}`. The client should prompt and
337:   re-send with `"force": true` to overwrite.
338: - On success, the server replies `{"...","resp":"OK"}` and then immediately
339:   sends the full profile list (as if `GET` were called).
340: 
341: > `temp_units`: the server adds `"temp_units":"c"` on save if absent and
342: > converts from the configured scale to °C before writing. The iOS app should
343: > always send `"temp_units":"c"` and °C data to avoid ambiguity.
344: 
345: ### Delete a profile
346: 
347: Send:
348: ```jsonc
349: {
350:   "cmd": "DELETE",
351:   "profile": { "name": "MyGlaze" }
352: }
353: ```
354: 
355: **Response:** the same object echoed with `resp` added:
356: `{"cmd":"DELETE","profile":{"name":"MyGlaze"},"resp":"OK"}` (or `"FAIL"` if the
357: file did not exist).
358: 
359: ## 2.4 `/config`
360: 
361: **Purpose:** retrieve controller display configuration.
362: 
363: **Direction:** client sends a message (typically the string `"GET"`) to trigger a
364: response; the server replies with the config object on **each** received
365: message.
366: 
367: **Send:** `GET`
368: 
369: **Response:** see [§3.4](#34-config-object). Example:
370: ```jsonc
371: {
372:   "temp_scale": "c",
373:   "time_scale_slope": "h",
374:   "time_scale_profile": "m",
375:   "kwh_rate": 0.25,
376:   "currency_type": "€"
377: }
378: ```
379: 
380: ---
381: 
382: # 3. Data models
383: 
384: ## 3.1 Profile
385: 
386: ```ts
387: interface Profile {
388:   type: "profile";            // always "profile"
389:   name: string;               // filesystem-safe; becomes <name>.json
390:   temp_units: "c" | "f";      // storage unit; server normalises to "c" on save
391:   data: [number, number][];   // [seconds, temperature] points, ascending by time
392: }
393: ```
394: 
395: - `data` must be sorted ascending by time. The server re-sorts on load.
396: - Duration = `max(data[*][0])` seconds.
397: - Target temperature at time `t` = linear interpolation between surrounding
398:   points; `0` if `t` beyond the last point (run ends).
399: 
400: **Wire note:** `data` elements are JSON arrays `[seconds, temperature]`, not
401: objects. In Swift, decode as `(Double, Double)` tuples or `[[Double]]`.
402: 
403: ## 3.2 State object (`get_state()`)
404: 
405: Pushed on `/status` (after the backlog). All fields are always present when
406: `state == "RUNNING"`; some are `0`/`null`/`{}` when `IDLE`.
407: 
408: ```ts
409: interface KilnStateFrame {
410:   cost: number;              // running energy cost (currency from /config)
411:   runtime: number;           // seconds since profile start
412:   temperature: number;       // current oven temp, in temp_scale, incl. offset
413:   target: number;            // current profile target temp
414:   state: "IDLE" | "RUNNING" | "PAUSED";
415:   heat: number;              // 0.0 off / 1.0 on (RealOven); on-seconds (SimulatedOven)
416:   heat_rate: number;         // degrees per hour (computed in get_state; see issue 2.5)
417:   totaltime: number;         // profile duration in seconds
418:   kwh_rate: number;          // echoed from config
419:   currency_type: string;     // e.g. "€"
420:   profile: string | null;    // profile name or null
421:   pidstats: PIDStats | {};    // see §3.3; {} right after reset()
422:   catching_up: boolean;      // true while schedule waits for temp to catch up
423: }
424: ```
425: 
426: Fields the web UI reads but the server **never** sends: `cool`, `air`, `door`
427: (bug 1.5). `hazard` is computed client-side from `temperature`.
428: 
429: ## 3.3 PID stats (`pidstats`)
430: 
431: ```ts
432: interface PIDStats {
433:   time: number;          // unix timestamp (seconds) of the compute
434:   timeDelta: number;     // seconds since previous compute
435:   setpoint: number;      // target temp at compute time
436:   ispoint: number;       // measured temp at compute time
437:   err: number;           // setpoint - ispoint
438:   errDelta: number;      // err - lastErr
439:   p: number;             // kp * err
440:   i: number;             // integral term (iterm)
441:   d: number;             // kd * dErr
442:   kp: number;            // proportional gain
443:   ki: number;            // integral gain (note: used as 1/ki internally)
444:   kd: number;            // derivative gain
445:   pid: number;           // raw combined output, windowed to ±100
446:   out: number;           // normalised output, 0..1 (SSR on-fraction)
447: }
448: ```
449: 
450: - `out` is the value to display as "heat %" (`out * 100`).
451: - Right after `reset()`, `pidstats` is `{}` (empty object). Decode defensively
452:   (all keys optional). `GET /api/stats` returns empty in this case.
453: - `ki` in the config is used as `1/ki` in the integral computation; the value
454:   in `pidstats.ki` is the raw config value (e.g. 75), not the reciprocal.
455: 
456: ## 3.4 Config object
457: 
458: Returned by `/config` WebSocket and (partly) echoed in each state frame.
459: 
460: ```ts
461: interface ControllerConfig {
462:   temp_scale: "c" | "f";
463:   time_scale_slope: "s" | "m" | "h";
464:   time_scale_profile: "s" | "m" | "h";
465:   kwh_rate: number;       // price per kWh
466:   currency_type: string;  // currency symbol
467: }
468: ```
469: 
470: **Not exposed** via `/config` (only inside `pidstats` or `config.py`):
471: `kw_elements` (element kW), `emergency_shutoff_temp`, `pid_kp/ki/kd`,
472: `sensor_time_wait`, `max_ssr_on_time`. The iOS app cannot read these today
473: (except the PID gains, which appear in each `pidstats` frame).
474: 
475: ---
476: 
477: # 4. Error handling & edge cases
478: 
479: | Situation | Server behaviour | Client should |
480: |---|---|---|
481: | `POST /api` invalid JSON | `{"success":false,"error":"Invalid JSON"}` | Show error. |
482: | `POST /api` missing `cmd` | `{"success":false,"error":"Missing cmd parameter"}` | — |
483: | `run` profile not found | `{"success":false,"error":"profile X not found"}` | Refresh profile list. |
484: | `run` non-numeric `startat` | `{"success":false,"error":"Invalid startat value"}` | Validate input. |
485: | `pause`/`resume` while `IDLE` | No guard → may crash oven thread (bug 1.4) | Only send when state is RUNNING/PAUSED. |
486: | `GET /api/stats` while idle | `200` empty body | Treat empty 200 as healthy/idle. |
487: | Non-WebSocket request to `/status` etc. | `NameError` → 500 (bug 1.1) | Don't hit these via plain HTTP; use WS upgrade. |
488: | WebSocket disconnect | Observer removed silently | Reconnect with backoff; re-send any needed `GET`. |
489: | Profile name with path separators | Writes outside profile dir (bug 1.9) | Send safe names; rely on server fix. |
490: 
491: The server does **not** set `Content-Type: application/json` consistently for
492: all JSON returns (some returns are pre-serialised strings served as
493: `text/html`). Clients should parse the body as JSON regardless of content type.
494: 
495: ---
496: 
497: # 5. Example iOS flows
498: 
499: ### 5.1 Connect & show live status
500: 1. Store `host`/`port` in Keychain.
501: 2. `GET http://<host>:<port>/api/stats` — if HTTP 200 (even empty), mark
502:    connection OK.
503: 3. Open `ws://<host>:<port>/status`.
504: 4. First frame: parse `backlog`; seed chart + selected profile.
505: 5. Subsequent frames: update dashboard; append `(runtime, temperature)`.
506: 
507: ### 5.2 List & edit profiles
508: 1. Open `ws://<host>:<port>/storage`.
509: 2. Send `GET`; parse the returned array into `[Profile]`.
510: 3. To save: send `{"cmd":"PUT","profile":{...},"force":false}`. On `resp:"FAIL"`,
511:    prompt and resend with `"force":true`.
512: 4. To delete: send `{"cmd":"DELETE","profile":{"name":<name>}}`; check `resp`.
513: 5. After PUT/DELETE success, the server re-sends the full list — refresh from it.
514: 
515: ### 5.3 Start a run
516: 1. (Profile selected by name from the `/storage` list.)
517: 2. `POST /api` with `{"cmd":"run","profile":"<name>"}` (optionally `startat`).
518: 3. Watch `/status`: expect `state` to become `"RUNNING"`, `profile` to equal the
519:    name, `totaltime` populated.
520: 
521: ### 5.4 Pause / resume / stop
522: - `POST /api` `{"cmd":"pause"}` — only when `state == "RUNNING"`.
523: - `POST /api` `{"cmd":"resume"}` — only when `state == "PAUSED"`.
524: - `POST /api` `{"cmd":"stop"}` — anytime.
525: 
526: ### 5.5 Load config
527: 1. Open `ws://<host>:<port>/config`.
528: 2. Send `GET`.
529: 3. Decode config object; apply temp scale & currency to the UI.
530: 
531: ---
532: 
533: # 6. Known backend quirks affecting clients
534: 
535: (See `issue-list.md` for full detail.)
536: 
537: - **`GET /api/stats` empty when idle** — treat empty 200 as "healthy/idle".
538: - **`pause`/`resume` unguarded** — only send in the correct state or the oven
539:   thread may crash.
540: - **`cool`/`air`/`door` never sent** — don't rely on them.
541: - **`pidstats` is `{}` after reset** — decode all fields as optional.
542: - **No ack on `/control`** — confirm via `/status`.
543: - **`/storage` `GET` is a bare string** — handle both string (`"GET"`) send and
544:   JSON-array receive.
545: - **`out` is 0..1**, not 0..100; multiply by 100 for a percentage.
546: - **`heat_rate` is degrees/hour**, though the label in the old UI omits `/hr`.
547: - **No auth/TLS** — use plain `http`/`ws` until a reverse proxy + token is added.
548: - **Seek-start offset is currently lost after one cycle** (bug 1.2) — until
549:   fixed, `startat` restart may not honour the temperature-matched seek.
550: - **Emergency shutoff temperature may be in the wrong scale** (bug 1.3) — do
551:   not rely on the server's over-temp protection until confirmed/fixed.

(End of file - total 551 lines)
</content>
```

**Tool: read**

**Input:**
```json
{
  "filePath": "/Users/paul/Desktop/BinkKiln/plan.md"
}
```

**Output:**
```
<path>/Users/paul/Desktop/BinkKiln/plan.md</path>
<type>file</type>
<content>
1: # KilnControllerV2 Project Plan
2: 
3: ## Project Overview
4: KilnControllerV2 is a SwiftUI application designed to monitor and control a kiln. It communicates with a kiln controller via a WebSocket for real-time updates and a REST API for configuration and program management.
5: 
6: ## Architecture
7: The project follows the MVVM (Model-View-ViewModel) architecture.
8: 
9: ### 1. Models
10: Data structures representing the domain:
11: - `FiringProgram.swift`: Defines the sequence of temperature steps for a kiln firing.
12: - `ControllerSettings.swift`: Configuration settings for the controller.
13: - `KilnStatus.swift`: Current state of the kiln (temperature, status, etc.).
14: - `WebSocketMessage.swift`: Structure for messages received via WebSocket.
15: - `TempLogEntry.swift`: Individual temperature reading for graphing.
16: 
17: ### 2. ViewModels
18: Business logic and state management for views:
19: - `DashboardViewModel.swift`: Manages the main status screen and quick actions.
20: - `ProgramsViewModel.swift`: Handles loading, creating, and updating firing programs.
21: - `ProgramEditorViewModel.swift`: Specifically handles the logic for editing a program's segments.
22: - `GraphViewModel.swift`: Processes temperature logs for visualization.
23: - `SettingsViewModel.swift`: Manages connection settings and general app configuration.
24: 
25: ### 3. Views
26: UI components organized by feature:
27: - **Dashboard**:
28:     - `DashboardView.swift`: Main entry point for monitoring.
29:     - `StatusCardView.swift`, `TemperatureGaugeView.swift`, `QuickActionsView.swift`: Modular components for the dashboard.
30: - **Programs**:
31:     - `ProgramsListView.swift`: List of available firing programs.
32:     - `ProgramEditorView.swift`: Interface for modifying firing steps.
33:     - `ProgramCardView.swift`, `SegmentRowView.swift`, `ProgramPickerView.swift`: Supporting views for programs.
34: - **Graph**:
35:     - `GraphView.swift`: Visualization of actual and setpoint temperature over time from Schedule start to projected end time.
36: - **Settings**:
37:     - `SettingsView.swift`: General settings. Temperature unit Celcius or Farenheit. Temperature measurement board Max31855 or Max31856 using Hardware or Software SPI. Thermocouple type possible depending on Temperature measurement board. Kiln elements power in kW. Electricity price per kilowatt. Currency Unit.
38:     - `ConnectionSetupView.swift`: Configuration for the controller's IP and port. Ping test for ip address.
39: - **Components**:
40:     - `TempDisplay.swift`, `ConnectionIndicator.swift`, `LoadingOverlay.swift`: Common UI elements used across multiple views.
41: 
42: ### 4. Services
43: Infrastructure and communication layers:
44: - `WebSocketService.swift`: Handles the real-time bidirectional communication with the kiln.
45: - `ControllerAPI.swift`: Handles REST API requests (e.g., sending programs, updating settings).
46: - `KeychainService.swift`: Securely stores sensitive information like API keys or credentials.
47: - `KilnWatcher.swift`: Monitors kiln for errors. The kiln is heating at full power but fails to reach the required temperature increase (often due to worn heating elements, low voltage, or a blown fuse). Thermocouple defect or broken connection. Thermocouple polarity is reversed or the temperature sensor is reading colder than -15° C, Safety alarm activated, usually due to a stuck relay or the kiln exceeding the maximum target temperature, Internal hardware failure detected during the controller's self-check at power-up. Emergency button pressed or lid open or other critical error? stop firing, disconnect contactor and SSR.
48: Event Messages: Certain conditions like power interruptions cause an event message and typically hold or terminate the program
49: upon return. PC & Mobile Integration: You can track firings live and receive alerts or firing results via imessage/sms/email.
50: Error Logs:  store recent events internally. Up to the 50 most recent errors can be viewed or sent via email for deep troubleshooting. A built-in safety function monitors the rate of temperature rise during the full-power heating phase. If the temperature fails to rise by a minimum required threshold of 1 or 2 degrees C over a set period, usually 15 to 30 minutes, the controller cuts power to the heating elements to prevent damage or fire hazards.
51: 
52: - `KilnSelfTest.swift` : Check for valid temperature. Check for network connectivity.
53: 
54: ### 5. Utilities
55: Helper classes and extensions:
56: - `TemperatureFormatter.swift`: Handles conversion and formatting of temperature values.
57: - `Extensions.swift`: General SwiftUI/Swift extensions.
58: - `HapticsManager.swift`: Manages tactile feedback for user interactions.
59: 
60: ### 6. State Management
61: - `AppState.swift`: A central state object (likely an `ObservableObject`) that coordinates state across different ViewModels and Services.
62: 
63: ## Testing
64: - `KilnControllerV2Tests`: Unit tests for logic.
65: - `KilnControllerV2UITests`: UI tests for user flow verification.
66: 
67: ## Future Goals / Roadmap
68: *(This section can be updated as new requirements emerge)*
69: - [ ] Implement real-time alerting for temperature thresholds.
70: - [ ] Improve graph interactivity (zoom/pan).
71: - [ ] Implement offline caching for programs.
72: - [ ] Ask me questions for other ideas of improvements and extra functionality.
73: 

(End of file - total 73 lines)
</content>
```

**Tool: read**

**Input:**
```json
{
  "filePath": "/Users/paul/Desktop/BinkKiln/spec.md"
}
```

**Output:**
```
<path>/Users/paul/Desktop/BinkKiln/spec.md</path>
<type>file</type>
<content>
1: # Kiln Controller — Specification (`spec.md`)
2: 
3: This document describes the **actual** behaviour of the kiln controller as
4: implemented in `~/Downloads/kiln-controller-bug-fixed`, observed from the source
5: code (the live device was unreachable during review). It is the source of truth
6: for building a new iOS front-end. The authoritative wire-protocol reference is
7: `api.md`; this document explains the concepts, data model, and state machine.
8: 
9: > ⚠️ The existing Swift scaffold (`Services/ControllerAPI.swift`, `Models/*`)
10: > was written against a **fictional** REST API and must be rewritten to match
11: > the protocol below. See `issue-list.md` §6 and `api.md`.
12: 
13: ---
14: 
15: ## 1. Overview
16: 
17: A Raspberry Pi runs `kiln-controller.py`, a single-process Bottle + gevent
18: server. It:
19: 
20: - Reads a thermocouple (MAX31855 / MAX31856 ) every duty cycle
21:   (`config.sensor_time_wait`, default 3 s).
22: - Runs a PID controller (`lib/oven.py::PID`) to decide the SSR on-fraction
23:   for each duty cycle.
24: - When firing is started it Drives a Safety SSR relay to bring power to the Main SSR.
25: - Safety SSR has Normally closed lid switch in series with the driving signal. If Lid is opened firing is stopped and signal dropped to safety SSR.
26: - When Firing is active Main SSR drives heating elements. 
27: - Tracks runtime, actual and target temperature, cost, heat rate, and PID stats.
28: - Serves a web UI and a small HTTP/WebSocket API on `0.0.0.0:8080`.
29: - Persists firing profiles as JSON files in `storage/profiles/`.
30: - Writes a restart state file (`state.json`) every duty cycle for power-loss
31:   recovery.
32: - Runs an `OvenWatcher` thread that pushes state to all WebSocket observers.
33: 
34: There is **no database**. Profiles and restart state are flat JSON files.
35: There is **no authentication** and **no TLS** by default (open LAN service).
36: 
37: ### Processes / components
38: 
39: | Component | File | Role |
40: |---|---|---|
41: | HTTP + WS server | `kiln-controller.py` | Serves static UI, REST `/api`, four WebSockets |
42: | Oven core | `lib/oven.py` | PID, profile interpolation, SSR timing, state machine |
43: | State broadcaster | `lib/ovenWatcher.py` | Pushes state to `/status` observers; keeps a backlog |
44: | Config | `config.py` | All tunables: hardware pins, PID, scales, limits |
45: | Watchdog (optional) | `watcher.py` | External script polling `/api/stats`, alerts Slack |
46: | Loggers (optional) | `kiln-logger.py`, `kiln-logger-period.py` | WebSocket loggers → CSV |
47: | Tuner (optional) | `kiln-tuner.py` | Step-response PID autotune |
48: | systemd | `lib/init/kiln-controller.service` | Auto-start on boot |
49: 
50: ### Threading model
51: 
52: - `Oven` (real or simulated) is a `threading.Thread` running the control loop.
53: - `OvenWatcher` is a `threading.Thread` polling `oven.get_state()` every
54:   `sensor_time_wait` and pushing to observers.
55: - `TempSensor` (real) is a `threading.Thread` sampling the thermocouple.
56: - Bottle/gevent handles HTTP and WebSockets on a greenlet pool.
57: 
58: A single global `oven` instance and a single `ovenWatcher` instance are created
59: at startup.
60: 
61: ---
62: 
63: ## 2. Firing profile model
64: 
65: A profile is a JSON object stored as `storage/profiles/<name>.json`:
66: 
67: ```json
68: {
69:   "type": "profile",
70:   "name": "Bisque",
71:   "temp_units": "c",
72:   "data": [
73:     [0, 25],
74:     [3600, 300],
75:     [7200, 600],
76:     [19800, 1220]
77:   ]
78: }
79: ```
80: 
81: - `data` is an array of `[time_seconds, temperature]` points, sorted ascending
82:   by time. The controller interpolates linearly between consecutive points to
83:   find the target temperature at any `runtime`.
84: - `temp_units` is `"c"` (Celsius) or `"f"` (Fahrenheit). Profiles are stored in
85:   °C internally; the server converts to the configured `temp_scale` for
86:   display when serving (one-way only today — see issues).
87: - `type` is always `"profile"` (legacy field).
88: - Duration of the profile = `max(time)` across all points (seconds).
89: 
90: The **only** profile representation over the wire is this point-list format.
91: There is no "segment with rate + hold" model. The iOS app must edit/store
92: profiles in this exact `[[seconds, temp], ...]` form.
93: 
94: ### Interpolation
95: 
96: `Profile.get_target_temperature(time)`:
97: - If `time` is beyond the last point → returns `0` (and `reset_if_schedule_ended`
98:   ends the run).
99: - Otherwise linearly interpolates between the two surrounding points.
100: 
101: ### Seek-start behaviour
102: 
103: When starting a profile and `config.seek_start == True` and the kiln is already
104: hotter than the first point + 5°, the controller advances the schedule start to
105: the time whose target temperature matches the current temperature
106: (`get_start_from_temperature`). This is suppressed when `startat > 0` and on
107: automatic restarts. (Note: bug 1.2 currently loses this offset after one
108: cycle — to be fixed.)
109: 
110: ---
111: 
112: ## 3. Controller state machine
113: 
114: States are uppercase strings: `IDLE`, `RUNNING`, `PAUSED`.
115: (The source defines no `COMPLETE`/`ERROR`; the run simply returns to `IDLE`.)
116: 
117: ```
118:                  run_profile()
119:         ┌────────────────────────► RUNNING
120:  IDLE ──┤                            │
121:         │  automatic_restart()       │ pause
122:         │  (on boot if state.json    ▼
123:         │   says RUNNING & fresh)   PAUSED
124:         │                            │
125:         └────────────────────────────┘ resume
126:                      ▲   │
127:                      │   │ stop / abort_run()
128:                      │   │ schedule ended
129:                      │   │ emergency (temp too high / TC errors)
130:                      └───┘
131: ```
132: 
133: - `run_profile(profile, startat=minutes, allow_seek=bool)` sets state `RUNNING`.
134: - `abort_run()` (stop / emergency / schedule end) calls `reset()` → state `IDLE`
135:   and writes `state.json`.
136: - `pause`/`resume` directly set the state string (no guards today — bug 1.4).
137: 
138: ### What happens each duty cycle while RUNNING
139: 
140: 1. `update_cost()` — add power cost for this cycle.
141: 2. `save_automatic_restart_state()` — write `state.json`.
142: 3. `kiln_must_catch_up()` — if actual temp is outside `pid_control_window` of
143:    target, shift `start_time` so the schedule waits (prevents the profile
144:    running away while the kiln can't keep up). Sets `catching_up`.
145: 4. `update_runtime()` — `runtime = now - start_time`.
146: 5. `update_target_temp()` — interpolate profile at `runtime`.
147: 6. `heat_then_cool()` — compute PID, energise SSR for `heat_on` seconds, then
148:    cool for the rest of `sensor_time_wait`.
149: 7. `reset_if_emergency()` — abort on over-temp or excessive TC errors.
150: 8. `reset_if_schedule_ended()` — abort when `runtime > totaltime`.
151: 
152: ### Emergency conditions
153: 
154: - Current temp ≥ `emergency_shutoff_temp` (unless `ignore_temp_too_high`).
155: - Thermocouple error rate > `limit` (30 %) over the sample window (unless
156:   `ignore_tc_too_many_errors`).
157: - Individual thermocouple faults can each be ignored via `config.ignore_tc_*`.
158: 
159: ---
160: 
161: ## 4. Configuration (`config.py`)
162: 
163: Key values the iOS app should know about (read via `/config` WebSocket):
164: 
165: | Config key | Default | Meaning |
166: |---|---|---|
167: | `temp_scale` | `"c"` | Display unit: `"c"` or `"f"` |
168: | `time_scale_slope` | `"h"` | Slope display unit: s/m/h |
169: | `time_scale_profile` | `"m"` | Profile time display unit: s/m/h |
170: | `kwh_rate` | `0.25` | Energy price per kWh |
171: | `currency_type` | `"€"` | Currency symbol |
172: | `kw_elements` | `7.1` | Element power in kW (NOT currently sent over `/config`; the UI hardcodes 3850 W — bug 3.1) |
173: | `pid_kp`/`pid_ki`/`pid_kd` | 3/75/12 | PID gains (in pidstats, not `/config`) |
174: | `emergency_shutoff_temp` | 2264 | Safety limit (scale bug — issue 1.3) |
175: | `sensor_time_wait` | 3 | Duty cycle seconds; also the state push interval |
176: | `max_ssr_on_time` | 6 | Cap on SSR on-time per cycle |
177: 
178: `/config` currently returns only `temp_scale`, `time_scale_slope`,
179: `time_scale_profile`, `kwh_rate`, `currency_type`. PID gains and limits are
180: **not** exposed via the API (only inside each `/status` message's `pidstats`).
181: 
182: ---
183: 
184: ## 5. Networking — protocol summary
185: 
186: (See `api.md` for the full, exact reference.)
187: 
188: ### 5.1 REST
189: 
190: | Method | Path | Purpose |
191: |---|---|---|
192: | `GET` | `/` | Redirect → `/picoreflow/index.html` |
193: | `GET` | `/state` | Redirect → `/picoreflow/state.html` |
194: | `GET` | `/picoreflow/<file>` | Static UI assets |
195: | `POST` | `/api` | Command endpoint: `run`, `pause`, `resume`, `stop`, `memo`, `stats` |
196: | `GET` | `/api/stats` | Current PID stats (empty when idle) |
197: 
198: ### 5.2 WebSockets (four independent sockets)
199: 
200: | Path | Direction | Content |
201: |---|---|---|
202: | `/status` | server→client push | `backlog` message on connect, then a state dict every `sensor_time_wait` |
203: | `/control` | client→server | `{"cmd":"RUN","profile":{...}}`, `{"cmd":"STOP"}`, `{"cmd":"SIMULATE",...}` |
204: | `/storage` | bidirectional | `GET` (string), `{"cmd":"DELETE","profile":{...}}`, `{"cmd":"PUT","profile":{...},"force":bool}` |
205: | `/config` | server→client push | config JSON on each received message (client sends `"GET"` to trigger) |
206: 
207: Important protocol notes for the iOS app:
208: - There is **no single multiplexed socket** and **no `subscribe` handshake**.
209:   Open four sockets.
210: - The `/status` socket receives JSON objects. The first is `{"type":"backlog",...}`;
211:   subsequent ones are the live `get_state()` dict (no `type` field).
212: - The server never sends an acknowledgement to `/control` `RUN`/`STOP`. The app
213:   learns success from the next `/status` message's `state`.
214: - `/storage` responses are loose: a `DELETE`/`PUT` echoes the request back with
215:   a `resp` field (`"OK"`/`"FAIL"`); a `GET` (string) returns the profile array.
216: - All messages are JSON text frames (no binary).
217: 
218: ---
219: 
220: ## 6. State object (`get_state()`)
221: 
222: Pushed on `/status` every `sensor_time_wait` (3 s). Field types observed from
223: `Oven.get_state()`:
224: 
225: ```jsonc
226: {
227:   "cost": 1.23,                 // running energy cost, currency from /config
228:   "runtime": 1234.0,             // seconds since profile start
229:   "temperature": 612.5,         // current oven temp (in temp_scale), incl. offset
230:   "target": 620.0,              // current profile target temp
231:   "state": "RUNNING",            // "IDLE" | "RUNNING" | "PAUSED"
232:   "heat": 1.0,                  // SSR indicator: 0.0 off / 1.0 on (real); on-seconds (sim)
233:   "heat_rate": 150.0,           // degrees per hour (NOTE: bug 2.5 side-effect)
234:   "totaltime": 19800.0,         // profile duration in seconds
235:   "kwh_rate": 0.25,             // echoed from config
236:   "currency_type": "€",
237:   "profile": "Bisque",          // profile name or null
238:   "pidstats": {                 // see §7
239:     "time": 1719400000,
240:     "timeDelta": 3.0,
241:     "setpoint": 620.0,
242:     "ispoint": 612.5,
243:     "err": 7.5,
244:     "errDelta": ...,
245:     "p": ..., "i": ..., "d": ...,
246:     "kp": 3, "ki": 75, "kd": 12,
247:     "pid": ...,                 // raw (pre-normalise) output
248:     "out": 0.45                 // normalised 0..1 SSR fraction
249:   },
250:   "catching_up": false          // true when schedule is held waiting for temp
251: }
252: ```
253: 
254: Fields the front-end reads but the server **never** sends: `cool`, `air`,
255: `door` (bug 1.5). `hazard` is derived client-side from temperature.
256: 
257: ### Backlog message (first `/status` frame)
258: 
259: ```jsonc
260: {
261:   "type": "backlog",
262:   "profile": { "name": "Bisque", "data": [[0,25],...], "type": "profile" },  // or null
263:   "log": [ <state>, <state>, ... ]   // down-sampled to ~50 points
264: }
265: ```
266: 
267: ---
268: 
269: ## 7. PID stats (`pidstats`)
270: 
271: Populated only after the first `PID.compute()`. When idle just after `reset()`,
272: `pidstats == {}` (empty). Fields:
273: 
274: | Field | Meaning |
275: |---|---|
276: | `time` | Unix timestamp of the compute |
277: | `timeDelta` | Seconds since previous compute |
278: | `setpoint` | Target temperature at compute time |
279: | `ispoint` | Measured temperature |
280: | `err` | `setpoint - ispoint` |
281: | `errDelta` | `err - lastErr` |
282: | `p`,`i`,`d` | P/I/D output components (`kp*err`, `iterm`, `kd*dErr`) |
283: | `kp`,`ki`,`kd` | Current gains |
284: | `pid` | Raw combined output before normalisation (windowed to ±100) |
285: | `out` | Normalised output, 0..1 (SSR on-fraction) |
286: 
287: `GET /api/stats` returns this same `pidstats` object (as a JSON string) when a
288: PID exists; otherwise empty.
289: 
290: ---
291: 
292: ## 8. Profile storage operations
293: 
294: All over the `/storage` WebSocket:
295: 
296: - **List:** send the string `GET`. Server replies with a JSON array of all
297:   profile objects (already unit-converted for display).
298: - **Save/overwrite:** send `{"cmd":"PUT","profile":{...},"force":false}`. If a
299:   profile with that name exists and `force` is false, server replies
300:   `{"...,"resp":"FAIL"}`; the client re-sends with `"force":true` to overwrite.
301:   On success server replies `resp:"OK"` then immediately the full profile list.
302: - **Delete:** send `{"cmd":"DELETE","profile":{"name":"Bisque"}}`. Server
303:   replies with the same object plus `resp:"OK"`/`"FAIL"`.
304: 
305: Profile names become filenames (`<name>.json`); names must be filesystem-safe
306: (path-traversal bug 1.9 — to be fixed server-side; the app should still send
307: safe names).
308: 
309: ---
310: 
311: ## 9. Control commands
312: 
313: Via REST `POST /api` (body `{"cmd":...}`) **or** the `/control` WebSocket:
314: 
315: | cmd | REST body | WS body | Effect |
316: |---|---|---|---|
317: | run | `{"cmd":"run","profile":"Bisque","startat":0}` | `{"cmd":"RUN","profile":{...}}` | Start/resume a profile |
318: | stop | `{"cmd":"stop"}` | `{"cmd":"STOP"}` | Abort the run → IDLE |
319: | pause | `{"cmd":"pause"}` | — | Set state PAUSED (REST only) |
320: | resume | `{"cmd":"resume"}` | — | Set state RUNNING (REST only) |
321: | memo | `{"cmd":"memo","memo":"text"}` | — | Logs a message only |
322: | stats | `{"cmd":"stats"}` (POST) | — | Returns pidstats |
323: | SIMULATE | — | `{"cmd":"SIMULATE",...}` | No-op (commented out in server) |
324: 
325: Notes:
326: - REST `run` takes the **profile name**; WS `RUN` takes the **full profile
327:   object**. The iOS app should prefer the REST `run` (simpler) but must support
328:   `startat` for skip-ahead/restart.
329: - `pause`/`resume` are **REST-only** on the real backend.
330: 
331: ---
332: 
333: ## 10. Automatic restart
334: 
335: If `config.automatic_restarts == True`:
336: - Every duty cycle the oven writes `state.json` (in the script directory) with
337:   the current `get_state()` output.
338: - On boot, if `state.json` exists, is younger than `automatic_restart_window`
339:   minutes (default 15), and its `state` was `RUNNING`, the oven reloads the
340:   named profile and resumes at the recorded `runtime` (as `startat`), with
341:   `allow_seek=False`.
342: 
343: The iOS app can observe this by watching the first `/status` frame after
344: connecting — if the kiln is already `RUNNING` on connect, it was (likely) an
345: auto-restart.
346: 
347: ---
348: 
349: ## 11. Recommended backend additions for the iOS client
350: 
351: These are **not** required (the app can be built today against the existing
352: protocol), but would meaningfully improve the client:
353: 
354: 1. **`GET /api/stats` idle response** — return `{}` (or a real idle status with
355:    `state:"IDLE"`) instead of an empty body, so the app's health-check and the
356:    watcher (`watcher.py`) don't choke. (issue 1.14 / 4.2)
357: 2. **Optional auth token** — a shared-secret header on `POST /api` and the
358:    WebSockets so the iOS app can pass a passcode. (issue 1.11)
359: 3. **Expose `kw_elements` via `/config`** — so the app can show an accurate
360:    pre-run cost estimate instead of hardcoding power. (issue 3.1)
361: 4. **Fix pause/resume guards & emergency-shutoff scale** — safety. (issues 1.3,
362:    1.4)
363: 5. **Single multiplexed status JSON with `type`** — optional convenience; the
364:    app can handle the current backlog/live distinction.
365: 
366: Until #1 and #2 land, the iOS app must:
367: - treat an empty `GET /api/stats` body as "idle/healthy",
368: - connect via plain `ws://`/`http://` (no auth).
369: 
370: ---
371: 
372: ## 12. iOS app architecture guidance
373: 
374: Given the real protocol, the Swift rewrite should:
375: 
376: - **Networking:** one `ControllerAPI` that holds the base URL and a small REST
377:   client, plus a `WebSocketService` that manages **four** sockets
378:   (`/status`,`/control`,`/storage`,`/config`) with independent reconnect/backoff.
379:   (`URLSessionWebSocketTask` per socket.)
380: - **Models:** drop the segment-based `FiringProgram`; use a point-based
381:   `Profile { name, tempUnits, data: [(time: Double, temp: Double)] }` matching
382:   the wire format. `KilnState` should decode `IDLE/RUNNING/PAUSED`. `KilnStatus`
383:   should mirror `get_state()` fields (`runtime`, `temperature`, `target`,
384:   `heat`, `heatRate`, `totaltime`, `cost`, `profile`, `catchingUp`,
385:   `pidstats`).
386: - **State push:** subscribe to `/status`; on `backlog`, seed the live chart and
387:   selected profile; on each state dict, update the dashboard + append a chart
388:   point `(runtime, temperature)`.
389: - **Programs CRUD:** use `/storage` WS (`GET`/`PUT`/`DELETE`) — *not* REST.
390: - **Run control:** use REST `POST /api` (`run`/`stop`/`pause`/`resume`) for
391:   commands; use `/control` WS `RUN`/`STOP` only if needed. The app should read
392:   back success from `/status` state changes.
393: - **Config:** open `/config`, send `"GET"`, decode the returned config object;
394:   refresh on reconnect.
395: - **Connection setup:** user enters host (e.g. `192.168.178.120`) and port
396:   (`8080`). Store in Keychain. Validate by calling `GET /api/stats` (accept
397:   empty body as OK if HTTP 200).

(End of file - total 397 lines)
</content>
```

---

## Assistant (Build · GLM-4.7 · 416.9s)

_Thinking:_


The user wants me to read through the three files (api.md, plan.md, spec.md) and create a complete implementation plan for an iOS Swift front-end and a Python back-end running on a Raspberry Pi 3 B.

Let me analyze what I've read:

## From api.md:
- Base URL: `http://192.168.178.120:8080`
- Protocol: plain HTTP/1.1 + WebSocket (no TLS, no auth) by default
- REST routes: GET /, GET /state, GET /picoreflow/<filename>, POST /api, GET /api/stats
- WebSockets: /status (live state push), /control (run/stop commands), /storage (profile CRUD), /config (controller config)
- Data models: Profile, State object, PID stats, Config object
- Known backend quirks affecting clients

## From plan.md:
- Project Overview: SwiftUI application to monitor and control a kiln
- Architecture: MVVM (Model-View-ViewModel)
- Models: FiringProgram, ControllerSettings, KilnStatus, WebSocketMessage, TempLogEntry
- ViewModels: DashboardViewModel, ProgramsViewModel, ProgramEditorViewModel, GraphViewModel, SettingsViewModel
- Views: Dashboard, Programs, Graph, Settings, Components
- Services: WebSocketService, ControllerAPI, KeychainService, KilnWatcher, KilnSelfTest
- Utilities: TemperatureFormatter, Extensions, HapticsManager
- State Management: AppState
- Testing: Unit tests and UI tests
- Future Goals: Real-time alerting, improved graph interactivity, offline caching

## From spec.md:
- Raspberry Pi runs kiln-controller.py (single-process Bottle + gevent server)
- Components: HTTP + WS server, Oven core, State broadcaster, Config, Watchdog, Loggers, Tuner, systemd
- Firing profile model: JSON with type, name, temp_units, data (array of [time_seconds, temperature])


I see a complex temperature monitoring and control system requiring precise communication protocols. The system uses WebSockets for real-time interactions, with dedicated channels for different functions. REST APIs handle command dispatching, while separate WebSocket connections manage status updates, profile storage, and configuration. 

The architecture demands careful integration between iOS front-end and Python back-end, focusing on real-time kiln temperature monitoring and precise control mechanisms. Each communication channel plays a critical role in ensuring seamless kiln operation and data synchronization.

I'll create a comprehensive implementation plan based on these three documents.

**Tool: write**

**Input:**
```json
{
  "content": "# Kiln Controller Implementation Plan\n## Complete iOS Swift Frontend + Python Backend on Raspberry Pi 3 B\n\n---\n\n## Executive Summary\n\nThis plan outlines the complete implementation of a kiln control system consisting of:\n- **iOS Swift Frontend**: SwiftUI-based mobile application for monitoring and controlling a kiln\n- **Python Backend**: Bottle + gevent server running on Raspberry Pi 3 B for hardware control\n- **Communication**: REST API + 4 independent WebSocket connections\n- **Hardware**: Raspberry Pi 3 B, MAX31855/56 thermocouple reader, SSR relay, safety relay with lid switch\n\n---\n\n## Table of Contents\n\n1. [Architecture Overview](#1-architecture-overview)\n2. [Python Backend Implementation](#2-python-backend-implementation)\n3. [iOS Swift Frontend Implementation](#3-ios-swift-frontend-implementation)\n4. [Hardware Integration](#4-hardware-integration)\n5. [Deployment & Installation](#5-deployment--installation)\n6. [Testing Strategy](#6-testing-strategy)\n7. [Timeline & Milestones](#7-timeline--milestones)\n8. [Risk Assessment](#8-risk-assessment)\n\n---\n\n## 1. Architecture Overview\n\n### 1.1 System Components\n\n```\n┌─────────────────────────────────────────────────────────────┐\n│                      iOS Swift App                           │\n│  ┌─────────────┐  ┌─────────────┐  ┌──────────────────────┐ │\n│  │  Dashboard  │  │  Programs   │  │      Settings        │ │\n│  │   View      │  │    View     │  │       View           │ │\n│  └──────┬──────┘  └──────┬──────┘  └──────────┬───────────┘ │\n│         │                │                     │             │\n│  ┌──────▼────────────────▼─────────────────────▼───────────┐ │\n│  │              WebSocketService (4 sockets)               │ │\n│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │ │\n│  │  │/status  │ │/control │ │/storage │ │/config  │        │ │\n│  │  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘        │ │\n│  └───────┼─────────────┼─────────────┼─────────────┼────────┘ │\n│          │             │             │             │           │\n└──────────┼─────────────┼─────────────┼─────────────┼───────────┘\n           │             │             │             │\n           └─────────────┴─────────────┴─────────────┘\n                     HTTP/WS over LAN (port 8080)\n           ┌─────────────┴─────────────┴─────────────┐\n           │  Raspberry Pi 3 B - Python Backend      │\n           │  ┌─────────────────────────────────────┐ │\n           │  │    kiln-controller.py               │ │\n           │  │  (Bottle + gevent server)           │ │\n           │  └──────────┬──────────────────────────┘ │\n           │  ┌──────────▼──────────────────────────┐ │\n           │  │    Oven Core (lib/oven.py)          │ │\n           │  │  - PID Controller                   │ │\n           │  │  - Profile Interpolation            │ │\n           │  │  - SSR Timing                       │ │\n           │  │  - State Machine                    │ │\n           │  └──────────┬──────────────────────────┘ │\n           │  ┌──────────▼──────────────────────────┐ │\n           │  │    OvenWatcher (lib/ovenWatcher.py) │ │\n           │  │  - State Broadcaster                │ │\n           │  │  - Backlog Management               │ │\n           │  └──────────┬──────────────────────────┘ │\n           │  ┌──────────▼──────────────────────────┐ │\n           │  │    TempSensor (lib/tempSensor.py)   │ │\n           │  │  - MAX31855/56 Reader               │ │\n           │  └──────────┬──────────────────────────┘ │\n           │  ┌──────────▼──────────────────────────┐ │\n           │  │    Hardware Interface               │ │\n           │  │  - GPIO/SSR Control                 │ │\n           │  │  - Safety Relay                     │ │\n           │  │  - Lid Switch                       │ │\n           │  └──────────┬──────────────────────────┘ │\n           │  ┌──────────▼──────────────────────────┐ │\n           │  │    Storage                          │ │\n           │  │  - storage/profiles/*.json          │ │\n           │  │  - state.json                       │ │\n           │  └──────────┬──────────────────────────┘ │\n           │  ┌──────────▼──────────────────────────┐ │\n           │  │    Config (config.py)               │ │\n           │  │  - PID Gains                        │ │\n           │  │  - Hardware Settings                │ │\n           │  │  - Display Settings                 │ │\n           │  └─────────────────────────────────────┘ │\n           └───────────────────────────────────────────┘\n```\n\n### 1.2 Communication Protocol\n\n**REST API (POST /api, GET /api/stats):**\n- Commands: run, pause, resume, stop, memo, stats\n- Health checks\n- Command acknowledgements\n\n**4 Independent WebSocket Connections:**\n1. `/status` - Live state push (every 3 seconds)\n2. `/control` - Run/stop commands\n3. `/storage` - Profile CRUD operations\n4. `/config` - Controller configuration\n\n**Note:** No multiplexing, no authentication by default, plain HTTP/WS\n\n---\n\n## 2. Python Backend Implementation\n\n### 2.1 Core Components\n\n#### 2.1.1 kiln-controller.py (Main Entry Point)\n\n**Dependencies:**\n```python\n# requirements.txt\nbottle==0.12.25\ngevent==23.9.1\ngevent-websocket==0.10.1\nRPi.GPIO==0.7.1\nspidev==3.5\n```\n\n**Key Functions:**\n```python\ndef start_server():\n    # Initialize global oven and ovenWatcher instances\n    # Setup Bottle routes and WebSocket handlers\n    # Run gevent WSGIServer on 0.0.0.0:8080\n    pass\n\n@route('/')\ndef redirect_to_ui():\n    redirect('/picoreflow/index.html')\n\n@post('/api')\ndef handle_api_command():\n    # Parse JSON body with cmd field\n    # Execute: run, pause, resume, stop, memo, stats\n    # Return {\"success\": bool, \"error\": string|None}\n    pass\n\n@get('/api/stats')\ndef get_pid_stats():\n    # Return current pidstats as JSON\n    # Empty body when idle\n    pass\n\n# WebSocket Handlers\n@get('/status', apply=[websocket])\ndef handle_status(ws):\n    # Subscribe observer\n    # Send backlog immediately\n    # Push state every sensor_time_wait\n    pass\n\n@get('/control', apply=[websocket])\ndef handle_control(ws):\n    # Receive RUN, STOP, SIMULATE commands\n    # No acknowledgement (check /status for confirmation)\n    pass\n\n@get('/storage', apply=[websocket])\ndef handle_storage(ws):\n    # Handle GET (list), PUT (save), DELETE operations\n    # Support force flag for overwrites\n    pass\n\n@get('/config', apply=[websocket])\ndef handle_config(ws):\n    # Send config object on each message received\n    pass\n```\n\n#### 2.1.2 lib/oven.py (Oven Core)\n\n**Class Structure:**\n```python\nclass Oven(threading.Thread):\n    def __init__(self, config):\n        # Initialize PID controller\n        # Setup GPIO pins\n        # Load configuration\n        pass\n\n    def run_profile(self, profile, startat=0, allow_seek=True):\n        # Start firing sequence\n        # Set state to RUNNING\n        pass\n\n    def pause(self):\n        # Set state to PAUSED\n        # Hold current position\n        pass\n\n    def resume(self):\n        # Set state to RUNNING\n        pass\n\n    def abort_run(self):\n        # Stop firing\n        # Reset to IDLE\n        # Write state.json\n        pass\n\n    def get_state(self):\n        # Return current state dict with:\n        # - cost, runtime, temperature, target, state\n        # - heat, heat_rate, totaltime, kwh_rate\n        # - currency_type, profile, pidstats, catching_up\n        pass\n\n    def _control_loop(self):\n        while True:\n            # 1. update_cost()\n            # 2. save_automatic_restart_state()\n            # 3. kiln_must_catch_up()\n            # 4. update_runtime()\n            # 5. update_target_temp()\n            # 6. heat_then_cool()\n            # 7. reset_if_emergency()\n            # 8. reset_if_schedule_ended()\n            pass\n\nclass PID:\n    def compute(self, setpoint, input):\n        # Compute PID output\n        # Return pidstats dict\n        pass\n```\n\n#### 2.1.3 lib/ovenWatcher.py (State Broadcaster)\n\n```python\nclass OvenWatcher(threading.Thread):\n    def __init__(self, oven):\n        # Maintain list of WebSocket observers\n        # Build backlog from oven log\n        pass\n\n    def add_observer(self, ws):\n        # Send backlog immediately\n        # Add to observers list\n        pass\n\n    def remove_observer(self, ws):\n        # Remove from observers\n        pass\n\n    def run(self):\n        while True:\n            # Poll oven.get_state() every sensor_time_wait\n            # Push to all observers\n            # Sleep sensor_time_wait\n            pass\n\n    def record(self, profile):\n        # Reset backlog\n        # Store profile for backlog\n        pass\n```\n\n#### 2.1.4 lib/tempSensor.py (Temperature Reading)\n\n```python\nclass TempSensor(threading.Thread):\n    def __init__(self, config):\n        # Setup SPI for MAX31855/56\n        # Configure thermocouple type\n        pass\n\n    def read_temperature(self):\n        # Read from MAX31855/56 via SPI\n        # Return temperature in config temp_scale\n        # Apply offset if configured\n        pass\n\n    def run(self):\n        while True:\n            # Continuously read temperature\n            # Store latest reading\n            # Sleep briefly\n            pass\n```\n\n### 2.2 Configuration (config.py)\n\n```python\n# Hardware Configuration\nSPI_HARDWARE = True  # True for hardware SPI, False for software\nSENSOR_TYPE = \"MAX31856\"  # or \"MAX31855\"\nTHERMOCOUPLE_TYPE = \"K\"  # K, J, etc.\n\n# GPIO Pin Configuration\nPIN_SSR = 18  # Main SSR control\nPIN_SAFETY_RELAY = 23  # Safety relay control\nPIN_LID_SWITCH = 24  # Lid switch input\n\n# Oven Parameters\nKW_ELEMENTS = 7.1  # Heating element power in kW\nEMERGENCY_SHUTOFF_TEMP = 2264  # Safety limit (configurable scale bug)\nMAX_SSR_ON_TIME = 6  # Maximum SSR on-time per cycle\n\n# PID Parameters\nPID_KP = 3\nPID_KI = 75\nPID_KD = 12\nPID_CONTROL_WINDOW = 50  # Temperature window for catching up\n\n# Timing\nSENSOR_TIME_WAIT = 3  # Seconds between readings\nDUTY_CYCLE = SENSOR_TIME_WAIT\n\n# Display Configuration\nTEMP_SCALE = \"c\"  # \"c\" or \"f\"\nTIME_SCALE_SLOPE = \"h\"  # Slope display: s/m/h\nTIME_SCALE_PROFILE = \"m\"  # Profile time: s/m/h\nKWH_RATE = 0.25  # Price per kWh\nCURRENCY_TYPE = \"€\"\n\n# Restart Configuration\nAUTOMATIC_RESTARTS = True\nAUTOMATIC_RESTART_WINDOW = 15  # Minutes\nSEEK_START = True  # Auto-seek on hot start\n\n# Storage Paths\nSTORAGE_DIR = \"storage\"\nPROFILES_DIR = \"storage/profiles\"\nSTATE_FILE = \"state.json\"\n```\n\n### 2.3 Data Models\n\n#### 2.3.1 Profile Model\n```python\nclass Profile:\n    def __init__(self, name, data, temp_units=\"c\"):\n        self.name = name\n        self.type = \"profile\"\n        self.data = data  # [[seconds, temperature], ...]\n        self.temp_units = temp_units\n\n    def get_target_temperature(self, time):\n        # Linear interpolation between data points\n        # Return 0 if beyond last point\n        pass\n\n    def duration(self):\n        # Return max time in seconds\n        pass\n\n    def to_json(self):\n        # Serialize to JSON\n        pass\n\n    @classmethod\n    def from_json(cls, json_str):\n        # Deserialize from JSON\n        pass\n```\n\n### 2.4 Emergency & Safety Features\n\n```python\nclass Oven:\n    def reset_if_emergency(self):\n        # Check temperature >= emergency_shutoff_temp\n        # Check thermocouple error rate > limit\n        # Check individual TC faults\n        # Abort if any condition met (unless ignored)\n        pass\n\n    def check_thermocouple_errors(self):\n        # Count errors over sample window\n        # Return error rate\n        pass\n```\n\n### 2.5 Automatic Restart\n\n```python\nclass Oven:\n    def save_automatic_restart_state(self):\n        # Write current state to state.json every duty cycle\n        # Include: profile, runtime, state, timestamp\n        pass\n\n    @classmethod\n    def check_automatic_restart(cls):\n        # On boot, check if state.json exists\n        # Check if state is RUNNING and recent\n        # Reload profile and resume at runtime\n        pass\n```\n\n### 2.6 systemd Service\n\n**File: /etc/systemd/system/kiln-controller.service**\n```ini\n[Unit]\nDescription=Kiln Controller Service\nAfter=network.target\n\n[Service]\nType=simple\nUser=pi\nWorkingDirectory=/home/pi/kiln-controller\nEnvironment=PATH=/home/pi/kiln-controller/venv/bin\nExecStart=/home/pi/kiln-controller/venv/bin/python kiln-controller.py\nRestart=always\nRestartSec=10\n\n[Install]\nWantedBy=multi-user.target\n```\n\n---\n\n## 3. iOS Swift Frontend Implementation\n\n### 3.1 Project Structure\n\n```\nKilnControllerV2/\n├── App/\n│   ├── KilnControllerApp.swift        # App entry point\n│   ├── AppDelegate.swift              # App lifecycle\n│   └── SceneDelegate.swift            # Scene management\n├── Models/\n│   ├── Profile.swift                  # Firing profile model\n│   ├── KilnState.swift                # Current kiln state\n│   ├── PIDStats.swift                 # PID statistics\n│   ├── ControllerConfig.swift         # Configuration\n│   ├── BacklogMessage.swift           # Backlog message\n│   └── WebSocketMessage.swift         # Generic WS message\n├── ViewModels/\n│   ├── DashboardViewModel.swift       # Dashboard logic\n│   ├── ProgramsViewModel.swift        # Programs list logic\n│   ├── ProgramEditorViewModel.swift   # Profile editing logic\n│   ├── GraphViewModel.swift           # Temperature graph logic\n│   ├── SettingsViewModel.swift        # Settings logic\n│   └── ConnectionViewModel.swift      # Connection management\n├── Views/\n│   ├── Dashboard/\n│   │   ├── DashboardView.swift        # Main dashboard\n│   │   ├── StatusCardView.swift       # Status display\n│   │   ├── TemperatureGaugeView.swift # Temperature visualization\n│   │   └── QuickActionsView.swift     # Quick action buttons\n│   ├── Programs/\n│   │   ├── ProgramsListView.swift     # Profile list\n│   │   ├── ProgramEditorView.swift    # Profile editor\n│   │   ├── ProgramCardView.swift      # Profile card\n│   │   └── SegmentRowView.swift       # Temperature point row\n│   ├── Graph/\n│   │   └── GraphView.swift            # Temperature chart\n│   ├── Settings/\n│   │   ├── SettingsView.swift         # Settings screen\n│   │   └── ConnectionSetupView.swift  # Connection configuration\n│   └── Components/\n│       ├── TempDisplay.swift          # Temperature display\n│       ├── ConnectionIndicator.swift  # Connection status\n│       └── LoadingOverlay.swift       # Loading spinner\n├── Services/\n│   ├── WebSocketService.swift         # WebSocket manager (4 sockets)\n│   ├── ControllerAPI.swift            # REST API client\n│   ├── KeychainService.swift          # Secure storage\n│   └── ReachabilityService.swift      # Network connectivity\n├── Utilities/\n│   ├── TemperatureFormatter.swift     # Temperature formatting\n│   ├── Extensions.swift               # Swift extensions\n│   └── HapticsManager.swift           # Haptic feedback\n├── Resources/\n│   ├── Assets.xcassets                # Images, colors\n│   └── Localizable.strings            # Localization\n└── Tests/\n    ├── KilnControllerV2Tests/         # Unit tests\n    └── KilnControllerV2UITests/       # UI tests\n```\n\n### 3.2 Models\n\n#### 3.2.1 Profile.swift\n```swift\nstruct Profile: Codable, Identifiable {\n    let id = UUID()\n    let type: String  // Always \"profile\"\n    var name: String\n    var tempUnits: String  // \"c\" or \"f\"\n    var data: [[Double]]  // [[seconds, temperature], ...]\n\n    enum CodingKeys: String, CodingKey {\n        case type, name, tempUnits = \"temp_units\", data\n    }\n\n    func getTargetTemperature(at time: Double) -> Double {\n        // Linear interpolation between data points\n        // Return 0 if beyond last point\n        let sortedData = data.sorted { $0[0] < $1[0] }\n        guard let lastPoint = sortedData.last else { return 0 }\n\n        if time >= lastPoint[0] {\n            return 0\n        }\n\n        for i in 0..<sortedData.count - 1 {\n            let current = sortedData[i]\n            let next = sortedData[i + 1]\n\n            if time >= current[0] && time <= next[0] {\n                let ratio = (time - current[0]) / (next[0] - current[0])\n                return current[1] + ratio * (next[1] - current[1])\n            }\n        }\n\n        return 0\n    }\n\n    var duration: Double {\n        return data.map { $0[0] }.max() ?? 0\n    }\n}\n```\n\n#### 3.2.2 KilnState.swift\n```swift\nstruct KilnState: Codable {\n    let cost: Double\n    let runtime: Double\n    let temperature: Double\n    let target: Double\n    let state: OvenState\n    let heat: Double  // 0.0 off / 1.0 on\n    let heatRate: Double  // degrees per hour\n    let totalTime: Double\n    let kwhRate: Double\n    let currencyType: String\n    let profile: String?\n    let pidstats: PIDStats?\n    let catchingUp: Bool\n\n    enum CodingKeys: String, CodingKey {\n        case cost, runtime, temperature, target, state\n        case heat, heatRate = \"heat_rate\", totalTime = \"totaltime\"\n        case kwhRate = \"kwh_rate\", currencyType = \"currency_type\"\n        case profile, pidstats, catchingUp = \"catching_up\"\n    }\n}\n\nenum OvenState: String, Codable {\n    case idle = \"IDLE\"\n    case running = \"RUNNING\"\n    case paused = \"PAUSED\"\n}\n```\n\n#### 3.2.3 PIDStats.swift\n```swift\nstruct PIDStats: Codable {\n    let time: Double  // Unix timestamp\n    let timeDelta: Double  // Seconds since previous compute\n    let setpoint: Double  // Target temp\n    let ispoint: Double  // Measured temp\n    let err: Double  // setpoint - ispoint\n    let errDelta: Double  // err - lastErr\n    let p: Double  // kp * err\n    let i: Double  // integral term\n    let d: Double  // kd * dErr\n    let kp: Double  // proportional gain\n    let ki: Double  // integral gain\n    let kd: Double  // derivative gain\n    let pid: Double  // raw combined output\n    let out: Double  // normalised 0..1 output\n\n    var heatPercentage: Double {\n        return out * 100\n    }\n}\n```\n\n#### 3.2.4 ControllerConfig.swift\n```swift\nstruct ControllerConfig: Codable {\n    let tempScale: String  // \"c\" or \"f\"\n    let timeScaleSlope: String  // s/m/h\n    let timeScaleProfile: String  // s/m/h\n    let kwhRate: Double\n    let currencyType: String\n\n    enum CodingKeys: String, CodingKey {\n        case tempScale = \"temp_scale\"\n        case timeScaleSlope = \"time_scale_slope\"\n        case timeScaleProfile = \"time_scale_profile\"\n        case kwhRate = \"kwh_rate\"\n        case currencyType = \"currency_type\"\n    }\n}\n```\n\n#### 3.2.5 BacklogMessage.swift\n```swift\nstruct BacklogMessage: Codable {\n    let type: String  // \"backlog\"\n    let profile: Profile?\n    let log: [KilnState]\n\n    enum CodingKeys: String, CodingKey {\n        case type, profile, log\n    }\n}\n```\n\n### 3.3 Services\n\n#### 3.3.1 WebSocketService.swift\n\n```swift\nimport Foundation\nimport Combine\n\nclass WebSocketService: ObservableObject {\n    private let baseURL: String\n    private let port: Int\n\n    // Four independent WebSocket connections\n    private var statusTask: URLSessionWebSocketTask?\n    private var controlTask: URLSessionWebSocketTask?\n    private var storageTask: URLSessionWebSocketTask?\n    private var configTask: URLSessionWebSocketTask?\n\n    // Published state\n    @Published var isConnected = false\n    @Published var currentProfile: Profile?\n    @Published var temperatureHistory: [(time: Double, temp: Double)] = []\n\n    // Callbacks\n    var onStateUpdate: ((KilnState) -> Void)?\n    var onConfigUpdate: ((ControllerConfig) -> Void)?\n    var onProfilesUpdate: (([Profile]) -> Void)?\n    var onConnectionError: ((Error) -> Void)?\n\n    init(baseURL: String, port: Int = 8080) {\n        self.baseURL = baseURL\n        self.port = port\n    }\n\n    func connect() {\n        connectStatus()\n        connectControl()\n        connectStorage()\n        connectConfig()\n    }\n\n    func disconnect() {\n        statusTask?.cancel()\n        controlTask?.cancel()\n        storageTask?.cancel()\n        configTask?.cancel()\n        isConnected = false\n    }\n\n    // MARK: - /status WebSocket\n\n    private func connectStatus() {\n        let url = URL(string: \"ws://\\(baseURL):\\(port)/status\")!\n        statusTask = URLSession.shared.webSocketTask(with: url)\n\n        statusTask?.resume()\n        receiveStatusMessages()\n        isConnected = true\n    }\n\n    private func receiveStatusMessages() {\n        statusTask?.receive { [weak self] result in\n            switch result {\n            case .success(let message):\n                switch message {\n                case .string(let text):\n                    self?.handleStatusMessage(text)\n                case .data(let data):\n                    if let text = String(data: data, encoding: .utf8) {\n                        self?.handleStatusMessage(text)\n                    }\n                @unknown default:\n                    break\n                }\n                self?.receiveStatusMessages()  // Continue receiving\n            case .failure(let error):\n                self?.onConnectionError?(error)\n                self?.isConnected = false\n                // Reconnect with backoff\n                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {\n                    self?.connectStatus()\n                }\n            }\n        }\n    }\n\n    private func handleStatusMessage(_ text: String) {\n        guard let data = text.data(using: .utf8) else { return }\n\n        // Try to decode as BacklogMessage first\n        if let backlog = try? JSONDecoder().decode(BacklogMessage.self, from: data),\n           backlog.type == \"backlog\" {\n            // Handle backlog\n            currentProfile = backlog.profile\n            temperatureHistory = backlog.log.map { (time: $0.runtime, temp: $0.temperature) }\n            onStateUpdate?(backlog.log.last ?? KilnState.placeholder)\n            return\n        }\n\n        // Otherwise, it's a live state update\n        if let state = try? JSONDecoder().decode(KilnState.self, from: data) {\n            onStateUpdate?(state)\n            temperatureHistory.append((time: state.runtime, temp: state.temperature))\n        }\n    }\n\n    // MARK: - /control WebSocket\n\n    private func connectControl() {\n        let url = URL(string: \"ws://\\(baseURL):\\(port)/control\")!\n        controlTask = URLSession.shared.webSocketTask(with: url)\n        controlTask?.resume()\n    }\n\n    func sendRunCommand(profile: Profile) {\n        let message = [\n            \"cmd\": \"RUN\",\n            \"profile\": profile\n        ] as [String : Any]\n\n        guard let data = try? JSONSerialization.data(withJSONObject: message),\n              let text = String(data: data, encoding: .utf8) else { return }\n\n        controlTask?.send(.string(text)) { error in\n            if let error = error {\n                print(\"Error sending RUN command: \\(error)\")\n            }\n        }\n    }\n\n    func sendStopCommand() {\n        let message = [\"cmd\": \"STOP\"]\n\n        guard let data = try? JSONSerialization.data(withJSONObject: message),\n              let text = String(data: data, encoding: .utf8) else { return }\n\n        controlTask?.send(.string(text)) { error in\n            if let error = error {\n                print(\"Error sending STOP command: \\(error)\")\n            }\n        }\n    }\n\n    // MARK: - /storage WebSocket\n\n    private func connectStorage() {\n        let url = URL(string: \"ws://\\(baseURL):\\(port)/storage\")!\n        storageTask = URLSession.shared.webSocketTask(with: url)\n        storageTask?.resume()\n        receiveStorageMessages()\n    }\n\n    private func receiveStorageMessages() {\n        storageTask?.receive { [weak self] result in\n            switch result {\n            case .success(let message):\n                switch message {\n                case .string(let text):\n                    self?.handleStorageMessage(text)\n                default:\n                    break\n                }\n                self?.receiveStorageMessages()\n            case .failure(let error):\n                print(\"Storage WebSocket error: \\(error)\")\n                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {\n                    self?.connectStorage()\n                }\n            }\n        }\n    }\n\n    private func handleStorageMessage(_ text: String) {\n        // Try to decode as profile array first\n        if let data = text.data(using: .utf8),\n           let profiles = try? JSONDecoder().decode([Profile].self, from: data) {\n            onProfilesUpdate?(profiles)\n            return\n        }\n\n        // Handle PUT/DELETE responses\n        if let data = text.data(using: .utf8),\n           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],\n           let resp = dict[\"resp\"] as? String {\n            if resp == \"OK\" {\n                // Success - request full list\n                requestProfilesList()\n            }\n        }\n    }\n\n    func requestProfilesList() {\n        storageTask?.send(.string(\"GET\")) { error in\n            if let error = error {\n                print(\"Error requesting profiles: \\(error)\")\n            }\n        }\n    }\n\n    func saveProfile(_ profile: Profile, force: Bool = false) {\n        let message: [String: Any] = [\n            \"cmd\": \"PUT\",\n            \"profile\": profile,\n            \"force\": force\n        ]\n\n        guard let data = try? JSONSerialization.data(withJSONObject: message),\n              let text = String(data: data, encoding: .utf8) else { return }\n\n        storageTask?.send(.string(text)) { error in\n            if let error = error {\n                print(\"Error saving profile: \\(error)\")\n            }\n        }\n    }\n\n    func deleteProfile(name: String) {\n        let message: [String: Any] = [\n            \"cmd\": \"DELETE\",\n            \"profile\": [\"name\": name]\n        ]\n\n        guard let data = try? JSONSerialization.data(withJSONObject: message),\n              let text = String(data: data, encoding: .utf8) else { return }\n\n        storageTask?.send(.string(text)) { error in\n            if let error = error {\n                print(\"Error deleting profile: \\(error)\")\n            }\n        }\n    }\n\n    // MARK: - /config WebSocket\n\n    private func connectConfig() {\n        let url = URL(string: \"ws://\\(baseURL):\\(port)/config\")!\n        configTask = URLSession.shared.webSocketTask(with: url)\n        configTask?.resume()\n        receiveConfigMessages()\n        requestConfig()\n    }\n\n    private func receiveConfigMessages() {\n        configTask?.receive { [weak self] result in\n            switch result {\n            case .success(let message):\n                switch message {\n                case .string(let text):\n                    self?.handleConfigMessage(text)\n                default:\n                    break\n                }\n                self?.receiveConfigMessages()\n            case .failure(let error):\n                print(\"Config WebSocket error: \\(error)\")\n                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {\n                    self?.connectConfig()\n                }\n            }\n        }\n    }\n\n    private func handleConfigMessage(_ text: String) {\n        if let data = text.data(using: .utf8),\n           let config = try? JSONDecoder().decode(ControllerConfig.self, from: data) {\n            onConfigUpdate?(config)\n        }\n    }\n\n    func requestConfig() {\n        configTask?.send(.string(\"GET\")) { error in\n            if let error = error {\n                print(\"Error requesting config: \\(error)\")\n            }\n        }\n    }\n}\n\nextension KilnState {\n    static var placeholder: KilnState {\n        return KilnState(\n            cost: 0,\n            runtime: 0,\n            temperature: 0,\n            target: 0,\n            state: .idle,\n            heat: 0,\n            heatRate: 0,\n            totalTime: 0,\n            kwhRate: 0.25,\n            currencyType: \"€\",\n            profile: nil,\n            pidstats: nil,\n            catchingUp: false\n        )\n    }\n}\n```\n\n#### 3.3.2 ControllerAPI.swift\n\n```swift\nimport Foundation\nimport Combine\n\nclass ControllerAPI {\n    private let baseURL: String\n    private let port: Int\n    private let session: URLSession\n\n    init(baseURL: String, port: Int = 8080) {\n        self.baseURL = baseURL\n        self.port = port\n        self.session = URLSession(configuration: .default)\n    }\n\n    private func buildURL(path: String) -> URL {\n        return URL(string: \"http://\\(baseURL):\\(port)\\(path)\")!\n    }\n\n    // MARK: - Health Check\n\n    func checkConnection() -> AnyPublisher<Bool, Error> {\n        let url = buildURL(path: \"/api/stats\")\n\n        return session.dataTaskPublisher(for: url)\n            .map { data, response in\n                // Treat empty 200 body as healthy/idle\n                if let httpResponse = response as? HTTPURLResponse {\n                    return httpResponse.statusCode == 200\n                }\n                return false\n            }\n            .catch { _ in\n                Just(false)\n                    .setFailureType(to: Error.self)\n            }\n            .eraseToAnyPublisher()\n    }\n\n    // MARK: - Commands\n\n    func runProfile(name: String, startAt: Int = 0) -> AnyPublisher<Bool, Error> {\n        let url = buildURL(path: \"/api\")\n        var request = URLRequest(url: url)\n        request.httpMethod = \"POST\"\n        request.setValue(\"application/json\", forHTTPHeaderField: \"Content-Type\")\n\n        let body: [String: Any] = [\n            \"cmd\": \"run\",\n            \"profile\": name,\n            \"startat\": startAt\n        ]\n\n        request.httpBody = try? JSONSerialization.data(withJSONObject: body)\n\n        return session.dataTaskPublisher(for: request)\n            .map { data, _ in\n                guard let response = try? JSONDecoder().decode(CommandResponse.self, from: data) else {\n                    return false\n                }\n                return response.success\n            }\n            .eraseToAnyPublisher()\n    }\n\n    func pause() -> AnyPublisher<Bool, Error> {\n        return sendCommand(\"pause\")\n    }\n\n    func resume() -> AnyPublisher<Bool, Error> {\n        return sendCommand(\"resume\")\n    }\n\n    func stop() -> AnyPublisher<Bool, Error> {\n        return sendCommand(\"stop\")\n    }\n\n    func sendMemo(_ text: String) -> AnyPublisher<Bool, Error> {\n        let url = buildURL(path: \"/api\")\n        var request = URLRequest(url: url)\n        request.httpMethod = \"POST\"\n        request.setValue(\"application/json\", forHTTPHeaderField: \"Content-Type\")\n\n        let body: [String: Any] = [\n            \"cmd\": \"memo\",\n            \"memo\": text\n        ]\n\n        request.httpBody = try? JSONSerialization.data(withJSONObject: body)\n\n        return session.dataTaskPublisher(for: request)\n            .map { data, _ in\n                guard let response = try? JSONDecoder().decode(CommandResponse.self, from: data) else {\n                    return false\n                }\n                return response.success\n            }\n            .eraseToAnyPublisher()\n    }\n\n    func getStats() -> AnyPublisher<PIDStats?, Error> {\n        let url = buildURL(path: \"/api/stats\")\n\n        return session.dataTaskPublisher(for: url)\n            .map { data, _ in\n                // Empty body means idle\n                guard !data.isEmpty else { return nil }\n                return try? JSONDecoder().decode(PIDStats.self, from: data)\n            }\n            .eraseToAnyPublisher()\n    }\n\n    // MARK: - Helpers\n\n    private func sendCommand(_ cmd: String) -> AnyPublisher<Bool, Error> {\n        let url = buildURL(path: \"/api\")\n        var request = URLRequest(url: url)\n        request.httpMethod = \"POST\"\n        request.setValue(\"application/json\", forHTTPHeaderField: \"Content-Type\")\n\n        let body: [String: Any] = [\"cmd\": cmd]\n        request.httpBody = try? JSONSerialization.data(withJSONObject: body)\n\n        return session.dataTaskPublisher(for: request)\n            .map { data, _ in\n                guard let response = try? JSONDecoder().decode(CommandResponse.self, from: data) else {\n                    return false\n                }\n                return response.success\n            }\n            .eraseToAnyPublisher()\n    }\n}\n\nstruct CommandResponse: Codable {\n    let success: Bool\n    let error: String?\n}\n```\n\n#### 3.3.3 KeychainService.swift\n\n```swift\nimport Foundation\nimport Security\n\nclass KeychainService {\n    static let shared = KeychainService()\n\n    private let service = \"com.kilncontroller\"\n\n    private init() {}\n\n    func save(_ data: Data, forKey key: String) -> Bool {\n        let query = [\n            kSecValueData: data,\n            kSecClass: kSecClassGenericPassword,\n            kSecAttrService: service,\n            kSecAttrAccount: key,\n            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked\n        ] as CFDictionary\n\n        SecItemDelete(query)  // Delete existing item if any\n\n        let status = SecItemAdd(query, nil)\n        return status == errSecSuccess\n    }\n\n    func load(forKey key: String) -> Data? {\n        let query = [\n            kSecClass: kSecClassGenericPassword,\n            kSecAttrService: service,\n            kSecAttrAccount: key,\n            kSecReturnData: true,\n            kSecMatchLimit: kSecMatchLimitOne\n        ] as CFDictionary\n\n        var dataTypeRef: AnyObject?\n        let status = SecItemCopyMatching(query, &dataTypeRef)\n\n        if status == errSecSuccess {\n            return dataTypeRef as? Data\n        }\n\n        return nil\n    }\n\n    func delete(forKey key: String) -> Bool {\n        let query = [\n            kSecClass: kSecClassGenericPassword,\n            kSecAttrService: service,\n            kSecAttrAccount: key\n        ] as CFDictionary\n\n        let status = SecItemDelete(query)\n        return status == errSecSuccess\n    }\n}\n\n// Convenience methods for connection settings\nextension KeychainService {\n    private enum Keys {\n        static let host = \"host\"\n        static let port = \"port\"\n    }\n\n    func saveConnection(host: String, port: Int) {\n        if let hostData = host.data(using: .utf8) {\n            save(hostData, forKey: Keys.host)\n        }\n        if let portData = String(port).data(using: .utf8) {\n            save(portData, forKey: Keys.port)\n        }\n    }\n\n    func loadConnection() -> (host: String, port: Int)? {\n        guard let hostData = load(forKey: Keys.host),\n              let portData = load(forKey: Keys.port),\n              let host = String(data: hostData, encoding: .utf8),\n              let portString = String(data: portData, encoding: .utf8),\n              let port = Int(portString) else {\n            return nil\n        }\n        return (host, port)\n    }\n\n    func clearConnection() {\n        delete(forKey: Keys.host)\n        delete(forKey: Keys.port)\n    }\n}\n```\n\n### 3.4 ViewModels\n\n#### 3.4.1 DashboardViewModel.swift\n\n```swift\nimport Foundation\nimport Combine\n\nclass DashboardViewModel: ObservableObject {\n    @Published var currentState: KilnState = .placeholder\n    @Published var isConnected = false\n    @Published var isConnecting = false\n    @Published var errorMessage: String?\n\n    private let webSocketService: WebSocketService\n    private let controllerAPI: ControllerAPI\n    private var cancellables = Set<AnyCancellable>()\n\n    init(webSocketService: WebSocketService, controllerAPI: ControllerAPI) {\n        self.webSocketService = webSocketService\n        self.controllerAPI = controllerAPI\n\n        setupBindings()\n    }\n\n    private func setupBindings() {\n        webSocketService.$isConnected\n            .assign(to: &$isConnected)\n\n        webSocketService.onStateUpdate = { [weak self] state in\n            DispatchQueue.main.async {\n                self?.currentState = state\n            }\n        }\n\n        webSocketService.onConnectionError = { [weak self] error in\n            DispatchQueue.main.async {\n                self?.errorMessage = error.localizedDescription\n            }\n        }\n    }\n\n    // MARK: - Commands\n\n    func pause() {\n        // Only allow pause when RUNNING (to avoid server bug)\n        guard currentState.state == .running else { return }\n\n        controllerAPI.pause()\n            .sink(\n                receiveCompletion: { completion in\n                    if case .failure(let error) = completion {\n                        self.errorMessage = \"Failed to pause: \\(error.localizedDescription)\"\n                    }\n                },\n                receiveValue: { success in\n                    if !success {\n                        self.errorMessage = \"Pause command failed\"\n                    }\n                }\n            )\n            .store(in: &cancellables)\n    }\n\n    func resume() {\n        // Only allow resume when PAUSED (to avoid server bug)\n        guard currentState.state == .paused else { return }\n\n        controllerAPI.resume()\n            .sink(\n                receiveCompletion: { completion in\n                    if case .failure(let error) = completion {\n                        self.errorMessage = \"Failed to resume: \\(error.localizedDescription)\"\n                    }\n                },\n                receiveValue: { success in\n                    if !success {\n                        self.errorMessage = \"Resume command failed\"\n                    }\n                }\n            )\n            .store(in: &cancellables)\n    }\n\n    func stop() {\n        controllerAPI.stop()\n            .sink(\n                receiveCompletion: { completion in\n                    if case .failure(let error) = completion {\n                        self.errorMessage = \"Failed to stop: \\(error.localizedDescription)\"\n                    }\n                },\n                receiveValue: { success in\n                    if !success {\n                        self.errorMessage = \"Stop command failed\"\n                    }\n                }\n            )\n            .store(in: &cancellables)\n    }\n\n    // MARK: - Computed Properties\n\n    var temperatureDisplay: String {\n        let formatter = TemperatureFormatter()\n        return formatter.format(currentState.temperature)\n    }\n\n    var targetDisplay: String {\n        let formatter = TemperatureFormatter()\n        return formatter.format(currentState.target)\n    }\n\n    var heatPercentage: Int {\n        guard let pidstats = currentState.pidstats else { return 0 }\n        return Int(pidstats.heatPercentage)\n    }\n\n    var isIdle: Bool {\n        return currentState.state == .idle\n    }\n\n    var isRunning: Bool {\n        return currentState.state == .running\n    }\n\n    var isPaused: Bool {\n        return currentState.state == .paused\n    }\n\n    var elapsedTimeString: String {\n        let hours = Int(currentState.runtime) / 3600\n        let minutes = (Int(currentState.runtime) % 3600) / 60\n        let seconds = Int(currentState.runtime) % 60\n\n        if hours > 0 {\n            return String(format: \"%02d:%02d:%02d\", hours, minutes, seconds)\n        } else {\n            return String(format: \"%02d:%02d\", minutes, seconds)\n        }\n    }\n\n    var totalTimeString: String {\n        let hours = Int(currentState.totalTime) / 3600\n        let minutes = (Int(currentState.totalTime) % 3600) / 60\n\n        if hours > 0 {\n            return \"\\(hours)h \\(minutes)m\"\n        } else {\n            return \"\\(minutes)m\"\n        }\n    }\n\n    var costDisplay: String {\n        return String(format: \"%.2f %@\", currentState.cost, currentState.currencyType)\n    }\n\n    var heatRateDisplay: String {\n        return String(format: \"%.1f°/hr\", currentState.heatRate)\n    }\n}\n```\n\n#### 3.4.2 ProgramsViewModel.swift\n\n```swift\nimport Foundation\nimport Combine\n\nclass ProgramsViewModel: ObservableObject {\n    @Published var profiles: [Profile] = []\n    @Published var isLoading = false\n    @Published var errorMessage: String?\n    @Published var showDeleteAlert = false\n    @Published var profileToDelete: Profile?\n\n    private let webSocketService: WebSocketService\n    private var cancellables = Set<AnyCancellable>()\n\n    init(webSocketService: WebSocketService) {\n        self.webSocketService = webSocketService\n\n        setupBindings()\n    }\n\n    private func setupBindings() {\n        webSocketService.onProfilesUpdate = { [weak self] profiles in\n            DispatchQueue.main.async {\n                self?.profiles = profiles\n                self?.isLoading = false\n            }\n        }\n    }\n\n    func loadProfiles() {\n        isLoading = true\n        webSocketService.requestProfilesList()\n    }\n\n    func saveProfile(_ profile: Profile) {\n        webSocketService.saveProfile(profile, force: false)\n    }\n\n    func forceSaveProfile(_ profile: Profile) {\n        webSocketService.saveProfile(profile, force: true)\n    }\n\n    func confirmDelete(_ profile: Profile) {\n        profileToDelete = profile\n        showDeleteAlert = true\n    }\n\n    func deleteProfile() {\n        guard let profile = profileToDelete else { return }\n\n        webSocketService.deleteProfile(name: profile.name)\n        profileToDelete = nil\n        showDeleteAlert = false\n    }\n}\n```\n\n### 3.5 Views\n\n#### 3.5.1 DashboardView.swift\n\n```swift\nimport SwiftUI\n\nstruct DashboardView: View {\n    @StateObject private var viewModel: DashboardViewModel\n    @State private var showingSettings = false\n\n    init(viewModel: DashboardViewModel) {\n        _viewModel = StateObject(wrappedValue: viewModel)\n    }\n\n    var body: some View {\n        NavigationView {\n            ScrollView {\n                VStack(spacing: 20) {\n                    // Connection Status\n                    ConnectionIndicator(\n                        isConnected: viewModel.isConnected,\n                        errorMessage: viewModel.errorMessage\n                    )\n\n                    if viewModel.isConnected {\n                        // Temperature Gauge\n                        TemperatureGaugeView(\n                            current: viewModel.currentState.temperature,\n                            target: viewModel.currentState.target,\n                            state: viewModel.currentState.state\n                        )\n\n                        // Status Card\n                        StatusCardView(viewModel: viewModel)\n\n                        // Quick Actions\n                        QuickActionsView(viewModel: viewModel)\n\n                        // Additional Stats\n                        StatsView(viewModel: viewModel)\n                    }\n                }\n                .padding()\n            }\n            .navigationTitle(\"Kiln Controller\")\n            .toolbar {\n                ToolbarItem(placement: .navigationBarTrailing) {\n                    Button(action: { showingSettings = true }) {\n                        Image(systemName: \"gearshape\")\n                    }\n                }\n            }\n            .sheet(isPresented: $showingSettings) {\n                SettingsView()\n            }\n        }\n    }\n}\n```\n\n#### 3.5.2 ProgramsListView.swift\n\n```swift\nimport SwiftUI\n\nstruct ProgramsListView: View {\n    @StateObject private var viewModel: ProgramsViewModel\n    @State private var showingEditor = false\n    @State private var editingProfile: Profile?\n\n    init(viewModel: ProgramsViewModel) {\n        _viewModel = StateObject(wrappedValue: viewModel)\n    }\n\n    var body: some View {\n        NavigationView {\n            ZStack {\n                if viewModel.isLoading {\n                    ProgressView(\"Loading profiles...\")\n                } else if viewModel.profiles.isEmpty {\n                    Text(\"No profiles found\")\n                        .foregroundColor(.secondary)\n                } else {\n                    List {\n                        ForEach(viewModel.profiles) { profile in\n                            NavigationLink(destination: ProfileDetailView(profile: profile)) {\n                                ProgramCardView(profile: profile)\n                            }\n                        }\n                    }\n                }\n            }\n            .navigationTitle(\"Firing Programs\")\n            .toolbar {\n                ToolbarItem(placement: .navigationBarTrailing) {\n                    Button(action: createNewProfile) {\n                        Image(systemName: \"plus\")\n                    }\n                }\n            }\n            .onAppear {\n                viewModel.loadProfiles()\n            }\n            .alert(\"Delete Profile\", isPresented: $viewModel.showDeleteAlert) {\n                Button(\"Cancel\", role: .cancel) { }\n                Button(\"Delete\", role: .destructive) {\n                    viewModel.deleteProfile()\n                }\n            } message: {\n                if let profile = viewModel.profileToDelete {\n                    Text(\"Are you sure you want to delete \\(profile.name)?\")\n                }\n            }\n            .sheet(isPresented: $showingEditor) {\n                if let profile = editingProfile {\n                    ProgramEditorView(profile: profile, onSave: { updatedProfile in\n                        viewModel.saveProfile(updatedProfile)\n                    })\n                } else {\n                    ProgramEditorView(profile: Profile(name: \"New Profile\", tempUnits: \"c\", data: []), onSave: { newProfile in\n                        viewModel.saveProfile(newProfile)\n                    })\n                }\n            }\n        }\n    }\n\n    private func createNewProfile() {\n        editingProfile = Profile(name: \"New Profile\", tempUnits: \"c\", data: [])\n        showingEditor = true\n    }\n}\n\nstruct ProgramCardView: View {\n    let profile: Profile\n\n    var body: some View {\n        VStack(alignment: .leading, spacing: 8) {\n            Text(profile.name)\n                .font(.headline)\n\n            Text(\"\\(profile.data.count) points\")\n                .font(.caption)\n                .foregroundColor(.secondary)\n\n            Text(\"Duration: \\(durationString)\")\n                .font(.caption)\n                .foregroundColor(.secondary)\n        }\n        .padding(.vertical, 4)\n    }\n\n    private var durationString: String {\n        let hours = Int(profile.duration) / 3600\n        let minutes = (Int(profile.duration) % 3600) / 60\n\n        if hours > 0 {\n            return \"\\(hours)h \\(minutes)m\"\n        } else {\n            return \"\\(minutes)m\"\n        }\n    }\n}\n\nstruct ProfileDetailView: View {\n    let profile: Profile\n\n    var body: some View {\n        ScrollView {\n            VStack(alignment: .leading, spacing: 20) {\n                // Profile Info\n                VStack(alignment: .leading) {\n                    Text(profile.name)\n                        .font(.title)\n                        .bold()\n\n                    Text(\"Temperature Unit: \\(profile.tempUnits.uppercased())\")\n                        .foregroundColor(.secondary)\n                }\n\n                Divider()\n\n                // Temperature Graph\n                Text(\"Temperature Schedule\")\n                    .font(.headline)\n\n                ProfileGraphView(profile: profile)\n\n                Divider()\n\n                // Temperature Points\n                Text(\"Schedule Points\")\n                    .font(.headline)\n\n                ForEach(Array(profile.data.enumerated()), id: \\.offset) { index, point in\n                    HStack {\n                        Text(\"\\(timeString(point[0]))\")\n                            .frame(width: 80, alignment: .leading)\n\n                        Spacer()\n\n                        Text(\"\\(String(format: \"%.1f\", point[1]))°\")\n                            .frame(width: 80, alignment: .trailing)\n                    }\n                    .padding(.vertical, 4)\n                }\n            }\n            .padding()\n        }\n        .navigationTitle(\"Program Details\")\n    }\n\n    private func timeString(_ seconds: Double) -> String {\n        let hours = Int(seconds) / 3600\n        let minutes = (Int(seconds) % 3600) / 60\n\n        if hours > 0 {\n            return String(format: \"%02d:%02d\", hours, minutes)\n        } else {\n            return String(format: \"%02d:%02d\", 0, minutes)\n        }\n    }\n}\n\nstruct ProfileGraphView: View {\n    let profile: Profile\n\n    var body: some View {\n        GeometryReader { geometry in\n            ZStack {\n                // Grid lines\n                Path { path in\n                    // Add grid lines here\n                }\n                .stroke(Color.gray.opacity(0.3))\n\n                // Temperature curve\n                Path { path in\n                    guard let firstPoint = profile.data.first else { return }\n\n                    let width = geometry.size.width\n                    let height = geometry.size.height\n                    let maxTime = profile.duration\n                    let maxTemp = profile.data.map { $0[1] }.max() ?? 100\n\n                    func mapPoint(_ point: [Double]) -> CGPoint {\n                        let x = (point[0] / maxTime) * width\n                        let y = height - (point[1] / maxTemp) * height\n                        return CGPoint(x: x, y: y)\n                    }\n\n                    path.move(to: mapPoint(firstPoint))\n\n                    for point in profile.data {\n                        path.addLine(to: mapPoint(point))\n                    }\n                }\n                .stroke(Color.blue, lineWidth: 2)\n            }\n        }\n        .frame(height: 200)\n        .background(Color.gray.opacity(0.1))\n        .cornerRadius(8)\n    }\n}\n```\n\n#### 3.5.3 ProgramEditorView.swift\n\n```swift\nimport SwiftUI\n\nstruct ProgramEditorView: View {\n    @Environment(\\.dismiss) var dismiss\n    @State private var profile: Profile\n    let onSave: (Profile) -> Void\n\n    @State private var showingAddPoint = false\n    @State private var newTime = \"\"\n    @State private var newTemp = \"\"\n\n    init(profile: Profile, onSave: @escaping (Profile) -> Void) {\n        _profile = State(initialValue: profile)\n        self.onSave = onSave\n    }\n\n    var body: some View {\n        NavigationView {\n            Form {\n                Section(header: Text(\"Profile Name\")) {\n                    TextField(\"Name\", text: $profile.name)\n                }\n\n                Section(header: Text(\"Temperature Points\")) {\n                    ForEach(Array(profile.data.enumerated()), id: \\.offset) { index, point in\n                        HStack {\n                            Text(\"\\(timeString(point[0]))\")\n                                .frame(width: 80, alignment: .leading)\n\n                            Text(\"\\(String(format: \"%.1f\", point[1]))°\")\n                                .frame(width: 80, alignment: .trailing)\n\n                            Spacer()\n\n                            Button(action: { deletePoint(at: index) }) {\n                                Image(systemName: \"trash\")\n                                    .foregroundColor(.red)\n                            }\n                        }\n                    }\n\n                    Button(action: { showingAddPoint = true }) {\n                        HStack {\n                            Image(systemName: \"plus.circle.fill\")\n                            Text(\"Add Point\")\n                        }\n                    }\n                }\n            }\n            .navigationTitle(\"Edit Program\")\n            .toolbar {\n                ToolbarItem(placement: .navigationBarLeading) {\n                    Button(\"Cancel\") {\n                        dismiss()\n                    }\n                }\n\n                ToolbarItem(placement: .navigationBarTrailing) {\n                    Button(\"Save\") {\n                        saveProfile()\n                    }\n                    .disabled(profile.name.isEmpty || profile.data.isEmpty)\n                }\n            }\n            .alert(\"Add Point\", isPresented: $showingAddPoint) {\n                TextField(\"Time (seconds)\", text: $newTime)\n                    .keyboardType(.numberPad)\n                TextField(\"Temperature\", text: $newTemp)\n                    .keyboardType(.decimalPad)\n\n                Button(\"Cancel\", role: .cancel) { }\n                Button(\"Add\") {\n                    addPoint()\n                }\n            }\n        }\n    }\n\n    private func addPoint() {\n        guard let time = Double(newTime),\n              let temp = Double(newTemp) else { return }\n\n        profile.data.append([time, temp])\n        profile.data.sort { $0[0] < $1[0] }\n\n        newTime = \"\"\n        newTemp = \"\"\n    }\n\n    private func deletePoint(at index: Int) {\n        profile.data.remove(at: index)\n    }\n\n    private func saveProfile() {\n        onSave(profile)\n        dismiss()\n    }\n\n    private func timeString(_ seconds: Double) -> String {\n        let hours = Int(seconds) / 3600\n        let minutes = (Int(seconds) % 3600) / 60\n\n        if hours > 0 {\n            return String(format: \"%02d:%02d\", hours, minutes)\n        } else {\n            return String(format: \"%02d:%02d\", 0, minutes)\n        }\n    }\n}\n```\n\n#### 3.5.4 SettingsView.swift\n\n```swift\nimport SwiftUI\n\nstruct SettingsView: View {\n    @Environment(\\.dismiss) var dismiss\n    @StateObject private var viewModel = SettingsViewModel()\n\n    var body: some View {\n        NavigationView {\n            Form {\n                Section(header: Text(\"Connection\")) {\n                    HStack {\n                        Text(\"Host\")\n                        Spacer()\n                        Text(viewModel.host)\n                            .foregroundColor(.secondary)\n                    }\n\n                    HStack {\n                        Text(\"Port\")\n                        Spacer()\n                        Text(\"\\(viewModel.port)\")\n                            .foregroundColor(.secondary)\n                    }\n\n                    Button(\"Test Connection\") {\n                        viewModel.testConnection()\n                    }\n                    .disabled(viewModel.isTesting)\n\n                    if viewModel.isTesting {\n                        HStack {\n                            ProgressView()\n                                .scaleEffect(0.8)\n                            Text(\"Testing...\")\n                                .foregroundColor(.secondary)\n                        }\n                    }\n                }\n\n                Section(header: Text(\"Temperature Units\")) {\n                    Picker(\"Scale\", selection: $viewModel.tempScale) {\n                        Text(\"Celsius\").tag(\"c\")\n                        Text(\"Fahrenheit\").tag(\"f\")\n                    }\n                    .pickerStyle(SegmentedPickerStyle())\n                }\n\n                Section(header: Text(\"Cost Calculation\")) {\n                    HStack {\n                        Text(\"Electricity Rate\")\n                        Spacer()\n                        TextField(\"€/kWh\", value: $viewModel.kwhRate, format: .number)\n                            .keyboardType(.decimalPad)\n                            .textFieldStyle(RoundedBorderTextFieldStyle())\n                            .frame(width: 80)\n                    }\n\n                    HStack {\n                        Text(\"Currency\")\n                        Spacer()\n                        TextField(\"Symbol\", text: $viewModel.currencyType)\n                            .textFieldStyle(RoundedBorderTextFieldStyle())\n                            .frame(width: 50)\n                    }\n                }\n\n                Section(header: Text(\"Hardware\")) {\n                    HStack {\n                        Text(\"Element Power\")\n                        Spacer()\n                        TextField(\"kW\", value: $viewModel.kwElements, format: .number)\n                            .keyboardType(.decimalPad)\n                            .textFieldStyle(RoundedBorderTextFieldStyle())\n                            .frame(width: 80)\n                    }\n\n                    Picker(\"Sensor Type\", selection: $viewModel.sensorType) {\n                        Text(\"MAX31855\").tag(\"MAX31855\")\n                        Text(\"MAX31856\").tag(\"MAX31856\")\n                    }\n\n                    Picker(\"Thermocouple\", selection: $viewModel.thermocoupleType) {\n                        Text(\"Type K\").tag(\"K\")\n                        Text(\"Type J\").tag(\"J\")\n                    }\n                }\n            }\n            .navigationTitle(\"Settings\")\n            .toolbar {\n                ToolbarItem(placement: .navigationBarLeading) {\n                    Button(\"Done\") {\n                        dismiss()\n                    }\n                }\n\n                ToolbarItem(placement: .navigationBarTrailing) {\n                    Button(\"Save\") {\n                        viewModel.saveSettings()\n                        dismiss()\n                    }\n                }\n            }\n            .alert(\"Connection Test\", isPresented: $viewModel.showingAlert) {\n                Button(\"OK\", role: .cancel) { }\n            } message: {\n                Text(viewModel.alertMessage)\n            }\n        }\n    }\n}\n```\n\n#### 3.5.5 ConnectionSetupView.swift\n\n```swift\nimport SwiftUI\n\nstruct ConnectionSetupView: View {\n    @Environment(\\.dismiss) var dismiss\n    @State private var host: String = \"\"\n    @State private var port: String = \"8080\"\n    @State private var isTesting = false\n    @State private var testResult: String?\n    @State private var showError = false\n\n    var body: some View {\n        NavigationView {\n            Form {\n                Section(header: Text(\"Server Address\")) {\n                    TextField(\"Host IP\", text: $host)\n                        .keyboardType(.numbersAndPunctuation)\n                        .autocapitalization(.none)\n\n                    TextField(\"Port\", text: $port)\n                        .keyboardType(.numberPad)\n                }\n\n                Section {\n                    Button(action: testConnection) {\n                        HStack {\n                            Spacer()\n                            if isTesting {\n                                ProgressView()\n                                    .scaleEffect(0.8)\n                                Text(\"Testing...\")\n                            } else {\n                                Text(\"Test Connection\")\n                            }\n                            Spacer()\n                        }\n                    }\n                    .disabled(host.isEmpty || port.isEmpty || isTesting)\n\n                    if let result = testResult {\n                        Text(result)\n                            .foregroundColor(result.contains(\"Success\") ? .green : .red)\n                    }\n                }\n            }\n            .navigationTitle(\"Connection Setup\")\n            .toolbar {\n                ToolbarItem(placement: .navigationBarLeading) {\n                    Button(\"Cancel\") {\n                        dismiss()\n                    }\n                }\n\n                ToolbarItem(placement: .navigationBarTrailing) {\n                    Button(\"Connect\") {\n                        saveAndConnect()\n                    }\n                    .disabled(host.isEmpty || port.isEmpty)\n                }\n            }\n            .onAppear {\n                loadSavedConnection()\n            }\n            .alert(\"Error\", isPresented: $showError) {\n                Button(\"OK\", role: .cancel) { }\n            } message: {\n                Text(testResult ?? \"Unknown error\")\n            }\n        }\n    }\n\n    private func loadSavedConnection() {\n        if let (savedHost, savedPort) = KeychainService.shared.loadConnection() {\n            host = savedHost\n            port = String(savedPort)\n        }\n    }\n\n    private func testConnection() {\n        guard let portNum = Int(port) else { return }\n\n        isTesting = true\n        testResult = nil\n\n        let api = ControllerAPI(baseURL: host, port: portNum)\n\n        api.checkConnection()\n            .sink(\n                receiveCompletion: { completion in\n                    isTesting = false\n                    if case .failure(let error) = completion {\n                        testResult = \"Failed: \\(error.localizedDescription)\"\n                        showError = true\n                    }\n                },\n                receiveValue: { success in\n                    isTesting = false\n                    testResult = success ? \"Success! Connection established.\" : \"Failed: No response\"\n                }\n            )\n            .store(in: &cancellables)\n    }\n\n    private func saveAndConnect() {\n        guard let portNum = Int(port) else { return }\n\n        KeychainService.shared.saveConnection(host: host, port: portNum)\n        dismiss()\n    }\n\n    private var cancellables = Set<AnyCancellable>()\n}\n```\n\n### 3.6 Utilities\n\n#### 3.6.1 TemperatureFormatter.swift\n\n```swift\nimport Foundation\n\nclass TemperatureFormatter {\n    private let celsiusToFahrenheit: (Double) -> Double = { c in\n        return (c * 9/5) + 32\n    }\n\n    private let fahrenheitToCelsius: (Double) -> Double = { f in\n        return (f - 32) * 5/9\n    }\n\n    enum Unit {\n        case celsius\n        case fahrenheit\n    }\n\n    func format(_ temperature: Double, unit: Unit = .celsius) -> String {\n        let value: Double\n        let symbol: String\n\n        switch unit {\n        case .celsius:\n            value = temperature\n            symbol = \"°C\"\n        case .fahrenheit:\n            value = celsiusToFahrenheit(temperature)\n            symbol = \"°F\"\n        }\n\n        return String(format: \"%.1f%@\", value, symbol)\n    }\n\n    func convert(_ temperature: Double, from: Unit, to: Unit) -> Double {\n        if from == to {\n            return temperature\n        }\n\n        switch (from, to) {\n        case (.celsius, .fahrenheit):\n            return celsiusToFahrenheit(temperature)\n        case (.fahrenheit, .celsius):\n            return fahrenheitToCelsius(temperature)\n        default:\n            return temperature\n        }\n    }\n}\n```\n\n#### 3.6.2 Extensions.swift\n\n```swift\nimport SwiftUI\n\n// MARK: - View Extensions\n\nextension View {\n    func hideKeyboard() {\n        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)\n    }\n}\n\n// MARK: - Array Extensions\n\nextension Array {\n    func chunked(into size: Int) -> [[Element]] {\n        return stride(from: 0, to: count, by: size).map {\n            Array(self[$0..<Swift.min($0 + size, count)])\n        }\n    }\n}\n\n// MARK: - String Extensions\n\nextension String {\n    var isValidIP: Bool {\n        let pattern = \"^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$\"\n        return NSPredicate(format: \"SELF MATCHES %@\", pattern).evaluate(with: self)\n    }\n}\n```\n\n#### 3.6.3 HapticsManager.swift\n\n```swift\nimport UIKit\n\nclass HapticsManager {\n    static let shared = HapticsManager()\n\n    private init() {}\n\n    enum HapticType {\n        case light\n        case medium\n        case heavy\n        case success\n        case warning\n        case error\n    }\n\n    func play(_ type: HapticType) {\n        switch type {\n        case .light:\n            let generator = UIImpactFeedbackGenerator(style: .light)\n            generator.impactOccurred()\n\n        case .medium:\n            let generator = UIImpactFeedbackGenerator(style: .medium)\n            generator.impactOccurred()\n\n        case .heavy:\n            let generator = UIImpactFeedbackGenerator(style: .heavy)\n            generator.impactOccurred()\n\n        case .success:\n            let generator = UINotificationFeedbackGenerator()\n            generator.notificationOccurred(.success)\n\n        case .warning:\n            let generator = UINotificationFeedbackGenerator()\n            generator.notificationOccurred(.warning)\n\n        case .error:\n            let generator = UINotificationFeedbackGenerator()\n            generator.notificationOccurred(.error)\n        }\n    }\n}\n```\n\n### 3.7 Main App Entry Point\n\n```swift\nimport SwiftUI\n\n@main\nstruct KilnControllerApp: App {\n    @StateObject private var appState = AppState()\n\n    var body: some Scene {\n        WindowGroup {\n            ContentView()\n                .environmentObject(appState)\n        }\n    }\n}\n\nstruct ContentView: View {\n    @EnvironmentObject var appState: AppState\n\n    var body: some View {\n        TabView {\n            DashboardView(viewModel: appState.dashboardViewModel)\n                .tabItem {\n                    Label(\"Dashboard\", systemImage: \"gauge\")\n                }\n\n            ProgramsListView(viewModel: appState.programsViewModel)\n                .tabItem {\n                    Label(\"Programs\", systemImage: \"list.bullet\")\n                }\n\n            GraphView(viewModel: appState.graphViewModel)\n                .tabItem {\n                    Label(\"Graph\", systemImage: \"chart.xyaxis.line\")\n                }\n\n            SettingsView()\n                .tabItem {\n                    Label(\"Settings\", systemImage: \"gearshape\")\n                }\n        }\n        .onAppear {\n            appState.connectIfNeeded()\n        }\n    }\n}\n```\n\n```swift\nimport Foundation\nimport Combine\n\nclass AppState: ObservableObject {\n    @Published var isConnected = false\n    @Published var currentHost: String?\n    @Published var currentPort: Int?\n\n    // Services\n    let webSocketService: WebSocketService\n    let controllerAPI: ControllerAPI\n\n    // ViewModels\n    let dashboardViewModel: DashboardViewModel\n    let programsViewModel: ProgramsViewModel\n    let graphViewModel: GraphViewModel\n\n    private var cancellables = Set<AnyCancellable>()\n\n    init() {\n        // Load connection settings\n        let (host, port) = KeychainService.shared.loadConnection() ?? (\"192.168.178.120\", 8080)\n        currentHost = host\n        currentPort = port\n\n        // Initialize services\n        webSocketService = WebSocketService(baseURL: host, port: port)\n        controllerAPI = ControllerAPI(baseURL: host, port: port)\n\n        // Initialize ViewModels\n        dashboardViewModel = DashboardViewModel(\n            webSocketService: webSocketService,\n            controllerAPI: controllerAPI\n        )\n\n        programsViewModel = ProgramsViewModel(\n            webSocketService: webSocketService\n        )\n\n        graphViewModel = GraphViewModel(\n            webSocketService: webSocketService\n        )\n\n        setupBindings()\n    }\n\n    private func setupBindings() {\n        webSocketService.$isConnected\n            .assign(to: &$isConnected)\n    }\n\n    func connectIfNeeded() {\n        if !isConnected {\n            webSocketService.connect()\n            programsViewModel.loadProfiles()\n        }\n    }\n\n    func reconnect() {\n        webSocketService.disconnect()\n        webSocketService.connect()\n        programsViewModel.loadProfiles()\n    }\n\n    func updateConnection(host: String, port: Int) {\n        currentHost = host\n        currentPort = port\n\n        // Recreate services with new connection\n        // (In a real app, you'd want to do this more carefully)\n    }\n}\n```\n\n---\n\n## 4. Hardware Integration\n\n### 4.1 Raspberry Pi 3 B Setup\n\n#### 4.1.1 Hardware Requirements\n\n- **Raspberry Pi 3 B** or newer\n- **MAX31855** or **MAX31856** thermocouple amplifier\n- **Type K Thermocouple** (or other supported type)\n- **SSR (Solid State Relay)** for heating element control\n- **Safety Relay** with lid switch\n- **Power supply** (5V 2.5A for Pi, separate for kiln)\n- **SD Card** (16GB+ Class 10)\n- **Case** with cooling\n\n#### 4.1.2 Wiring Diagram\n\n```\nRaspberry Pi 3 B GPIO\n├── SPI0 MOSI (GPIO 10) → MAX31855/56 SDI\n├── SPI0 MISO (GPIO 9)  → MAX31855/56 SDO\n├── SPI0 SCLK (GPIO 11) → MAX31855/56 SCK\n├── SPI0 CE0 (GPIO 8)   → MAX31855/56 CS\n├── GPIO 18             → SSR Control\n├── GPIO 23             → Safety Relay Control\n├── GPIO 24             → Lid Switch Input\n└── GND                 → Common Ground\n\nMAX31855/56 Thermocouple Amplifier\n├── VCC                 → 3.3V\n├── GND                 → GND\n├── T+                  → Thermocouple +\n├── T-                  → Thermocouple -\n└── SPI pins as above\n\nThermocouple (Type K)\n├── Yellow (+)          → MAX31855/56 T+\n└── Red (-)             → MAX31855/56 T-\n\nSSR (Solid State Relay)\n├── Control +           → GPIO 18\n├── Control -           → GND\n├── Load +              → Kiln Heating Element\n└── Load -              → Power Supply (L2)\n\nSafety Relay\n├── Coil +              → GPIO 23\n├── Coil -              → GND\n├── NO                  → SSR Control +\n└── COM                 → Power Supply (L1)\n\nLid Switch (Normally Open)\n├── One side            → GPIO 24\n└── Other side          → GND\n\nKiln Heating Elements\n├── Element 1           → SSR Load +\n└── Element 2           → Power Supply Neutral\n```\n\n#### 4.1.3 GPIO Configuration\n\n```python\n# config.py\nimport RPi.GPIO as GPIO\n\n# Use BCM numbering\nGPIO.setmode(GPIO.BCM)\n\n# Output pins\nPIN_SSR = 18\nPIN_SAFETY_RELAY = 23\n\n# Input pins\nPIN_LID_SWITCH = 24\n\n# Setup\nGPIO.setup(PIN_SSR, GPIO.OUT)\nGPIO.setup(PIN_SAFETY_RELAY, GPIO.OUT)\nGPIO.setup(PIN_LID_SWITCH, GPIO.IN, pull_up_down=GPIO.PUD_UP)\n\n# Initial state\nGPIO.output(PIN_SSR, GPIO.LOW)  # SSR off\nGPIO.output(PIN_SAFETY_RELAY, GPIO.LOW)  # Safety relay off\n```\n\n### 4.2 Temperature Sensor Integration\n\n#### 4.2.1 MAX31855/56 SPI Interface\n\n```python\n# lib/tempSensor.py\nimport spidev\nimport time\nfrom config import SENSOR_TYPE, THERMOCOUPLE_TYPE\n\nclass MAX31855:\n    def __init__(self, bus=0, device=0):\n        self.spi = spidev.SpiDev()\n        self.spi.open(bus, device)\n        self.spi.max_speed_hz = 5000000  # 5 MHz\n\n    def read_temp_c(self):\n        # Read 4 bytes from MAX31855\n        data = self.spi.readbytes(4)\n\n        # Convert bytes to 32-bit integer\n        value = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3]\n\n        # Check for errors\n        if value & 0x7:\n            raise ThermocoupleError(f\"Thermocouple error: 0x{value & 0x7:02x}\")\n\n        # Extract temperature (14-bit, 0.25°C resolution)\n        temp_raw = value >> 18\n\n        # Handle signed 14-bit value\n        if temp_raw & 0x2000:\n            temp_raw -= 0x4000\n\n        # Convert to Celsius\n        temp_c = temp_raw * 0.25\n\n        return temp_c\n\n    def close(self):\n        self.spi.close()\n\nclass MAX31856:\n    def __init__(self, bus=0, device=0, thermocouple_type='K'):\n        self.spi = spidev.SpiDev()\n        self.spi.open(bus, device)\n        self.spi.max_speed_hz = 5000000\n        self.thermocouple_type = thermocouple_type\n\n        # Configure MAX31856\n        self._configure()\n\n    def _configure(self):\n        # Set thermocouple type\n        type_map = {\n            'B': 0b0000,\n            'E': 0b0001,\n            'J': 0b0010,\n            'K': 0b0011,\n            'N': 0b0100,\n            'R': 0b0101,\n            'S': 0b0110,\n            'T': 0b0111,\n        }\n\n        cr0 = 0x80  # Auto conversion mode\n        cr1 = type_map.get(self.thermocouple_type, 0b0011) << 4  # Type K default\n\n        self._write_register(0x80, cr0)  # CR0\n        self._write_register(0x81, cr1)  # CR1\n\n    def _write_register(self, reg, value):\n        self.spi.xfer2([reg | 0x80, value])  # Write bit set\n\n    def _read_register(self, reg):\n        return self.spi.xfer2([reg, 0])[1]\n\n    def read_temp_c(self):\n        # Read temperature register\n        msb = self._read_register(0x0C)\n        lsb = self._read_register(0x0D)\n\n        # Check for faults\n        fault = self._read_register(0x0F)\n        if fault & 0x1F:\n            raise ThermocoupleError(f\"Thermocouple fault: 0x{fault:02x}\")\n\n        # Combine bytes and convert to temperature\n        temp_raw = (msb << 8) | lsb\n\n        # Handle signed value\n        if temp_raw & 0x8000:\n            temp_raw -= 0x10000\n\n        # Convert to Celsius (0.0078125°C resolution)\n        temp_c = temp_raw * 0.0078125\n\n        return temp_c\n\n    def close(self):\n        self.spi.close()\n\nclass ThermocoupleError(Exception):\n    pass\n```\n\n#### 4.2.2 TempSensor Thread\n\n```python\n# lib/tempSensor.py (continued)\nimport threading\nfrom config import SENSOR_TIME_WAIT, TEMP_SCALE\n\nclass TempSensor(threading.Thread):\n    def __init__(self):\n        super().__init__()\n        self.daemon = True\n        self.running = False\n        self.temperature = 0.0\n        self.error_count = 0\n        self.total_readings = 0\n\n        # Initialize sensor based on config\n        if SENSOR_TYPE == \"MAX31856\":\n            self.sensor = MAX31856(thermocouple_type=THERMOCOUPLE_TYPE)\n        else:\n            self.sensor = MAX31855()\n\n    def run(self):\n        self.running = True\n\n        while self.running:\n            try:\n                temp_c = self.sensor.read_temp_c()\n\n                # Convert to configured scale\n                if TEMP_SCALE == \"f\":\n                    temp = temp_c * 9/5 + 32\n                else:\n                    temp = temp_c\n\n                self.temperature = temp\n                self.error_count = 0\n                self.total_readings += 1\n\n            except ThermocoupleError as e:\n                self.error_count += 1\n                self.total_readings += 1\n                print(f\"Thermocouple error: {e}\")\n\n            except Exception as e:\n                print(f\"Sensor error: {e}\")\n\n            time.sleep(0.1)  # Read frequently, oven polls at SENSOR_TIME_WAIT\n\n    def get_temperature(self):\n        return self.temperature\n\n    def get_error_rate(self):\n        if self.total_readings == 0:\n            return 0.0\n        return self.error_count / self.total_readings\n\n    def stop(self):\n        self.running = False\n        self.sensor.close()\n```\n\n### 4.3 SSR & Safety Relay Control\n\n```python\n# lib/hardware.py\nimport RPi.GPIO as GPIO\nfrom config import PIN_SSR, PIN_SAFETY_RELAY, PIN_LID_SWITCH\n\nclass HardwareController:\n    def __init__(self):\n        GPIO.setmode(GPIO.BCM)\n        GPIO.setup(PIN_SSR, GPIO.OUT)\n        GPIO.setup(PIN_SAFETY_RELAY, GPIO.OUT)\n        GPIO.setup(PIN_LID_SWITCH, GPIO.IN, pull_up_down=GPIO.PUD_UP)\n\n        # Initial state - all off\n        self.ssr_on = False\n        self.safety_relay_on = False\n\n        GPIO.output(PIN_SSR, GPIO.LOW)\n        GPIO.output(PIN_SAFETY_RELAY, GPIO.LOW)\n\n    def enable_safety_relay(self):\n        \"\"\"Enable safety relay (power to SSR)\"\"\"\n        if not self.is_lid_open():\n            GPIO.output(PIN_SAFETY_RELAY, GPIO.HIGH)\n            self.safety_relay_on = True\n        else:\n            print(\"Cannot enable safety relay: lid is open\")\n\n    def disable_safety_relay(self):\n        \"\"\"Disable safety relay (cut power to SSR)\"\"\"\n        GPIO.output(PIN_SAFETY_RELAY, GPIO.LOW)\n        self.ssr_on = False  # Also turn off SSR\n        GPIO.output(PIN_SSR, GPIO.LOW)\n        self.safety_relay_on = False\n\n    def enable_ssr(self):\n        \"\"\"Enable SSR (power to heating elements)\"\"\"\n        if self.safety_relay_on and not self.is_lid_open():\n            GPIO.output(PIN_SSR, GPIO.HIGH)\n            self.ssr_on = True\n        else:\n            print(\"Cannot enable SSR: safety relay off or lid open\")\n\n    def disable_ssr(self):\n        \"\"\"Disable SSR\"\"\"\n        GPIO.output(PIN_SSR, GPIO.LOW)\n        self.ssr_on = False\n\n    def is_lid_open(self):\n        \"\"\"Check if lid switch is open\"\"\"\n        return GPIO.input(PIN_LID_SWITCH) == GPIO.LOW  # Active low\n\n    def emergency_shutdown(self):\n        \"\"\"Emergency shutdown - disable everything\"\"\"\n        self.disable_ssr()\n        self.disable_safety_relay()\n        print(\"EMERGENCY SHUTDOWN\")\n\n    def cleanup(self):\n        GPIO.cleanup()\n```\n\n---\n\n## 5. Deployment & Installation\n\n### 5.1 Raspberry Pi Setup\n\n#### 5.1.1 OS Installation\n\n1. Download Raspberry Pi OS Lite (64-bit)\n2. Flash to SD card using Raspberry Pi Imager\n3. Enable SSH and configure WiFi in `raspi-config`\n4. Update system:\n   ```bash\n   sudo apt update && sudo apt upgrade -y\n   sudo apt install -y python3 python3-pip python3-venv git\n   ```\n\n#### 5.1.2 System Dependencies\n\n```bash\n# Install system dependencies\nsudo apt install -y python3-dev libgpiod-dev\n\n# Enable SPI\nsudo raspi-config nonint do_spi 0\n\n# Enable I2C (if needed)\nsudo raspi-config nonint do_i2c 0\n\n# Enable serial (if needed)\nsudo raspi-config nonint do_serial 0\n\n# Reboot\nsudo reboot\n```\n\n#### 5.1.3 Python Environment Setup\n\n```bash\n# Create project directory\ncd ~\nmkdir kiln-controller\ncd kiln-controller\n\n# Create virtual environment\npython3 -m venv venv\nsource venv/bin/activate\n\n# Create directory structure\nmkdir -p lib storage/profiles public\n\n# Install Python dependencies\npip install --upgrade pip\npip install bottle gevent gevent-websocket RPi.GPIO spidev\n\n# Save dependencies\npip freeze > requirements.txt\n```\n\n#### 5.1.4 Application Deployment\n\n```bash\n# Copy files to Raspberry Pi\n# (Assuming files are in ~/Downloads/kiln-controller-bug-fixed)\ncp -r ~/Downloads/kiln-controller-bug-fixed/* ~/kiln-controller/\n\n# Set ownership\nsudo chown -R pi:pi ~/kiln-controller\n\n# Make scripts executable\nchmod +x kiln-controller.py\n\n# Test run\ncd ~/kiln-controller\nsource venv/bin/activate\npython3 kiln-controller.py\n```\n\n#### 5.1.5 systemd Service Setup\n\n```bash\n# Create systemd service file\nsudo tee /etc/systemd/system/kiln-controller.service > /dev/null <<EOF\n[Unit]\nDescription=Kiln Controller Service\nAfter=network.target\n\n[Service]\nType=simple\nUser=pi\nWorkingDirectory=/home/pi/kiln-controller\nEnvironment=PATH=/home/pi/kiln-controller/venv/bin\nExecStart=/home/pi/kiln-controller/venv/bin/python3 kiln-controller.py\nRestart=always\nRestartSec=10\nStandardOutput=journal\nStandardError=journal\n\n[Install]\nWantedBy=multi-user.target\nEOF\n\n# Enable and start service\nsudo systemctl daemon-reload\nsudo systemctl enable kiln-controller.service\nsudo systemctl start kiln-controller.service\n\n# Check status\nsudo systemctl status kiln-controller.service\n\n# View logs\nsudo journalctl -u kiln-controller.service -f\n```\n\n#### 5.1.6 Network Configuration\n\n**Static IP (Optional but recommended):**\n\n```bash\n# Edit dhcpcd configuration\nsudo nano /etc/dhcpcd.conf\n\n# Add at the end:\ninterface eth0\nstatic ip_address=192.168.178.120/24\nstatic routers=192.168.178.1\nstatic domain_name_servers=192.168.178.1\n\n# Reboot\nsudo reboot\n```\n\n**Firewall Configuration:**\n\n```bash\n# Install ufw if not present\nsudo apt install -y ufw\n\n# Allow SSH\nsudo ufw allow ssh\n\n# Allow kiln controller ports\nsudo ufw allow 8080/tcp\n\n# Enable firewall\nsudo ufw enable\n\n# Check status\nsudo ufw status\n```\n\n### 5.2 iOS App Deployment\n\n#### 5.2.1 Development Setup\n\n1. **Prerequisites:**\n   - Mac with Xcode 15+\n   - iOS 16+ device or simulator\n   - Apple Developer account (for TestFlight/App Store)\n\n2. **Project Setup:**\n   ```bash\n   # Create new Xcode project\n   # File → New → Project → iOS → App\n   # Name: KilnControllerV2\n   # Interface: SwiftUI\n   # Language: Swift\n   # Storage: None\n   ```\n\n3. **Add Dependencies:**\n   ```bash\n   # Using Swift Package Manager\n   # File → Add Package Dependencies\n   # Add: Combine (built-in), no external packages needed\n   ```\n\n4. **Configure Project:**\n   - Set deployment target to iOS 16.0\n   - Enable Local Network capability (for LAN communication)\n   - Add Info.plist keys:\n     ```xml\n     <key>NSLocalNetworkUsageDescription</key>\n     <string>Required to communicate with the kiln controller on your local network</string>\n     <key>NSBonjourServices</key>\n     <array>\n         <string>_http._tcp</string>\n         <string>_ws._tcp</string>\n     </array>\n     ```\n\n#### 5.2.2 Building for Testing\n\n```bash\n# Build for simulator\nxcodebuild -scheme KilnControllerV2 -destination 'platform=iOS Simulator,name=iPhone 15' clean build\n\n# Build for device\nxcodebuild -scheme KilnControllerV2 -destination 'platform=iOS,name=Your iPhone' clean build\n```\n\n#### 5.2.3 TestFlight Distribution\n\n1. **Archive Build:**\n   ```bash\n   # Archive\n   xcodebuild archive -scheme KilnControllerV2 -archivePath ~/Desktop/KilnControllerV2.xcarchive\n\n   # Export for App Store\n   xcodebuild -exportArchive -archivePath ~/Desktop/KilnControllerV2.xcarchive -exportPath ~/Desktop/KilnControllerV2-IPA -exportOptionsPlist ExportOptions.plist\n   ```\n\n2. **Upload to App Store Connect:**\n   ```bash\n   xcrun altool --upload-app --type ios --file ~/Desktop/KilnControllerV2-IPA/KilnControllerV2.ipa --apiKey YOUR_API_KEY --apiIssuer YOUR_ISSUER_ID\n   ```\n\n3. **Configure TestFlight:**\n   - Add internal testers\n   - Create beta group\n   - Distribute build\n\n#### 5.2.4 Ad-Hoc Distribution (for personal use)\n\n```bash\n# Create ExportOptions.plist for ad-hoc\ncat > ExportOptions.plist <<EOF\n<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n    <key>method</key>\n    <string>ad-hoc</string>\n    <key>teamID</key>\n    <string>YOUR_TEAM_ID</string>\n    <key>compileBitcode</key>\n    <false/>\n    <key>uploadSymbols</key>\n    <true/>\n</dict>\n</plist>\nEOF\n\n# Export ad-hoc IPA\nxcodebuild -exportArchive -archivePath ~/Desktop/KilnControllerV2.xcarchive -exportPath ~/Desktop/KilnControllerV2-AdHoc -exportOptionsPlist ExportOptions.plist\n```\n\n#### 5.2.5 App Store Submission\n\n1. **Prepare for Submission:**\n   - Create App Store Connect record\n   - Add screenshots (required sizes)\n   - Write app description\n   - Set age rating\n   - Add privacy policy URL\n\n2. **Submit:**\n   ```bash\n   # Use Xcode Organizer or Transporter app\n   # Or command line:\n   xcrun altool --upload-app --type ios --file ~/Desktop/KilnControllerV2-IPA/KilnControllerV2.ipa --apiKey YOUR_API_KEY --apiIssuer YOUR_ISSUER_ID\n   ```\n\n---\n\n## 6. Testing Strategy\n\n### 6.1 Python Backend Testing\n\n#### 6.1.1 Unit Tests\n\n```python\n# tests/test_oven.py\nimport unittest\nimport time\nfrom unittest.mock import Mock, patch\nfrom lib.oven import Oven, PID\nfrom config import PID_KP, PID_KI, PID_KD\n\nclass TestPID(unittest.TestCase):\n    def setUp(self):\n        self.pid = PID(PID_KP, PID_KI, PID_KD)\n\n    def test_pid_compute(self):\n        # Test PID computation\n        output = self.pid.compute(setpoint=100, input=90)\n        self.assertIsNotNone(output)\n        self.assertIn('out', output)\n        self.assertIn('pid', output)\n\n    def test_pid_reset(self):\n        self.pid.compute(100, 90)\n        self.pid.reset()\n        # Verify reset state\n        self.assertEqual(self.pid.iterm, 0)\n\nclass TestOven(unittest.TestCase):\n    def setUp(self):\n        self.mock_config = Mock()\n        self.oven = Oven(self.mock_config)\n\n    def test_get_state(self):\n        state = self.oven.get_state()\n        self.assertIn('state', state)\n        self.assertIn('temperature', state)\n        self.assertIn('target', state)\n\n    @patch('lib.oven.time.sleep')\n    def test_control_loop(self, mock_sleep):\n        # Test control loop iteration\n        self.oven.state = \"RUNNING\"\n        self.oven._control_loop()\n        # Verify state changes\n        self.assertIsNotNone(self.oven.get_state())\n\nclass TestProfile(unittest.TestCase):\n    def test_profile_interpolation(self):\n        from lib.oven import Profile\n        profile = Profile(\"Test\", [[0, 25], [3600, 300]])\n\n        # Test interpolation\n        temp = profile.get_target_temperature(1800)  # Midpoint\n        self.assertAlmostEqual(temp, 162.5, places=1)\n\n    def test_profile_duration(self):\n        from lib.oven import Profile\n        profile = Profile(\"Test\", [[0, 25], [7200, 600]])\n        self.assertEqual(profile.duration(), 7200)\n\nif __name__ == '__main__':\n    unittest.main()\n```\n\n#### 6.1.2 Integration Tests\n\n```python\n# tests/test_integration.py\nimport unittest\nimport json\nimport requests\nimport time\nfrom threading import Thread\nfrom kiln_controller import start_server\n\nclass TestAPI(unittest.TestCase):\n    @classmethod\n    def setUpClass(cls):\n        # Start test server\n        cls.server_thread = Thread(target=start_server)\n        cls.server_thread.daemon = True\n        cls.server_thread.start()\n        time.sleep(2)  # Wait for server to start\n\n        cls.base_url = \"http://localhost:8080\"\n\n    def test_health_check(self):\n        response = requests.get(f\"{self.base_url}/api/stats\")\n        self.assertEqual(response.status_code, 200)\n\n    def test_run_command(self):\n        # Create test profile\n        profile = {\n            \"type\": \"profile\",\n            \"name\": \"TestProfile\",\n            \"temp_units\": \"c\",\n            \"data\": [[0, 25], [3600, 300]]\n        }\n\n        # Save profile via storage WebSocket\n        # (WebSocket testing requires async, simplified here)\n\n        # Run profile\n        response = requests.post(\n            f\"{self.base_url}/api\",\n            json={\"cmd\": \"run\", \"profile\": \"TestProfile\"}\n        )\n        data = response.json()\n        self.assertTrue(data.get('success', False))\n\n        # Stop\n        response = requests.post(\n            f\"{self.base_url}/api\",\n            json={\"cmd\": \"stop\"}\n        )\n        data = response.json()\n        self.assertTrue(data.get('success', False))\n\nif __name__ == '__main__':\n    unittest.main()\n```\n\n#### 6.1.3 Hardware-in-Loop Testing\n\n```python\n# tests/test_hardware.py\nimport unittest\nimport time\nfrom unittest.mock import patch, MagicMock\nfrom lib.tempSensor import TempSensor, MAX31855\nfrom lib.hardware import HardwareController\nimport RPi.GPIO as GPIO\n\nclass TestTempSensor(unittest.TestCase):\n    @patch('lib.tempSensor.spidev.SpiDev')\n    def test_max31855_read(self, mock_spi):\n        # Mock SPI response\n        mock_spi_instance = MagicMock()\n        mock_spi.return_value = mock_spi_instance\n        mock_spi_instance.readbytes.return_value = [0x00, 0x00, 0x00, 0x0C]  # 25°C\n\n        sensor = MAX31855()\n        temp = sensor.read_temp_c()\n        self.assertAlmostEqual(temp, 25.0, places=1)\n\nclass TestHardwareController(unittest.TestCase):\n    @patch('lib.hardware.GPIO')\n    def test_ssr_control(self, mock_gpio):\n        controller = HardwareController()\n\n        controller.enable_safety_relay()\n        mock_gpio.output.assert_called_with(23, mock_gpio.HIGH)\n\n        controller.enable_ssr()\n        mock_gpio.output.assert_called_with(18, mock_gpio.HIGH)\n\n        controller.disable_ssr()\n        mock_gpio.output.assert_called_with(18, mock_gpio.LOW)\n\n        controller.disable_safety_relay()\n        mock_gpio.output.assert_called_with(23, mock_gpio.LOW)\n\nif __name__ == '__main__':\n    unittest.main()\n```\n\n### 6.2 iOS App Testing\n\n#### 6.2.1 Unit Tests\n\n```swift\n// KilnControllerV2Tests/ProfileTests.swift\nimport XCTest\n@testable import KilnControllerV2\n\nclass ProfileTests: XCTestCase {\n    func testProfileInterpolation() {\n        let profile = Profile(\n            name: \"Test\",\n            tempUnits: \"c\",\n            data: [[0, 25], [3600, 300]]\n        )\n\n        // Test midpoint\n        let temp = profile.getTargetTemperature(at: 1800)\n        XCTAssertEqual(temp, 162.5, accuracy: 0.1)\n\n        // Test beyond last point\n        let endTemp = profile.getTargetTemperature(at: 4000)\n        XCTAssertEqual(endTemp, 0)\n    }\n\n    func testProfileDuration() {\n        let profile = Profile(\n            name: \"Test\",\n            tempUnits: \"c\",\n            data: [[0, 25], [7200, 600]]\n        )\n\n        XCTAssertEqual(profile.duration, 7200)\n    }\n\n    func testProfileCoding() {\n        let profile = Profile(\n            name: \"Test Profile\",\n            tempUnits: \"c\",\n            data: [[0, 25], [1800, 150]]\n        )\n\n        let encoder = JSONEncoder()\n        let data = try! encoder.encode(profile)\n\n        let decoder = JSONDecoder()\n        let decoded = try! decoder.decode(Profile.self, from: data)\n\n        XCTAssertEqual(profile.name, decoded.name)\n        XCTAssertEqual(profile.tempUnits, decoded.tempUnits)\n        XCTAssertEqual(profile.data, decoded.data)\n    }\n}\n```\n\n#### 6.2.2 ViewModel Tests\n\n```swift\n// KilnControllerV2Tests/DashboardViewModelTests.swift\nimport XCTest\nimport Combine\n@testable import KilnControllerV2\n\nclass DashboardViewModelTests: XCTestCase {\n    var viewModel: DashboardViewModel!\n    var mockWebSocketService: MockWebSocketService!\n    var mockControllerAPI: MockControllerAPI!\n    var cancellables: Set<AnyCancellable>!\n\n    override func setUp() {\n        super.setUp()\n        mockWebSocketService = MockWebSocketService()\n        mockControllerAPI = MockControllerAPI()\n        viewModel = DashboardViewModel(\n            webSocketService: mockWebSocketService,\n            controllerAPI: mockControllerAPI\n        )\n        cancellables = Set<AnyCancellable>()\n    }\n\n    func testInitialState() {\n        XCTAssertFalse(viewModel.isConnected)\n        XCTAssertEqual(viewModel.currentState.state, .idle)\n    }\n\n    func testPauseWhenRunning() {\n        viewModel.currentState = KilnState(\n            cost: 0,\n            runtime: 100,\n            temperature: 200,\n            target: 210,\n            state: .running,\n            heat: 1.0,\n            heatRate: 150,\n            totalTime: 3600,\n            kwhRate: 0.25,\n            currencyType: \"€\",\n            profile: \"Test\",\n            pidstats: nil,\n            catchingUp: false\n        )\n\n        mockControllerAPI.pauseResult = Just(true)\n            .setFailureType(to: Error.self)\n            .eraseToAnyPublisher()\n\n        viewModel.pause()\n\n        XCTAssertTrue(mockControllerAPI.pauseCalled)\n    }\n\n    func testPauseWhenIdle() {\n        viewModel.currentState = .placeholder\n\n        viewModel.pause()\n\n        XCTAssertFalse(mockControllerAPI.pauseCalled)\n    }\n}\n\n// Mock classes\nclass MockWebSocketService: WebSocketService {\n    var pauseCalled = false\n    var resumeCalled = false\n    var stopCalled = false\n}\n\nclass MockControllerAPI: ControllerAPI {\n    var pauseCalled = false\n    var resumeCalled = false\n    var stopCalled = false\n\n    var pauseResult: AnyPublisher<Bool, Error> = Just(false).setFailureType(to: Error.self).eraseToAnyPublisher()\n    var resumeResult: AnyPublisher<Bool, Error> = Just(false).setFailureType(to: Error.self).eraseToAnyPublisher()\n    var stopResult: AnyPublisher<Bool, Error> = Just(false).setFailureType(to: Error.self).eraseToAnyPublisher()\n\n    override func pause() -> AnyPublisher<Bool, Error> {\n        pauseCalled = true\n        return pauseResult\n    }\n\n    override func resume() -> AnyPublisher<Bool, Error> {\n        resumeCalled = true\n        return resumeResult\n    }\n\n    override func stop() -> AnyPublisher<Bool, Error> {\n        stopCalled = true\n        return stopResult\n    }\n}\n```\n\n#### 6.2.3 UI Tests\n\n```swift\n// KilnControllerV2UITests/DashboardViewUITests.swift\nimport XCTest\n@testable import KilnControllerV2\n\nclass DashboardViewUITests: XCTestCase {\n    var app: XCUIApplication!\n\n    override func setUp() {\n        super.setUp()\n        continueAfterFailure = false\n        app = XCUIApplication()\n        app.launch()\n    }\n\n    func testDashboardDisplays() {\n        // Verify dashboard is displayed\n        XCTAssertTrue(app.navigationBars[\"Kiln Controller\"].exists)\n\n        // Verify connection indicator\n        XCTAssertTrue(app.staticTexts[\"Connected\"].exists)\n    }\n\n    func testTemperatureDisplay() {\n        // Wait for temperature data\n        let temperatureLabel = app.staticTexts.containing(NSPredicate(format: \"label CONTAINS '°'\")).firstMatch\n        XCTAssertTrue(temperatureLabel.waitForExistence(timeout: 5))\n    }\n\n    func testQuickActions() {\n        // Test pause button (when running)\n        let pauseButton = app.buttons[\"Pause\"]\n        if pauseButton.exists {\n            pauseButton.tap()\n            XCTAssertTrue(app.buttons[\"Resume\"].exists)\n        }\n\n        // Test stop button\n        let stopButton = app.buttons[\"Stop\"]\n        if stopButton.exists {\n            stopButton.tap()\n            // Verify confirmation dialog\n        }\n    }\n\n    func testProgramsNavigation() {\n        // Tap programs tab\n        app.tabBars.buttons[\"Programs\"].tap()\n\n        // Verify programs list\n        XCTAssertTrue(app.tables.firstMatch.exists)\n\n        // Test creating new profile\n        app.navigationBars.buttons[\"plus\"].tap()\n        XCTAssertTrue(app.textFields[\"Name\"].exists)\n    }\n\n    func testSettingsNavigation() {\n        // Navigate to settings\n        app.navigationBars.buttons[\"gearshape\"].tap()\n\n        // Verify settings screen\n        XCTAssertTrue(app.navigationBars[\"Settings\"].exists)\n\n        // Test connection test\n        app.buttons[\"Test Connection\"].tap()\n        // Wait for test result\n    }\n}\n```\n\n### 6.3 End-to-End Testing\n\n#### 6.3.1 Complete Firing Cycle Test\n\n```python\n# tests/test_e2e.py\nimport unittest\nimport json\nimport time\nimport websocket\nimport requests\n\nclass TestEndToEnd(unittest.TestCase):\n    def setUp(self):\n        self.base_url = \"http://192.168.178.120:8080\"\n        self.ws_url = \"ws://192.168.178.120:8080\"\n\n        # Create test profile\n        self.test_profile = {\n            \"type\": \"profile\",\n            \"name\": \"E2E_Test_Profile\",\n            \"temp_units\": \"c\",\n            \"data\": [[0, 25], [600, 100], [1200, 150], [1800, 100]]\n        }\n\n    def test_complete_firing_cycle(self):\n        # 1. Connect to /status WebSocket\n        ws = websocket.create_connection(f\"{self.ws_url}/status\")\n        backlog = json.loads(ws.recv())\n        self.assertEqual(backlog['type'], 'backlog')\n\n        # 2. Save test profile via /storage\n        storage_ws = websocket.create_connection(f\"{self.ws_url}/storage\")\n        storage_ws.send(json.dumps({\n            \"cmd\": \"PUT\",\n            \"profile\": self.test_profile,\n            \"force\": True\n        }))\n        response = json.loads(storage_ws.recv())\n        self.assertEqual(response['resp'], 'OK')\n\n        # 3. Start firing\n        response = requests.post(\n            f\"{self.base_url}/api\",\n            json={\"cmd\": \"run\", \"profile\": \"E2E_Test_Profile\"}\n        )\n        self.assertTrue(response.json()['success'])\n\n        # 4. Monitor state changes\n        state_seen = {'IDLE', 'RUNNING'}\n        timeout = time.time() + 30\n\n        while time.time() < timeout:\n            state_msg = json.loads(ws.recv())\n            state = state_msg.get('state')\n\n            if state == 'RUNNING':\n                self.assertIn('profile', state_msg)\n                self.assertEqual(state_msg['profile'], 'E2E_Test_Profile')\n                break\n\n        # 5. Pause\n        response = requests.post(\n            f\"{self.base_url}/api\",\n            json={\"cmd\": \"pause\"}\n        )\n        self.assertTrue(response.json()['success'])\n\n        # Verify paused state\n        state_msg = json.loads(ws.recv())\n        self.assertEqual(state_msg['state'], 'PAUSED')\n\n        # 6. Resume\n        response = requests.post(\n            f\"{self.base_url}/api\",\n            json={\"cmd\": \"resume\"}\n        )\n        self.assertTrue(response.json()['success'])\n\n        # Verify running state\n        state_msg = json.loads(ws.recv())\n        self.assertEqual(state_msg['state'], 'RUNNING')\n\n        # 7. Stop\n        response = requests.post(\n            f\"{self.base_url}/api\",\n            json={\"cmd\": \"stop\"}\n        )\n        self.assertTrue(response.json()['success'])\n\n        # Verify idle state\n        state_msg = json.loads(ws.recv())\n        self.assertEqual(state_msg['state'], 'IDLE')\n\n        # Cleanup\n        storage_ws.send(json.dumps({\n            \"cmd\": \"DELETE\",\n            \"profile\": {\"name\": \"E2E_Test_Profile\"}\n        }))\n\n        ws.close()\n        storage_ws.close()\n\nif __name__ == '__main__':\n    unittest.main()\n```\n\n---\n\n## 7. Timeline & Milestones\n\n### 7.1 Development Phases\n\n**Phase 1: Foundation (Weeks 1-2)**\n- Set up development environment\n- Implement basic Python backend structure\n- Create iOS project with basic UI scaffolding\n- Implement core data models\n- Milestone: Running backend with basic API, iOS app with empty screens\n\n**Phase 2: Backend Core (Weeks 3-4)**\n- Implement Oven class with PID controller\n- Implement TempSensor thread\n- Implement OvenWatcher for state broadcasting\n- Implement profile storage\n- Implement REST API endpoints\n- Implement WebSocket handlers\n- Milestone: Functional backend with all communication channels\n\n**Phase 3: Frontend Networking (Weeks 5-6)**\n- Implement WebSocketService with 4 connections\n- Implement ControllerAPI for REST calls\n- Implement KeychainService\n- Implement connection testing\n- Implement error handling\n- Milestone: iOS app can connect and communicate with backend\n\n**Phase 4: Frontend UI (Weeks 7-8)**\n- Implement DashboardView and components\n- Implement ProgramsListView and editor\n- Implement GraphView with temperature chart\n- Implement SettingsView\n- Implement State management\n- Milestone: Complete iOS UI with all features\n\n**Phase 5: Hardware Integration (Weeks 9-10)**\n- Wire up Raspberry Pi hardware\n- Implement MAX31855/56 driver\n- Implement GPIO control for SSR and safety relay\n- Implement lid switch monitoring\n- Implement emergency shutdown\n- Milestone: Hardware fully integrated and functional\n\n**Phase 6: Testing & Refinement (Weeks 11-12)**\n- Write unit tests for backend\n- Write unit tests for iOS\n- Write integration tests\n- Perform end-to-end testing\n- Fix bugs and refine UX\n- Milestone: Tested, stable system\n\n**Phase 7: Deployment (Weeks 13-14)**\n- Set up Raspberry Pi as production device\n- Configure systemd service\n- Test iOS TestFlight distribution\n- Prepare App Store submission\n- Create documentation\n- Milestone: Deployed system ready for use\n\n### 7.2 Key Milestones\n\n| Milestone | Date | Deliverables |\n|-----------|------|--------------|\n| M1: Foundation | Week 2 | Basic backend + iOS scaffold |\n| M2: Backend Core | Week 4 | Full backend implementation |\n| M3: Frontend Networking | Week 6 | iOS-backend communication |\n| M4: Frontend UI | Week 8 | Complete iOS app UI |\n| M5: Hardware Integration | Week 10 | Hardware fully functional |\n| M6: Testing | Week 12 | Fully tested system |\n| M7: Deployment | Week 14 | Production-ready system |\n\n### 7.3 Risk Mitigation Timeline\n\n| Risk | Mitigation | Timeline |\n|------|------------|----------|\n| Hardware compatibility | Test with actual hardware early | Week 9-10 |\n| WebSocket reliability | Implement robust reconnect logic | Week 5-6 |\n| iOS app store approval | Prepare documentation early | Week 13-14 |\n| Temperature accuracy | Calibrate sensors thoroughly | Week 9-10 |\n| Network issues | Implement offline handling | Week 11-12 |\n\n---\n\n## 8. Risk Assessment\n\n### 8.1 Technical Risks\n\n#### 8.1.1 Hardware Risks\n\n| Risk | Likelihood | Impact | Mitigation |\n|------|------------|--------|------------|\n| Thermocouple failure | Medium | High | Implement error detection, redundancy, alerts |\n| SSR failure | Low | Critical | Use quality components, implement safety relay |\n| GPIO pin damage | Low | Medium | Use opto-isolation, current limiting |\n| Power supply issues | Medium | High | Use UPS, voltage monitoring |\n| Raspberry Pi overheating | Low | Medium | Adequate cooling, temperature monitoring |\n\n#### 8.1.2 Software Risks\n\n| Risk | Likelihood | Impact | Mitigation |\n|------|------------|--------|------------|\n| WebSocket connection drops | High | Medium | Auto-reconnect, state sync on reconnect |\n| PID tuning issues | Medium | High | Implement auto-tune, manual override |\n| Profile data corruption | Low | High | Validation, backup, versioning |\n| Memory leaks | Low | Medium | Regular testing, monitoring |\n| Concurrency bugs | Medium | Medium | Proper threading, locks, testing |\n\n#### 8.1.3 Network Risks\n\n| Risk | Likelihood | Impact | Mitigation |\n|------|------------|--------|------------|\n| Network partition | Medium | Medium | Offline mode, state persistence |\n| IP address changes | High | Low | Static IP, mDNS, user configuration |\n| Port conflicts | Low | Medium | Configurable ports, error handling |\n| Latency issues | Low | Low | Buffering, timeout handling |\n\n### 8.2 Operational Risks\n\n| Risk | Likelihood | Impact | Mitigation |\n|------|------------|--------|------------|\n| Overheating kiln | Low | Critical | Temperature limits, safety shutoff |\n| Lid left open | Medium | High | Lid switch, auto-shutoff |\n| Power loss | Medium | Medium | Automatic restart, state persistence |\n| User error | High | Medium | Clear UI, confirmations, limits |\n| Component wear | Medium | High | Maintenance alerts, lifecycle tracking |\n\n### 8.3 Security Risks\n\n| Risk | Likelihood | Impact | Mitigation |\n|------|------------|--------|------------|\n| Unauthorized access | Medium | High | Implement authentication (future) |\n| Network snooping | Low | Medium | Use TLS (future) |\n| Code injection | Low | Critical | Input validation, sanitization |\n| Physical access | Low | Medium | Physical security, locked enclosure |\n\n### 8.4 Project Risks\n\n| Risk | Likelihood | Impact | Mitigation |\n|------|------------|--------|------------|\n| Timeline delays | Medium | Medium | Buffer time, phased delivery |\n| Scope creep | High | Medium | Clear requirements, change control |\n| Resource constraints | Low | High | Prioritize features, MVP approach |\n| User adoption | Medium | High | User testing, feedback, documentation |\n\n---\n\n## 9. Future Enhancements\n\n### 9.1 Backend Improvements\n\n1. **Authentication:**\n   - Add token-based authentication\n   - Implement user management\n   - Support multiple users with permissions\n\n2. **Enhanced Safety:**\n   - Multiple thermocouple support\n   - Redundant temperature sensors\n   - More sophisticated emergency detection\n\n3. **Data Persistence:**\n   - SQLite database for firing history\n   - Firing logs and analytics\n   - Trend analysis and reporting\n\n4. **Advanced Features:**\n   - PID auto-tuning\n   - Multiple firing schedules\n   - Delayed start\n   - Notifications (email, SMS, push)\n\n5. **API Improvements:**\n   - RESTful API redesign\n   - WebSocket multiplexing\n   - GraphQL support\n\n### 9.2 iOS App Improvements\n\n1. **Enhanced UI:**\n   - Dark mode support\n   - Custom themes\n   - Widget support\n   - Apple Watch companion app\n\n2. **Advanced Features:**\n   - Offline mode with sync\n   - Firing history and analytics\n   - Push notifications\n   - Siri shortcuts\n\n3. **Social Features:**\n   - Share profiles\n   - Community profile library\n   - Firing results sharing\n\n4. **Integration:**\n   - HomeKit integration\n   - IFTTT support\n   - Cloud backup\n\n### 9.3 Hardware Upgrades\n\n1. **Enhanced Sensors:**\n   - Multiple thermocouples\n   - Ambient temperature monitoring\n   - Humidity sensing\n   - Power consumption monitoring\n\n2. **Improved Control:**\n   - Multi-zone control\n   - Advanced SSR with feedback\n   - Ventilation control\n   - Dampers and airflow control\n\n3. **Safety Systems:**\n   - Fire detection\n   - Gas monitoring\n   - Automatic suppression\n   - Remote emergency stop\n\n---\n\n## 10. Conclusion\n\nThis implementation plan provides a comprehensive roadmap for building a complete kiln control system with:\n\n- **Robust Python backend** running on Raspberry Pi 3 B with hardware control\n- **Modern iOS SwiftUI frontend** with real-time monitoring and control\n- **Reliable communication** via REST API and WebSockets\n- **Comprehensive safety features** including emergency shutoff and lid switch\n- **Thorough testing strategy** covering unit, integration, and end-to-end testing\n- **Clear deployment process** for both backend and iOS app\n\nThe system is designed to be:\n- **Safe**: Multiple safety layers, emergency shutdown, temperature monitoring\n- **Reliable**: Robust error handling, automatic restart, state persistence\n- **User-friendly**: Intuitive iOS app with clear feedback and controls\n- **Extensible**: Modular architecture allowing future enhancements\n- **Maintainable**: Clean code, comprehensive tests, detailed documentation\n\nWith this plan, the development team can proceed with confidence, knowing they have a clear path from initial implementation to production deployment.\n\n---\n\n## Appendix A: File Structure\n\n### Python Backend\n\n```\nkiln-controller/\n├── kiln-controller.py          # Main entry point\n├── config.py                   # Configuration\n├── requirements.txt            # Python dependencies\n├── lib/\n│   ├── __init__.py\n│   ├── oven.py                 # Oven core & PID\n│   ├── ovenWatcher.py          # State broadcaster\n│   ├── tempSensor.py           # Temperature reading\n│   └── hardware.py             # GPIO & hardware control\n├── storage/\n│   ├── profiles/               # Firing profiles (*.json)\n│   └── state.json              # Restart state\n├── public/                     # Web UI assets (optional)\n├── tests/\n│   ├── test_oven.py\n│   ├── test_integration.py\n│   └── test_hardware.py\n└── scripts/\n    ├── install.sh              # Installation script\n    └── update.sh               # Update script\n```\n\n### iOS App\n\n```\nKilnControllerV2/\n├── KilnControllerApp.swift\n├── AppDelegate.swift\n├── SceneDelegate.swift\n├── Models/\n│   ├── Profile.swift\n│   ├── KilnState.swift\n│   ├── PIDStats.swift\n│   ├── ControllerConfig.swift\n│   └── BacklogMessage.swift\n├── ViewModels/\n│   ├── DashboardViewModel.swift\n│   ├── ProgramsViewModel.swift\n│   ├── ProgramEditorViewModel.swift\n│   ├── GraphViewModel.swift\n│   └── SettingsViewModel.swift\n├── Views/\n│   ├── Dashboard/\n│   │   ├── DashboardView.swift\n│   │   ├── StatusCardView.swift\n│   │   ├── TemperatureGaugeView.swift\n│   │   └── QuickActionsView.swift\n│   ├── Programs/\n│   │   ├── ProgramsListView.swift\n│   │   ├── ProgramEditorView.swift\n│   │   └── ProgramCardView.swift\n│   ├── Graph/\n│   │   └── GraphView.swift\n│   ├── Settings/\n│   │   ├── SettingsView.swift\n│   │   └── ConnectionSetupView.swift\n│   └── Components/\n│       ├── TempDisplay.swift\n│       ├── ConnectionIndicator.swift\n│       └── LoadingOverlay.swift\n├── Services/\n│   ├── WebSocketService.swift\n│   ├── ControllerAPI.swift\n│   └── KeychainService.swift\n├── Utilities/\n│   ├── TemperatureFormatter.swift\n│   ├── Extensions.swift\n│   └── HapticsManager.swift\n├── Resources/\n│   └── Assets.xcassets\n└── Tests/\n    ├── KilnControllerV2Tests/\n    └── KilnControllerV2UITests/\n```\n\n---\n\n## Appendix B: Quick Start Guide\n\n### Raspberry Pi Setup\n\n```bash\n# 1. Update system\nsudo apt update && sudo apt upgrade -y\n\n# 2. Install dependencies\nsudo apt install -y python3 python3-pip python3-venv git\nsudo apt install -y python3-dev libgpiod-dev\n\n# 3. Enable SPI\nsudo raspi-config nonint do_spi 0\n\n# 4. Create project\ncd ~\nmkdir kiln-controller && cd kiln-controller\npython3 -m venv venv\nsource venv/bin/activate\n\n# 5. Install packages\npip install bottle gevent gevent-websocket RPi.GPIO spidev\n\n# 6. Create directories\nmkdir -p lib storage/profiles public\n\n# 7. Copy source files\n# (Copy all files from this plan)\n\n# 8. Test run\npython3 kiln-controller.py\n\n# 9. Install as service\nsudo cp scripts/kiln-controller.service /etc/systemd/system/\nsudo systemctl daemon-reload\nsudo systemctl enable kiln-controller\nsudo systemctl start kiln-controller\n```\n\n### iOS App Development\n\n```bash\n# 1. Create Xcode project\n# File → New → Project → iOS → App\n# Name: KilnControllerV2\n# Interface: SwiftUI\n# Language: Swift\n\n# 2. Add files\n# Copy all files from this plan into the project\n\n# 3. Configure capabilities\n# - Add Local Network capability\n# - Set deployment target to iOS 16.0\n\n# 4. Build and run\n# Product → Run (⌘R)\n```\n\n---\n\n## Appendix C: Troubleshooting\n\n### Common Issues\n\n**Backend won't start:**\n```bash\n# Check logs\nsudo journalctl -u kiln-controller -f\n\n# Check port availability\nsudo netstat -tlnp | grep 8080\n\n# Test manually\ncd ~/kiln-controller\nsource venv/bin/activate\npython3 kiln-controller.py\n```\n\n**Temperature reading errors:**\n```bash\n# Check SPI connection\nls /dev/spidev*\n\n# Test MAX31855/56\npython3 -c \"\nimport spidev\nspi = spidev.SpiDev()\nspi.open(0, 0)\nprint(spi.readbytes(4))\n\"\n```\n\n**iOS app can't connect:**\n- Verify Raspberry Pi is on network\n- Check IP address is correct\n- Ensure no firewall blocking port 8080\n- Test with browser: http://192.168.178.120:8080\n\n**WebSocket disconnects:**\n- Check network stability\n- Verify gevent-websocket is installed\n- Check server logs for errors\n\n**SSR not switching:**\n- Verify GPIO wiring\n- Check GPIO permissions\n- Test with: `gpio -g read 18`\n\n---\n\n## Appendix D: Configuration Examples\n\n### Example Profiles\n\n**Bisque Fire:**\n```json\n{\n  \"type\": \"profile\",\n  \"name\": \"Bisque\",\n  \"temp_units\": \"c\",\n  \"data\": [\n    [0, 25],\n    [3600, 300],\n    [7200, 600],\n    [10800, 900],\n    [14400, 1000],\n    [18000, 1050],\n    [21600, 1080]\n  ]\n}\n```\n\n**Glaze Fire:**\n```json\n{\n  \"type\": \"profile\",\n  \"name\": \"Glaze\",\n  \"temp_units\": \"c\",\n  \"data\": [\n    [0, 25],\n    [3600, 500],\n    [7200, 900],\n    [10800, 1200],\n    [12600, 1250],\n    [14400, 1250],\n    [16200, 800]\n  ]\n}\n```\n\n**Test Ramp:**\n```json\n{\n  \"type\": \"profile\",\n  \"name\": \"Test_Ramp\",\n  \"temp_units\": \"c\",\n  \"data\": [\n    [0, 25],\n    [600, 100],\n    [1200, 150],\n    [1800, 100]\n  ]\n}\n```\n\n---\n\n**END OF IMPLEMENTATION PLAN**",
  "filePath": "/Users/paul/Desktop/BinkKiln/IMPLEMENTATION_PLAN.md"
}
```

**Output:**
```
Wrote file successfully.
```

---

## Assistant (Build · GLM-4.7 · 25.2s)

_Thinking:_


Done. I have created a complete implementation plan for the kiln control system covering both the iOS Swift frontend and Python backend running on Raspberry Pi 3 B.

I've created a comprehensive implementation plan at `IMPLEMENTATION_PLAN.md` that covers:

**Python Backend:**
- Complete architecture with Bottle + gevent server
- Oven core with PID controller, TempSensor thread, OvenWatcher broadcaster
- Hardware integration (MAX31855/56, SSR, safety relay, lid switch)
- REST API endpoints and 4 WebSocket handlers
- systemd service setup for Raspberry Pi 3 B

**iOS Swift Frontend:**
- MVVM architecture with SwiftUI
- Complete data models matching the backend protocol
- WebSocketService managing 4 independent connections
- Dashboard, Programs, Graph, and Settings views
- Keychain secure storage for connection settings

**Hardware Integration:**
- Detailed wiring diagrams
- GPIO configuration
- Temperature sensor implementation
- Safety relay and SSR control

**Additional Sections:**
- Deployment & installation guides
- Comprehensive testing strategy
- 14-week development timeline with milestones
- Risk assessment and mitigation
- Future enhancements
- Troubleshooting guide
- Example firing profiles

The plan addresses all the requirements from api.md, plan.md, and spec.md, including the specific protocol quirks and backend limitations noted in the documentation.

---

## User

thank you i will read it and come back.

---

## Assistant (Build · GLM-4.7 · 5.6s)

_Thinking:_


The user is thanking me and saying they will read the implementation plan and come back. This is a simple acknowledgment, so I should respond briefly and concisely as per my instructions. I need to be direct and minimal in my response.

You're welcome! Take your time reviewing the plan.

---

