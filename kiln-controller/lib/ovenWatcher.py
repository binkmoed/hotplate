import threading
import time
import json
from collections import deque
from config import config


class OvenWatcher(threading.Thread):
    """Broadcasts oven state to WebSocket observers every duty cycle."""

    def __init__(self, oven):
        super().__init__()
        self.daemon = True
        self.running = False
        self.oven = oven
        self.observers = []
        self.backlog = deque(maxlen=50)
        self.backlog_profile = None
        self.lock = threading.Lock()

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

    def run(self):
        self.running = True
        while self.running:
            try:
                state = self.oven.get_state()
                self.backlog.append(state)
                state_json = json.dumps(state)

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
