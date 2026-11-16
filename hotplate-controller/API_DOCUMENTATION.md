# Hotplate Controller API Documentation

## Base URL
```
http://<host>:<port>
Default: http://192.168.178.120:8080
```

## Protocol
- REST API for commands and configuration
- WebSockets for real-time updates
- All responses are JSON (unless noted)

---

## REST API Endpoints

### GET /
Returns API information.

**Response:**
```
Hotplate Controller API. See api.md for documentation.
```

### GET /api/stats
Returns current PID statistics. Returns empty body when idle.

**Response (idle):**
```
(empty body, HTTP 200)
```

**Response (running):**
```json
{
  "time": 1234567890.0,
  "timeDelta": 3.0,
  "setpoint": 100.0,
  "ispoint": 98.5,
  "err": 1.5,
  "errDelta": 0.2,
  "p": 4.5,
  "i": 0.1,
  "d": 0.6,
  "kp": 3.0,
  "ki": 75.0,
  "kd": 12.0,
  "pid": 5.2,
  "out": 0.526
}
```

### POST /api
Main command endpoint for hotplate control.

**Request:**
```json
{
  "cmd": "<command>",
  ...additional parameters
}
```

**Response:**
```json
{
  "success": true/false,
  "error": "error message (if failed)"
}
```

#### Commands

##### cmd: run
Start or restart a firing profile.

**Parameters:**
- `profile` (string, required): Profile name
- `startat` (number, optional): Start time in seconds (default: 0)

**Example:**
```json
{
  "cmd": "run",
  "profile": "Bisque",
  "startat": 0
}
```

##### cmd: pause
Pause the current firing. Can only be called when state is RUNNING.

**Example:**
```json
{
  "cmd": "pause"
}
```

##### cmd: resume
Resume a paused firing. Can only be called when state is PAUSED.

**Example:**
```json
{
  "cmd": "resume"
}
```

##### cmd: stop
Stop the current firing and return to IDLE. Can be called from any state.

**Example:**
```json
{
  "cmd": "stop"
}
```

##### cmd: memo
Log a message to the server (for debugging).

**Parameters:**
- `memo` (string, required): Message to log

**Example:**
```json
{
  "cmd": "memo",
  "memo": "Test message"
}
```

##### cmd: stats
Return PID statistics (same as GET /api/stats).

**Example:**
```json
{
  "cmd": "stats"
}
```

### GET /api/config
Get full configuration.

**Response:**
```json
{
  "hardware": {
    "spi_bus": 0,
    "spi_device": 0,
    "sensor_type": "MAX31856",
    "thermocouple_type_max31856": "K",
    "thermocouple_type_max31855": "K",
    "pin_ssr": 18,
    "pin_safety_relay": 23,
    "pin_lid_switch": 24,
    "kw_elements": 7.1
  },
  "pid": {
    "kp": 3.0,
    "ki": 75.0,
    "kd": 12.0,
    "control_window": 50.0,
    "max_ssr_on_time": 6.0,
    "duty_cycle": 3.0,
    "max_ssr_on_percentage": 90.0,
    "temp_settle_time": 0.5
  },
  "safety": {
    "emergency_shutoff_temp": 1300.0,
    "emergency_shutoff_temp_scale": "c",
    "ignore_temp_too_high": false,
    "max_tc_error_rate": 0.3,
    "ignore_tc_too_many_errors": false
  },
  "display": {
    "temp_scale": "c",
    "time_scale_slope": "h",
    "time_scale_profile": "m",
    "kwh_rate": 0.25,
    "currency_type": "€"
  },
  "restart": {
    "automatic_restarts": true,
    "automatic_restart_window": 15,
    "seek_start": true
  },
  "alerting": {
    "enabled": false,
    "email_enabled": false,
    "sms_enabled": false,
    ...
  },
  "server": {
    "host": "0.0.0.0",
    "port": 8080
  }
}
```

### POST /api/config
Update configuration.

**Request:**
```json
{
  "display.kwh_rate": 0.30,
  "display.currency_type": "$",
  "pid.kp": 4.0
}
```

Use dot notation for nested keys.

**Response:**
```json
{
  "success": true,
  "restart_required": false,
  "message": "Configuration updated"
}
```

**Note:** Hardware configuration changes (hardware.*) require a restart to take effect.

---

## WebSocket Endpoints

### WebSocket /status
Real-time hotplate state updates.

**Flow:**
1. Connect to `ws://<host>:<port>/status`
2. Receive backlog message immediately
3. Receive state updates every duty cycle (default 3 seconds)

**Backlog Message (first message):**
```json
{
  "type": "backlog",
  "profile": {
    "type": "profile",
    "name": "Bisque",
    "temp_units": "c",
    "data": [[0, 25], [3600, 100], ...]
  },
  "log": [
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
      "pidstats": {...},
      "catching_up": false
    },
    ...
  ]
}
```

