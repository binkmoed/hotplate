import threading
import time
import json
from collections import deque
from config import config


class OvenWatcher(threading.Thread):
    """Broadcasts oven state to WebSocket observers every duty cycle."""

    def __init__(self, oven, session_logger=None):
        super().__init__()
        self.daemon = True
        self.running = False
        self.oven = oven
        self.session_logger = session_logger
        self.observers = []
        self.backlog = deque(maxlen=50)
        self.backlog_profile = None
        self.lock = threading.Lock()
        self._last_state = None
        self._last_sample = {}

    def add_observer(self, ws):
        with self.lock:
            self.observers.append(ws)
            observers_snapshot = list(self.observers)
        # Send backlog *outside* the lock so a slow client can't stall others
        self._send_backlog(ws)

    def remove_observer(self, ws):
        with self.lock:
            if ws in self.observers:
                self.observers.remove(ws)

    def _send_backlog(self, ws):
        try:
            backlog_data = {
                'type': 'backlog',
                'profile': self.backlog_profile.to_dict() if self.backlog_profile else None,
                'log': list(self.backlog),
            }
            ws.send(json.dumps(backlog_data))
        except Exception as e:
            print(f"Error sending backlog: {e}")

    def record(self, profile):
        with self.lock:
            self.backlog.clear()
            self.backlog_profile = profile
        if profile is not None and self.session_logger is not None:
            self.session_logger.start(profile)

    def _record_session_event(self, state):
        """Translate oven state transitions into session log events."""
        if self.session_logger is None:
            return
        prev, cur = self._last_state, state
        if prev != cur:
            if cur == 'RUNNING':
                self.session_logger.event('run' if prev is None else 'resume')
            elif cur == 'PAUSED':
                self.session_logger.event('pause')
            elif prev in ('RUNNING', 'PAUSED'):
                # Trust the oven's explicit outcome (set at the moment of
                # transition) rather than guessing from the last sample —
                # completion happens between broadcasts, so the last sample
                # almost always shows runtime < totaltime.
                outcome = getattr(self.oven, 'session_outcome', None)
                if outcome is None:
                    runtime = self._last_sample.get('runtime') or 0
                    total = self._last_sample.get('totaltime') or 0
                    outcome = 'completed' if total and runtime >= total else 'aborted'
                self.session_logger.stop(outcome)
                self.oven.clear_session_outcome()
        self._last_state = state

    def run(self):
        self.running = True
        while self.running:
            try:
                state = self.oven.get_state()
                self.backlog.append(state)
                state_json = json.dumps(state)
                if self.session_logger is not None:
                    # Write any events raised by the oven thread since the
                    # last cycle (abort reasons, sensor retries, stalls…).
                    for name, detail in self.oven.drain_session_events():
                        self.session_logger.event(name, detail)
                    self.session_logger.log(state)
                    self._last_sample = state
                    self._record_session_event(state.get('state'))

                with self.lock:
                    observers_snapshot = list(self.observers)

                dead = []
                for ws in observers_snapshot:
                    try:
                        ws.send(state_json)
                    except Exception as e:
                        print(f"Error sending state to observer: {e}")
                        dead.append(ws)

                if dead:
                    with self.lock:
                        for ws in dead:
                            if ws in self.observers:
                                self.observers.remove(ws)

                time.sleep(config.duty_cycle)

            except Exception as e:
                print(f"Error in OvenWatcher: {e}")

    def stop(self):
        self.running = False
        with self.lock:
            self.observers.clear()
