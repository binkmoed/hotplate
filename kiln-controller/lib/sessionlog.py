"""Persistent firing-session logs.

Each firing is recorded as one JSON-lines file under ``storage/sessions``:

  line 1: {"type":"meta", "profile": {...}, "started": epoch, ...}
  ...    {"type":"sample", ...oven state...}        (one per duty cycle)
  ...    {"type":"event", "name":"...", ...}        (pause/resume/lid/abort...)
  last:  {"type":"end", "outcome":"completed|aborted", ...}

Sample lines reuse the exact dict produced by ``Oven.get_state()`` so the
iOS app can decode them with its existing ``KilnStatus`` model.
"""
import json
import os
import re
import time


class SessionLogger:
    def __init__(self, sessions_dir, max_sessions=0):
        self.sessions_dir = sessions_dir
        self.max_sessions = max_sessions  # 0 = keep everything
        self.file = None
        self.current_id = None
        self.meta = None

    # ------------------------------------------------------------------
    # Recording
    # ------------------------------------------------------------------

    def start(self, profile, startat=0):
        self.stop()  # close any dangling session
        os.makedirs(self.sessions_dir, exist_ok=True)
        stamp = time.strftime('%Y%m%d_%H%M%S')
        safe = re.sub(r'[^A-Za-z0-9_-]+', '_', profile.name if profile else 'firing')
        self.current_id = f"{stamp}_{safe}.jsonl"
        path = os.path.join(self.sessions_dir, self.current_id)
        self.meta = {
            'type': 'meta',
            'id': self.current_id,
            'started': time.time(),
            'startat': startat,
            'duration': profile.get_duration() if profile else 0,
            'profile': profile.to_dict() if profile else None,
        }
        try:
            self.file = open(path, 'a')
            self.file.write(json.dumps(self.meta) + '\n')
            self.file.flush()
        except Exception as e:
            print(f"SessionLogger: cannot open {path}: {e}")
            self.file = None
        self._prune()

    def log(self, state):
        if self.file is None:
            return
        try:
            rec = dict(state)
            rec['type'] = 'sample'
            self.file.write(json.dumps(rec) + '\n')
            self.file.flush()
        except Exception as e:
            print(f"SessionLogger: write failed: {e}")
            self.stop()

    def event(self, name, detail=""):
        if self.file is None:
            return
        try:
            self.file.write(json.dumps({
                'type': 'event', 'name': name, 'detail': detail, 'time': time.time(),
            }) + '\n')
            self.file.flush()
        except Exception as e:
            print(f"SessionLogger: write failed: {e}")
            self.stop()

    def stop(self, outcome=None):
        if self.file is not None:
            try:
                self.file.write(json.dumps({
                    'type': 'end',
                    'outcome': outcome or 'aborted',
                    'ended': time.time(),
                }) + '\n')
                self.file.flush()
                self.file.close()
            except Exception as e:
                print(f"SessionLogger: close failed: {e}")
            self.file = None

    @property
    def recording(self):
        return self.file is not None

    # ------------------------------------------------------------------
    # Retrieval
    # ------------------------------------------------------------------

    def _session_files(self):
        if not os.path.isdir(self.sessions_dir):
            return []
        files = [f for f in os.listdir(self.sessions_dir) if f.endswith('.jsonl')]
        return sorted(files, reverse=True)  # newest first

    def list_sessions(self):
        """Summary list: meta plus peak temp / runtime from a tail scan."""
        sessions = []
        for name in self._session_files():
            path = os.path.join(self.sessions_dir, name)
            meta, summary = self._scan_file(path)
            if meta is None:
                continue
            meta.update(summary)
            sessions.append(meta)
        return sessions

    def _scan_file(self, path):
        meta, outcome = None, None
        peak = None
        last = None
        try:
            with open(path) as f:
                for line in f:
                    try:
                        rec = json.loads(line)
                    except Exception:
                        continue
                    rtype = rec.get('type')
                    if rtype == 'meta' and meta is None:
                        meta = {
                            'id': rec.get('id') or os.path.basename(path),
                            'started': rec.get('started'),
                            'profile': rec.get('profile'),
                        }
                    elif rtype == 'sample':
                        last = rec
                        t = rec.get('temperature')
                        if t is not None and (peak is None or t > peak):
                            peak = t
                    elif rtype == 'end':
                        outcome = rec.get('outcome')
        except Exception:
            return None, {}
        if meta is None:
            return None, {}
        summary = {
            'peak_temperature': peak,
            'runtime': last.get('runtime') if last else None,
            'cost': last.get('cost') if last else None,
            'outcome': outcome or ('in-progress' if last else 'unknown'),
        }
        return meta, summary

    def get_log(self, session_id):
        """Return the raw JSON-lines text for a session, or None."""
        if '/' in session_id or session_id.startswith('.'):
            return None  # reject path tricks
        path = os.path.join(self.sessions_dir, session_id)
        if not os.path.isfile(path):
            return None
        try:
            with open(path) as f:
                return f.read()
        except Exception:
            return None

    def delete(self, session_id):
        """Delete one session file. Returns True on success.
        Refuses to delete the session currently being recorded."""
        if '/' in session_id or session_id.startswith('.'):
            return False
        if session_id == self.current_id and self.recording:
            return False
        path = os.path.join(self.sessions_dir, session_id)
        if not os.path.isfile(path):
            return False
        try:
            os.remove(path)
            return True
        except Exception as e:
            print(f"SessionLogger: delete failed: {e}")
            return False

    # ------------------------------------------------------------------
    # Retention
    # ------------------------------------------------------------------

    def finalize_dangling(self):
        """Close any session files left without an end line (e.g. the
        controller was power-cycled mid-firing). Without this they show
        up as 'in-progress' forever in the app's history."""
        if not os.path.isdir(self.sessions_dir):
            return 0
        closed = 0
        for name in self._session_files():
            path = os.path.join(self.sessions_dir, name)
            has_end = False
            try:
                with open(path) as f:
                    for line in f:
                        try:
                            if json.loads(line).get('type') == 'end':
                                has_end = True
                                break
                        except Exception:
                            continue
            except Exception:
                pass
            if not has_end:
                try:
                    with open(path, 'a') as f:
                        f.write(json.dumps({
                            'type': 'end',
                            'outcome': 'aborted',
                            'ended': time.time(),
                            'detail': 'interrupted by controller restart',
                        }) + '\n')
                    closed += 1
                    print(f"SessionLogger: finalized dangling session {name}")
                except Exception as e:
                    print(f"SessionLogger: cannot finalize {name}: {e}")
        return closed

    def _prune(self):
        if self.max_sessions <= 0:
            return
        files = self._session_files()
        # Never delete the session currently being written.
        excess = [f for f in files[self.max_sessions:] if f != self.current_id]
        for name in excess:
            try:
                os.remove(os.path.join(self.sessions_dir, name))
            except Exception:
                pass
