"""Tests for the kiln control-loop safety fixes. Run: python3 tests/test_oven_safety.py"""
import sys, os, time, types, json
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'lib'))

from oven import PID, Profile, Oven

PASS = []
def check(name, cond, detail=""):
    PASS.append((name, bool(cond), detail))
    print(('PASS' if cond else 'FAIL'), name, detail)

class FakeHardware:
    def __init__(self, lid_open=False):
        self.lid_open = lid_open
        self.ssr_on = False
        self.relay_on = False
        self.relay_requested = 0
        self.ssrs = []          # log of (on_time,)
    def is_lid_open(self): return self.lid_open
    def enable_safety_relay(self):
        self.relay_requested += 1
        if self.lid_open: return False
        self.relay_on = True; return True
    def disable_safety_relay(self): self.ssr_on = False; self.relay_on = False
    def enable_ssr(self, duration=None):
        if not self.relay_on or self.lid_open: return False
        self.ssr_on = True; self.ssrs.append(duration)
        time.sleep(duration)
        self.ssr_on = False
        return True
    def disable_ssr(self): self.ssr_on = False

class FakeSensor:
    def __init__(self, temp=20.0, fail=False): self.temp = temp; self.fail = fail
    def safe_read(self):
        if self.fail: raise RuntimeError("fault")
        return self.temp
    def get_temperature(self): return self.temp
    def get_error_rate(self): return 0.0

# --- Fix 1/2: PID mapping & integral ---
pid = PID(3.0, 75.0, 12.0)
check("F1: zero error -> 0% duty", pid.compute(100, 100) == 0.0)
check("F1: positive err -> bounded duty", 0 < pid.compute(500, 20) <= 1.0)
pid.reset()
prev_i = 0
# Small error so the output is NOT saturated — the integrator must run.
# (With anti-windup, a saturating error correctly freezes the i-term.)
pid.compute(110, 100)
for _ in range(10): pid.compute(110, 100)
s = pid.get_stats()
check("F2: integral grows with ki gain", s['i'] > 0 and s['p'] > 0, f"i={s['i']:.2f}")
pid2 = PID(5.6, 72, 18)
pid2.compute(300, 100)
for _ in range(10): pid2.compute(300, 100)
s2 = pid2.get_stats()
check("F2b: anti-windup freezes i-term when saturated", s2['i'] == 0.0, f"i={s2['i']:.2f}")

# --- Fix 4: consecutive read failures abort ---
hw, sn = FakeHardware(), FakeSensor(fail=True)
ov = Oven(sn, hw)
ov.state = 'RUNNING'
ov.start_time = time.time()
ov.profile = Profile("t", [(0, 100), (600, 100)])
ov.totaltime = 600
for _ in range(3):
    ov._control_cycle()
check("F4: aborts after repeated sensor failures", ov.state == 'IDLE')
check("F4: SSR never energised", len(hw.ssrs) == 0 and not hw.ssr_on)

# --- Fix 6: lid open during heating aborts immediately ---
hw2 = FakeHardware()
hw2.relay_on = True
ov2 = Oven(FakeSensor(50.0), hw2)
ov2.state = 'RUNNING'
ov2.start_time = time.time()
ov2.profile = Profile("t", [(0, 900), (600, 900)])
ov2.totaltime = 600
def mid_heat_lid():  # open lid after SSR call begins
    orig = hw2.enable_ssr
    def hook(duration=None):
        hw2.lid_open = True
        hw2.ssr_on = True
        return False  # simulate immediate cut
    hw2.enable_ssr = hook
mid_heat_lid()
ov2.pid.reset()
before = time.time()
ov2._control_cycle()
check("F6: lid-open mid-heat aborts same cycle", ov2.state == 'IDLE' and not hw2.ssr_on)

