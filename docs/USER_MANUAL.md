# BinkKiln User Manual

A practical guide to firing your kiln with the BinkKiln system: a Raspberry
Pi controller mounted on the kiln ("Oven") and the KilnApp on your iPhone.

---

## 1. System overview

| Part | Where | What it does |
|---|---|---|
| **Controller** | Raspberry Pi on the kiln | Reads the thermocouple, runs PID, switches the elements via SSR + safety relay, logs every firing |
| **KilnApp** | Your iPhone | Live dashboard, start/stop firings, edit profiles, review history, change settings |
| **Firing profile** | Stored on the Pi | A schedule of `[time, temperature]` points the kiln follows |

The app talks to the controller over your home WiFi — there is no cloud
service; the phone must be on the same network as the Pi.

### States of the oven

| State | Meaning |
|---|---|
| ⚪ **Idle** | Nothing running, elements off |
| 🔥 **Running** | Firing in progress, following the profile |
| ⏸ **Paused** | Firing held (elements off, schedule paused) |

---

## 2. Daily use: running a firing

1. **Connect** — open KilnApp; on first use enter the Pi's address
   (e.g. `http://192.168.178.35:8080`). The app remembers it. A red
   "Offline" wifi icon means the controller can't be reached.
2. **Choose a profile** — on the Dashboard, pick the profile from the
   picker (e.g. *Lead_Free*, *Bisque*).
3. **Start** — tap **Start**, confirm in the sheet. The flame 🔥 icon
   appears while firing. If the kiln is already warm, *seek-start* jumps
   the schedule to the current temperature instead of reheating from
   ambient.
4. **Watch** — the dashboard shows current temperature, target, runtime,
   running cost (kWh × your tariff) and a live chart of actual vs.
   scheduled temperature.
5. **Pause / Resume** — useful for openings or waiting; the schedule
   freezes with the kiln.
6. **Completion** — when the profile finishes you get a
   **"Firing Completed"** alert with final runtime and cost. The kiln
   cools following the profile's cooldown segment.

### Stopping early

- **Stop** (your choice) asks for confirmation, then ends the firing —
  no alert noise.
- **Safety abort** — if the controller detects a fault (see below) it
  cuts all power immediately and your phone shows a **"Firing Aborted"**
  alert **with the reason**.

### How temperature is measured (and why it matters)

The controller **NEVER reads the thermocouple while the elements are
energised**. 

Each 3-second duty cycle follows an EMI-safe sequence:

1. SSR off →
2. 2. wait 0.5 s settle time →
3. read temperature →
4. PID computes →
5. SSR on for its slice →
6. quiet sleep.

The settle time is even reserved out of the SSR's maximum on-time, so a
long heating burst can never crowd out the next read.

This matters especially at high firing temperatures: the hot air around
the elements **ionizes and becomes conductive**, and the resulting
electrical noise skews the MAX31856's SPI measurements. A temperature
sampled mid-heat could read wildly wrong — and a falsely *low* reading
would drive the PID to dump even more power into an already-at-temperature
kiln. Quiet-window sampling guarantees every temperature the PID and the
safety interlocks act on is trustworthy. (If the sensor does fail to read
— e.g. a transient fault — the controller retries, logs a `sensor_retry`
event, and aborts rather than heating blind.)

### Safety aborts — what they mean

| Reason | Meaning | What to check |
|---|---|---|
| *Full power for Xs but temperature rose only Y°* (heating stall) | Elements, SSR or thermocouple not working | Element continuity, SSR wiring, thermocouple placement |
| Over-temperature | Kiln exceeded the emergency shutoff (default 1300 °C) | Profile correctness, thermocouple reading |
| Too many sensor errors | Thermocouple readings unreliable | Connections, interference, sensor health |

**Do not just restart** after an abort — investigate the reason in the
History screen first. This is the big safety advantage over e.g. a
Bentrup TC88, which would run a broken kiln "to completion" cold.

---

## 3. Profiles

A profile is a set of time → temperature points. Example (Bisque):
0 min → 25 °C, ramp to 100 °C over an hour, … hold 1050 °C, cool back down.

### Editing on the phone

- **Profiles tab** — list, create, duplicate, delete.
- **Editor** — add/remove segments and set time & temperature; the chart
  auto-scales to the peak temperature so you always see the full curve.
  Maximum settable temperature is 1500 °C.

---

## 4. History

The **History** tab lists every firing, including aborted ones:

- **Temperature chart** for the whole firing.
- **Event list** — start, pauses, completions, aborts with reasons — each
  shown with the real clock time and a muted `+Xm` runtime offset that
  matches the chart's x-axis.
- **Outcome** (completed / aborted), peak temperature and energy cost.

Sessions are stored on the Pi as JSONL files; you can delete them from the
app. If the Pi loses power mid-firing, the session is closed out on the
next boot rather than left dangling.

---

## 5. Settings

The **Settings** tab edits the controller configuration:

- **Display** — °C/°F, kWh rate & currency (for cost display).
- **PID** — tuning parameters (leave alone unless you know why).
- **Safety** — emergency shutoff temperature, sensor error tolerance.
- **Hardware** — element power rating, pins.

Changes are pushed to the controller immediately.

---

## 6. Power, reboots and recovery

- The controller runs as a systemd service: it starts on boot and restarts
  automatically after a crash.
- If power is lost mid-firing, on reboot the controller can **resume the
  firing** if it restarts within the configured window (default 15
  minutes) and seek-start is on — otherwise the session is marked
  interrupted and the kiln stays off.
- A hardware watchdog reboots the Pi if the software ever hangs while the
  elements are on (one-time setup, see `kiln-controller/deploy/README.md`).

---

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| App shows "Offline" | Check Pi power/LED, WiFi, address in the app; try `http://<pi>:8080` in a browser |
| Firing won't start | Is a profile selected? Check the controller isn't in an error state (restart the service when idle) |
| Aborted: heating stalled | Inspect elements/SSR/thermocouple before re-firing (see §2) |
| Chart shows a line back to zero | Fixed in current builds — update both app and controller |
| Cost looks wrong | Check element kW in Hardware settings and the kWh rate in Display settings |

For developer/setup documentation see the main
[README](../README.md), [KilnApp](../KilnApp/README.md) and
[controller](../kiln-controller/README.md) docs.