**State Message (subsequent messages):**
```json
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
  "pidstats": {
    "time": 1234567890.0,
    "timeDelta": 3.0,
    "setpoint": 430.0,
    "ispoint": 421.0,
    "err": 9.0,
    "out": 0.545
  },
  "catching_up": false
}
```

### WebSocket /control
Send control commands (alternative to REST /api).

**Commands:**

**RUN:**
```json
{
  "cmd": "RUN",
  "profile": {
    "type": "profile",
    "name": "Bisque",
    "temp_units": "c",
    "data": [[0, 25], [3600, 100], ...]
  }
}
```

**STOP:**
```json
{
  "cmd": "STOP"
}
```

**SIMULATE** (no-op currently):
```json
{
  "cmd": "SIMULATE",
  "profile": {...}
}
```

**Note:** No acknowledgement sent. Verify success by watching /status WebSocket.

### WebSocket /storage
Profile CRUD operations.

**List profiles:**
```
Send: "GET"
Receive: [{"type": "profile", "name": "Bisque", ...}, ...]
```

**Save profile:**
```json
Send: {
  "cmd": "PUT",
  "profile": {
    "type": "profile",
    "name": "NewProfile",
    "temp_units": "c",
    "data": [[0, 25], [600, 100]]
  },
  "force": false
}
Receive: {
  "cmd": "PUT",
  "profile": {...},
  "resp": "OK"
}
```

If profile exists and `force` is false, response will be `resp: "FAIL"`.

**Delete profile:**
```json
Send: {
  "cmd": "DELETE",
  "profile": {
    "name": "OldProfile"
  }
}
Receive: {
  "cmd": "DELETE",
  "profile": {"name": "OldProfile"},
  "resp": "OK"
}
```

### WebSocket /config
Get display configuration.

**Flow:**
1. Connect to `ws://<host>:<port>/config`
2. Send: "GET"
3. Receive configuration

**Send:**
```
"GET"
```

**Receive:**
```json
{
  "temp_scale": "c",
  "time_scale_slope": "h",
  "time_scale_profile": "m",
  "kwh_rate": 0.25,
  "currency_type": "€",
  "kw_elements": 7.1
}
```

Send "GET" anytime to refresh configuration.

---

## Data Models

### Profile
```json
{
  "type": "profile",
  "name": "Bisque",
  "temp_units": "c",
  "data": [[seconds, temperature], ...]
}
```

- `type`: Always "profile"
- `name`: Profile name (filesystem-safe)
- `temp_units`: "c" or "f"
- `data`: Array of [time_seconds, temperature] points, sorted by time

### PID Stats
```json
{
  "time": 1234567890.0,
  "timeDelta": 3.0,
  "setpoint": 100.0,
  "ispoint": 98.5,
  "err": 1.5,
  "errDelta": 0.2,
  "p": 4.5,
  "i": 0.1,
  "d": 0.6,
  "kp": 3.0,
  "ki": 75.0,
  "kd": 12.0,
  "pid": 5.2,
  "out": 0.526
}
```

- `time`: Unix timestamp of PID computation
- `timeDelta`: Seconds since previous computation
- `setpoint`: Target temperature
- `ispoint`: Measured temperature
- `err`: setpoint - ispoint
- `errDelta`: err - last_err
- `p`, `i`, `d`: PID components
- `kp`, `ki`, `kd`: PID gains
- `pid`: Raw combined output (-100 to 100)
- `out`: Normalized output (0.0 to 1.0) - multiply by 100 for percentage

### State
```json
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
  "pidstats": {...},
  "catching_up": false
}
```

- `cost`: Running energy cost
- `runtime`: Seconds since profile start
- `temperature`: Current hotplate temperature
- `target`: Current target temperature from profile
- `state`: "IDLE", "RUNNING", or "PAUSED"
- `heat`: SSR state (0.0 off, 1.0 on)
- `heat_rate`: Temperature change rate (degrees/hour)
- `totaltime`: Profile duration in seconds
- `kwh_rate`: Energy price (echoed from config)
- `currency_type`: Currency symbol
- `profile`: Current profile name or null
- `pidstats`: PID statistics object
- `catching_up`: True if hotplate is catching up to schedule

---

## Error Handling

All REST endpoints return HTTP 200 with JSON body for both success and error cases.

**Success Response:**
```json
{
  "success": true
}
```

**Error Response:**
```json
{
  "success": false,
  "error": "Error message"
}
```

**Common Errors:**
- `Invalid JSON`: Request body is not valid JSON
- `Invalid request format`: Body is valid JSON but not an object
- `Missing cmd parameter`: cmd field is missing
- `Unknown command: <cmd>`: Unrecognized command
- `Profile <name> not found`: Requested profile doesn't exist
- `Can only pause when RUNNING`: Invalid state for pause command
- `Can only resume when PAUSED`: Invalid state for resume command

---

## Safety Features

