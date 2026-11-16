# Hotplate Controller — session handoff

## What this is
This project is a **copy of Hotplate** (a working hotplate controller) being turned into a
**hotplate controller for PCB soldering (reflow)**. Copy made from
`~/Desktop/Hotplate` on this Mac; that original remains untouched and still lives at
github.com/binkmoed/Hotplate.

The codebase is proven and tested: a Python controller on a Raspberry Pi (GPIO + SSR +
MAX31855/56 thermocouple, PID control, WebSocket + REST API, session logging) and a
SwiftUI iOS app (live chart, profiles, history, PID tuning UI).

## Likely adjustments for a hotplate / reflow (not yet done)
- Rename branding: "Hotplate"/"Hotplate" → hotplate naming (iOS app name, bundle id
  `com.binkhotplate.HotplateApp`, Python service name `hotplate-controller`)
- Reflow needs much faster ramp rates (roughly 1–3 °C/s up to soak, then to peak
  ~235–250 °C for lead-free paste) — default PID gains (Pi runs kp 5.6, ki 72, kd 18)
  are tuned for a slow hotplate and will need retuning; note the PID already has
  anti-windup and the codebase was previously used on hotplates, so the basics work
- Profiles: replace ceramics firing schedules with reflow phases
  (preheat → soak → reflow → cooling)
- Shorter duty cycle may be appropriate (currently min duty = temp_settle_time + 1 s ≈ 1.5 s)

## Key facts carried over
- Server: `hotplate-controller/` (Python, systemd service, Bottle-style REST + WS on the Pi)
- App: `HotplateApp/` (SwiftUI, Xcode project `HotplateApp/HotplateApp.xcodeproj`, scheme `HotplateApp`)
- Hardware: Raspberry Pi + SSR + MAX31856 (Pi currently has thermocouple type S for
  the hotplate — a hotplate likely wants type K; check the Pi's own `config.json`)
- Tests: `python3 -m unittest discover tests` in `hotplate-controller/`
- Recent app features: PID tile per firing in History, Settings Guide section,
  Submarine.aiff completion alert (3×), restart-server button, control-window/duty sliders

## Deployment (from Hotplate; adapt host/paths for the hotplate Pi)
- Pi SSH was `oven@192.168.178.35`; the hotplate Pi will have its own address
- rsync with `--exclude venv --exclude __pycache__ --exclude hotplate.log
  --exclude config.json --exclude storage` to preserve live tuning and logs
- All subprocess calls must use absolute binary paths (the systemd unit PATH only
  contains the venv)
- iOS install target was an iPhone 11, UDID `00008030-0018356E0145802E`
  (adjust for whatever device this project targets)

## Git
Local `.git` history retained, but the GitHub `origin` remote was removed so pushes
from here cannot reach the Hotplate repo. Create a new repo and
`git remote add origin <url>` when ready.