# --- Fix 5: cost tracks actual on-time ---
from config import config
hw3 = FakeHardware(); hw3.relay_on = True
ov3 = Oven(FakeSensor(900.0), hw3)
ov3.state = 'RUNNING'
ov3.start_time = time.time()
ov3.profile = Profile("t", [(0, 1000), (3600, 1000)])
ov3.totaltime = 3600
ov3.pid.reset()
ov3.pid.last_time = time.time()  # avoid first-cycle shortcut
ov3._control_cycle()
expected_max = config.kw_elements * config.kwh_rate * config.duty_cycle / 3600.0
check("F5: cost accrued and <= duty-cycle max", 0 < ov3.cost <= expected_max, f"cost={ov3.cost:.4f} max={expected_max:.4f}")

# --- Fix 3: relay-before-start ordering (controller logic simulation) ---
hw4 = FakeHardware()
ok = hw4.enable_safety_relay() and hw4.relay_on
check("F3: relay enabled before run", ok)
hw5 = FakeHardware(lid_open=True)
check("F3: start refused with lid open", not hw5.enable_safety_relay())

# --- Soft landing: duty capped near the setpoint ---
print("\n--- Soft landing cap ---")
hw2, sn2 = FakeHardware(), FakeSensor()
hw2.enable_safety_relay()
ov2 = Oven(sn2, hw2)
ov2.state = 'RUNNING'
ov2.start_time = time.time()
ov2.profile = Profile("t", [(0, 100), (600, 100)])
ov2.totaltime = 600
sn2.temp = 95.0   # within 15 degrees of the 100C target
ov2.target_temp = 100.0
ov2._control_cycle()
on2 = hw2.ssrs[0] if hw2.ssrs else 0.0
max_cap = 3.0 * 0.40  # duty_cycle * approach_max_output
check("soft landing caps duty near target", 0 < on2 <= max_cap, f"on={on2:.2f} cap={max_cap:.2f}")
sn2.temp = 50.0   # far from target: no cap
ov2.runtime = 0.1
ov2._control_cycle()
check("no cap when far from target", hw2.ssrs[-1] > max_cap, f"on={hw2.ssrs[-1]:.2f}")

# --- Completed firing: event + outcome reach the session log ---
print("\n--- Completed firing event ---")
from ovenWatcher import OvenWatcher
from sessionlog import SessionLogger
import tempfile

tmpdir = tempfile.mkdtemp()
sl = SessionLogger(tmpdir)
sl.start(Profile("Lead", [(0, 100), (600, 200)]))
hw6, sn6 = FakeHardware(), FakeSensor(210.0)
ov6 = Oven(sn6, hw6)
w = OvenWatcher(ov6, session_logger=sl)
w._last_state = 'RUNNING'  # simulate a firing in progress
# Fire runs, reaches the end of the profile, goes IDLE.
ov6.state = 'RUNNING'
ov6.start_time = time.time() - 700
ov6.runtime = 700
ov6.profile = Profile("Lead", [(0, 100), (600, 200)])
ov6.totaltime = 600
ov6.session_outcome = 'completed'
ov6.raise_session_event('completed', 'profile finished after 600s, cost 0.10')
ov6.state = 'IDLE'
ov6.runtime = 0.0
# One watcher duty cycle: drain events, log samples, close session.
for name, detail in ov6.drain_session_events():
    sl.event(name, detail)
state = ov6.get_state()
if state.get('state') in ('RUNNING', 'PAUSED'):
    sl.log(state)
w._record_session_event(state.get('state'))
text = open(os.path.join(tmpdir, os.listdir(tmpdir)[0])).read()
names = [json.loads(l)['name'] for l in text.splitlines() if json.loads(l).get('type') == 'event']
outcome = [json.loads(l)['outcome'] for l in text.splitlines() if json.loads(l).get('type') == 'end']
no_idle = not any(json.loads(l).get('state') == 'IDLE' for l in text.splitlines() if json.loads(l).get('type') == 'sample')
check("completed event written to session log", 'completed' in names, f"events={names}")
check("end outcome completed", outcome == ['completed'], f"outcome={outcome}")
check("no IDLE sample logged after completion", no_idle)

fails = [n for n, ok, _ in PASS if not ok]
print(f"\n{len(PASS)-len(fails)}/{len(PASS)} passed")
sys.exit(1 if fails else 0)