### Automatic Emergency Shutdown

The hotplate will automatically shut down if:

1. **Temperature exceeds limit:** Current temp >= emergency_shutoff_temp
2. **Lid opened:** Lid switch detects open lid during firing
3. **Thermocouple errors:** Error rate exceeds max_tc_error_rate (default 30%)

### Safety Relay

The safety relay is only enabled when:
- Firing is active (state = RUNNING)
- Lid is closed
- No emergency conditions

Opening the lid immediately disables both SSR and safety relay.

### EMI-Safe Temperature Reading

Temperature readings only occur when:
- SSR is OFF (to avoid EMI interference)
- After a configurable settle time (default 0.5 seconds)

If PID requires 100% heating:
- Maximum on time is limited (max_ssr_on_percentage, default 90%)
- Remaining time is used for EMI-safe temperature reading

---

## Configuration Keys

Configurable via POST /api/config using dot notation:

**Display:**
- `display.temp_scale`: "c" or "f"
- `display.time_scale_slope`: "s", "m", or "h"
- `display.time_scale_profile`: "s", "m", or "h"
- `display.kwh_rate`: Price per kWh (float)
- `display.currency_type`: Currency symbol (string)

**PID (hot-reload):**
- `pid.kp`: Proportional gain (float)
- `pid.ki`: Integral gain (float)
- `pid.kd`: Derivative gain (float)

**PID (requires restart):**
- `pid.control_window`: Temperature window for catch-up (float)
- `pid.max_ssr_on_time`: Maximum SSR on-time per cycle (float)
- `pid.duty_cycle`: Control loop cycle time (float)
- `pid.max_ssr_on_percentage`: Maximum on-time percentage (float)
- `pid.temp_settle_time`: Temperature settle time after SSR off (float)

**Safety (requires restart):**
- `safety.emergency_shutoff_temp`: Temperature limit (float)
- `safety.emergency_shutoff_temp_scale`: "c" or "f"
- `safety.ignore_temp_too_high`: Ignore temperature limit (bool)
- `safety.max_tc_error_rate`: Max thermocouple error rate (float)
- `safety.ignore_tc_too_many_errors`: Ignore TC errors (bool)

**Hardware (requires restart):**
- `hardware.pin_ssr`: SSR control GPIO pin (int)
- `hardware.pin_safety_relay`: Safety relay GPIO pin (int)
- `hardware.pin_lid_switch`: Lid switch GPIO pin (int)
- `hardware.kw_elements`: Heating element power in kW (float)
- `hardware.sensor_type`: "MAX31855" or "MAX31856" (string)
- `hardware.thermocouple_type_max31856`: Thermocouple type for MAX31856 - "B", "E", "J", "K", "N", "R", "S", or "T"
- `hardware.thermocouple_type_max31855`: Thermocouple type for MAX31855 - only "K" supported

**Note:** MAX31855 only supports Type K thermocouples. The `thermocouple_type_max31855` setting is provided for API consistency but will be ignored if not set to "K".

**Alerting (hot-reload):**
- `alerting.enabled`: Enable alerting (bool)
- `alerting.email_enabled`: Enable email alerts (bool)
- `alerting.sms_enabled`: Enable SMS alerts (bool)

---

## Example Usage

### Python (requests + websocket-client)

```python
import requests
import websocket
import json

base_url = "http://192.168.178.120:8080"
ws_url = "ws://192.168.178.120:8080"

# Start firing
response = requests.post(
    f"{base_url}/api",
    json={"cmd": "run", "profile": "Bisque"}
)
print(response.json())

# Monitor status
def on_message(ws, message):
    data = json.loads(message)
    if data.get('type') == 'backlog':
        print("Backlog received")
    else:
        print(f"Temp: {data['temperature']}°, Target: {data['target']}°, State: {data['state']}")

ws = websocket.create_connection(f"{ws_url}/status")
ws.on_message = on_message

while True:
    ws.recv()
```

### cURL

```bash
# Start firing
curl -X POST http://192.168.178.120:8080/api \
  -H "Content-Type: application/json" \
  -d '{"cmd":"run","profile":"Bisque"}'

# Stop firing
curl -X POST http://192.168.178.120:8080/api \
  -H "Content-Type: application/json" \
  -d '{"cmd":"stop"}'

# Get stats
curl http://192.168.178.120:8080/api/stats

# Get config
curl http://192.168.178.120:8080/api/config
```

### JavaScript (Browser)

```javascript
const ws = new WebSocket('ws://192.168.178.120:8080/status');

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);

  if (data.type === 'backlog') {
    console.log('Backlog:', data);
  } else {
    console.log(`Temp: ${data.temperature}°, State: ${data.state}`);
  }
};

// Send command via fetch
fetch('http://192.168.178.120:8080/api', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({cmd: 'run', profile: 'Bisque'})
})
  .then(r => r.json())
  .then(console.log);
```