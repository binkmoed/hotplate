"""Integration test for session logging. Run: python3 tests/test_sessionlog.py"""
import sys, os, json, time, tempfile, shutil
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'lib'))

from sessionlog import SessionLogger
from oven import Profile
from ovenWatcher import OvenWatcher

tmp = tempfile.mkdtemp()
log = SessionLogger(tmp, max_sessions=3)

prof = Profile("Bisque", [(0, 20), (600, 1000)])

# Simulate a full firing
log.start(prof)
assert log.recording
for t, temp in [(0, 20), (60, 120), (120, 250)]:
    log.log({'state': 'RUNNING', 'runtime': t, 'temperature': temp, 'target': temp + 5, 'cost': 0.1 * t})
log.event('pause')
log.log({'state': 'PAUSED', 'runtime': 121, 'temperature': 240, 'target': 250, 'cost': 12.1})
log.event('resume')
log.log({'state': 'RUNNING', 'runtime': 130, 'temperature': 260, 'target': 265, 'cost': 13.0})
log.stop('completed-or-aborted')

sessions = log.list_sessions()
assert len(sessions) == 1, sessions
s = sessions[0]
assert s['profile']['name'] == "Bisque"
assert s['peak_temperature'] == 260, s
assert s['runtime'] == 130
assert 'outcome' in s

raw = log.get_log(s['id'])
lines = [json.loads(l) for l in raw.strip().split('\n')]
types = [l['type'] for l in lines]
assert types[0] == 'meta' and types[-1] == 'end'
assert 'event' in types and types.count('sample') == 5, types

# Sample lines must decode with the same keys the app's HotplateStatus expects
sample = [l for l in lines if l['type'] == 'sample'][0]
for key in ('runtime', 'temperature', 'target', 'state', 'cost'):
    assert key in sample, key
print("PASS: session file schema matches HotplateStatus wire format")

# Retention: max_sessions=3 prunes oldest
for i in range(5):
    log.start(Profile(f"P{i}", [(0, 10), (60, 100)]))
    log.stop('completed')
assert len(log._session_files()) == 3, log._session_files()
print("PASS: retention prunes to max_sessions")

# Path traversal rejected
assert log.get_log('../../etc/passwd') is None
print("PASS: path traversal rejected")

# Watcher integration: state transitions emit events / stop
class FakeOven:
    def __init__(self): self.state = 'IDLE'
    def get_state(self): return {'state': self.state, 'runtime': 1, 'temperature': 20, 'target': 0, 'cost': 0}
fake = FakeOven()
log2 = SessionLogger(tmp)
w = OvenWatcher.__new__(OvenWatcher)  # skip thread init
OvenWatcher.__init__(w, fake, session_logger=log2)
w.record(Profile("W", [(0, 10), (60, 100)]))
fake.state = 'RUNNING'; w._record_session_event('RUNNING')
fake.state = 'PAUSED'; w._record_session_event('PAUSED')
fake.state = 'RUNNING'; w._record_session_event('RUNNING')
fake.state = 'IDLE'; w._record_session_event('IDLE')
assert not log2.recording, "logger should be closed after firing ends"
lines2 = [json.loads(l) for l in open(os.path.join(tmp, log2.current_id))]
names = [l['name'] for l in lines2 if l['type'] == 'event']
assert names == ['run', 'pause', 'resume'], names
print("PASS: watcher emits run/pause/resume events and closes session")

shutil.rmtree(tmp)
print("\nAll session-log tests passed")
