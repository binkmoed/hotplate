#!/usr/bin/env python3

import sys
import os
import time
import json
import threading

from bottle import Bottle, request, response, abort
from gevent.pywsgi import WSGIServer
from geventwebsocket.handler import WebSocketHandler
from geventwebsocket import WebSocketError

from config import config
from lib.oven import Oven, Profile
from lib.tempSensor import TempSensor
from lib.hardware import HardwareController
from lib.ovenWatcher import OvenWatcher
from lib.alerting import AlertManager
from lib.sessionlog import SessionLogger


# ---------------------------------------------------------------------------
# Bottle application — routes are registered here (module-level on the app)
# ---------------------------------------------------------------------------
app = Bottle()

# Global controller instance, created in main()
controller = None


def get_ws():
    """Extract the WebSocket from the request environment."""
    ws = request.environ.get('wsgi.websocket')
    if ws is None:
        abort(400, 'Expected WebSocket request.')
    return ws


# ---------------------------------------------------------------------------
# REST routes
# ---------------------------------------------------------------------------

@app.route('/')
def index():
    return "Kiln Controller API. See api.md for documentation."


@app.route('/api/stats')
def get_stats():
    response.content_type = 'application/json'

    if controller.oven.state == 'IDLE':
        return ''

    stats = controller.oven.pid.get_stats()
    if not stats:
        return ''

    return json.dumps(stats)


@app.post('/api')
def handle_api_command():
    response.content_type = 'application/json'

    try:
        body = request.json
    except Exception:
        return json.dumps({'success': False, 'error': 'Invalid JSON'})

    if not isinstance(body, dict):
        return json.dumps({'success': False, 'error': 'Invalid request format'})

    cmd = body.get('cmd')
    if not cmd:
        return json.dumps({'success': False, 'error': 'Missing cmd parameter'})

    try:
        if cmd == 'run':
            profile_name = body.get('profile')
            startat = body.get('startat', 0)

            if not profile_name:
                return json.dumps({'success': False, 'error': 'Missing profile name'})

            try:
                startat = float(startat)
            except (ValueError, TypeError):
                return json.dumps({'success': False, 'error': 'Invalid startat value'})

            return controller.run_profile(profile_name, startat)

        elif cmd == 'pause':
            return controller.pause()

        elif cmd == 'resume':
            return controller.resume()

        elif cmd == 'stop':
            return controller.stop()

        elif cmd == 'memo':
            memo = body.get('memo', '')
            print(f"Memo: {memo}")
            return json.dumps({'success': True})

        elif cmd == 'stats':
            stats = controller.oven.pid.get_stats()
            return json.dumps(stats) if stats else ''

        else:
            return json.dumps({'success': False, 'error': f'Unknown command: {cmd}'})

    except Exception as e:
        print(f"Error handling command '{cmd}': {e}")
        return json.dumps({'success': False, 'error': str(e)})


@app.get('/api/config')
def get_config():
    response.content_type = 'application/json'
    return json.dumps(config.to_dict())


@app.post('/api/config')
def update_config():
    response.content_type = 'application/json'

    try:
        updates = request.json
        if not isinstance(updates, dict):
            return json.dumps({'success': False, 'error': 'Invalid request format'})

        restart_required = False
        warnings = []

        sensor_type = config.sensor_type.upper()

        if 'hardware.thermocouple_type_max31856' in updates:
            tc_type = str(updates['hardware.thermocouple_type_max31856']).upper()
            if sensor_type == 'MAX31856':
                from lib.max31856 import MAX31856
                if tc_type not in MAX31856.THERMOCOUPLE_TYPES:
                    return json.dumps({
                        'success': False,
                        'error': f"Invalid thermocouple type '{tc_type}' for MAX31856. "
                                 f"Supported: {', '.join(MAX31856.THERMOCOUPLE_TYPES)}"
                    })
            elif sensor_type == 'MAX31855':
                warnings.append(
                    "MAX31855 only supports Type K. "
                    "thermocouple_type_max31856 will be ignored."
                )

        if 'hardware.thermocouple_type_max31855' in updates:
            tc_type = str(updates['hardware.thermocouple_type_max31855']).upper()
            if sensor_type == 'MAX31855':
                from lib.max31855 import MAX31855
                if not MAX31855.is_type_supported(tc_type):
                    return json.dumps({
                        'success': False,
                        'error': f"Invalid thermocouple type '{tc_type}' for MAX31855. "
                                 "Only Type K is supported."
                    })

        if 'hardware.sensor_type' in updates:
            new_sensor = str(updates['hardware.sensor_type']).upper()
            if new_sensor != sensor_type:
                restart_required = True
                warnings.append(
                    f"Sensor type changing from {sensor_type} to {new_sensor}. "
                    "Restart required."
                )

        for key, value in updates.items():
            if key.startswith('hardware.'):
                restart_required = True
            elif key.startswith('pid.'):
                if key == 'pid.kp':
                    controller.oven.pid.kp = value
                elif key == 'pid.ki':
                    controller.oven.pid.ki = value
                elif key == 'pid.kd':
                    controller.oven.pid.kd = value

        config.update(updates)

        result = {
            'success': True,
            'restart_required': restart_required,
            'warnings': warnings,
            'message': 'Configuration updated' +
                       ('. Restart required for hardware changes.' if restart_required else '')
        }
        return json.dumps(result)

    except Exception as e:
        return json.dumps({'success': False, 'error': str(e)})


# ---------------------------------------------------------------------------
# WebSocket routes
# ---------------------------------------------------------------------------

@app.route('/status')
def handle_status():
    ws = get_ws()
    controller.watcher.add_observer(ws)
    try:
        while True:
            message = ws.receive()
            if message is None:
                break
    except WebSocketError:
        pass
    finally:
        controller.watcher.remove_observer(ws)


@app.route('/control')
def handle_control():
    ws = get_ws()
    try:
        while True:
            message = ws.receive()
            if message is None:
                break
            try:
                data = json.loads(message)
                cmd = data.get('cmd', '').upper()

                if cmd == 'RUN':
                    profile_data = data.get('profile')
                    if profile_data:
                        profile = Profile.from_dict(profile_data)
                        if controller.hardware.enable_safety_relay():
                            controller.oven.run_profile(profile)
                            controller.watcher.record(profile)
                        # If the relay can't be enabled (lid open) the
                        # profile simply doesn't start.
                elif cmd == 'STOP':
                    controller.oven.stop()
                    controller.watcher.record(None)
                elif cmd == 'SIMULATE':
                    pass
            except json.JSONDecodeError:
                pass
    except WebSocketError:
        pass


@app.route('/api/sessions')
def handle_sessions_list():
    """List recorded firing sessions (newest first)."""
    response.content_type = 'application/json'
    return json.dumps(controller.session_logger.list_sessions())


@app.route('/api/sessions/<session_id>')
def handle_session_get(session_id):
    """Return the full JSON-lines log for one session."""
    log = controller.session_logger.get_log(session_id)
    if log is None:
        abort(404, 'Session not found')
    response.content_type = 'application/x-ndjson'
    return log


@app.route('/api/sessions/<session_id>', method='DELETE')
def handle_session_delete(session_id):
    """Delete one recorded session (refuses the in-progress one)."""
    if controller.session_logger.delete(session_id):
        response.content_type = 'application/json'
        return json.dumps({'success': True})
    abort(404, 'Session not found or in progress')


@app.route('/storage')
def handle_storage():
    ws = get_ws()

    def list_profiles():
        profiles = []
        profiles_dir = config.profiles_dir
        if os.path.exists(profiles_dir):
            for filename in os.listdir(profiles_dir):
                if filename.endswith('.json'):
                    filepath = os.path.join(profiles_dir, filename)
                    try:
                        with open(filepath, 'r') as f:
                            profiles.append(json.load(f))
                    except Exception:
                        pass
        ws.send(json.dumps(profiles))

    def save_profile(data):
        try:
            profile = data.get('profile')
            force = data.get('force', False)

            if not profile:
                ws.send(json.dumps({'resp': 'FAIL', 'error': 'No profile data'}))
                return

            profile_name = profile.get('name')
            if not profile_name:
                ws.send(json.dumps({'resp': 'FAIL', 'error': 'No profile name'}))
                return

            filepath = os.path.join(config.profiles_dir, f"{profile_name}.json")

            if os.path.exists(filepath) and not force:
                ws.send(json.dumps({
                    'cmd': 'PUT',
                    'profile': profile,
                    'resp': 'FAIL',
                    'error': 'Profile already exists'
                }))
                return

            os.makedirs(config.profiles_dir, exist_ok=True)
            with open(filepath, 'w') as f:
                json.dump(profile, f, indent=2)

            ws.send(json.dumps({
                'cmd': 'PUT',
                'profile': profile,
                'resp': 'OK'
            }))
            list_profiles()

        except Exception as e:
            ws.send(json.dumps({'resp': 'FAIL', 'error': str(e)}))

    def delete_profile(data):
        try:
            profile_name = data.get('profile', {}).get('name')
            if not profile_name:
                ws.send(json.dumps({'resp': 'FAIL', 'error': 'No profile name'}))
                return

            filepath = os.path.join(config.profiles_dir, f"{profile_name}.json")

            if not os.path.exists(filepath):
                ws.send(json.dumps({
                    'cmd': 'DELETE',
                    'profile': {'name': profile_name},
                    'resp': 'FAIL',
                    'error': 'Profile not found'
                }))
                return

            os.remove(filepath)
            ws.send(json.dumps({
                'cmd': 'DELETE',
                'profile': {'name': profile_name},
                'resp': 'OK'
            }))
            list_profiles()

        except Exception as e:
            ws.send(json.dumps({'resp': 'FAIL', 'error': str(e)}))

    # Send initial profile list on connect
    list_profiles()

    try:
        while True:
            message = ws.receive()
            if message is None:
                break

            if message == 'GET':
                list_profiles()
            else:
                try:
                    data = json.loads(message)
                    cmd = data.get('cmd', '').upper()
                    if cmd == 'PUT':
                        save_profile(data)
                    elif cmd == 'DELETE':
                        delete_profile(data)
                except json.JSONDecodeError:
                    pass
    except WebSocketError:
        pass


@app.route('/config')
def handle_config():
    ws = get_ws()

    def send_config():
        config_data = {
            'temp_scale': config.temp_scale,
            'time_scale_slope': config.time_scale_slope,
            'time_scale_profile': config.time_scale_profile,
            'kwh_rate': config.kwh_rate,
            'currency_type': config.currency_type,
            'kw_elements': config.kw_elements
        }
        ws.send(json.dumps(config_data))

    send_config()

    try:
        while True:
            message = ws.receive()
            if message is None:
                break
            if message == 'GET':
                send_config()
    except WebSocketError:
        pass


# ---------------------------------------------------------------------------
# Main controller class
# ---------------------------------------------------------------------------

class KilnController:
    def __init__(self):
        print("Initializing Kiln Controller...")

        self.hardware = HardwareController()
        print("Hardware controller initialized")

        self.temp_sensor = TempSensor()
        self.temp_sensor.start()
        print("Temperature sensor started")

        self.alert_manager = AlertManager()
        print("Alert manager initialized")

        self.oven = Oven(self.temp_sensor, self.hardware, self.alert_manager)
        print("Oven initialized")

        self.session_logger = SessionLogger(
            config.sessions_dir, max_sessions=config.max_sessions)
        # Close any sessions left open by a previous unclean shutdown so
        # they don't linger as 'in-progress' in the app's history.
        self.session_logger.finalize_dangling()
        self.watcher = OvenWatcher(self.oven, session_logger=self.session_logger)
        print("Oven watcher initialized (session logging enabled)")

        self.check_automatic_restart()

        print("Kiln Controller initialized successfully")

    def check_automatic_restart(self):
        if not config.automatic_restarts:
            return

        saved_state = Oven.load_state()
        if saved_state is None:
            return

        print(f"Found saved state from {time.ctime(saved_state.get('saved_at', 0))}")

        if saved_state.get('state') == 'RUNNING':
            profile_name = saved_state.get('profile')
            if profile_name:
                profile_path = os.path.join(config.profiles_dir, f"{profile_name}.json")
                if os.path.exists(profile_path):
                    try:
                        with open(profile_path, 'r') as f:
                            profile_data = json.load(f)
                        profile = Profile.from_dict(profile_data)
                        startat = saved_state.get('runtime', 0)

                        if self.hardware.enable_safety_relay():
                            self.oven.run_profile(profile, startat=startat, allow_seek=False)
                            self.watcher.record(profile)
                            self.watcher.start()
                        else:
                            print("Auto-restart aborted: cannot enable safety relay (lid open?)")

                        print(f"Resumed profile '{profile_name}' at {startat}s")
                        self.alert_manager.send_alert(
                            "AUTO_RESTART",
                            f"Automatically resumed profile '{profile_name}' after restart",
                            "info"
                        )
                        if os.path.exists(config.state_file):
                            os.remove(config.state_file)
                    except Exception as e:
                        print(f"Failed to resume profile: {e}")
                else:
                    print(f"Profile file not found: {profile_path}")

    def start(self):
        self.oven.start()
        self.watcher.start()
        print("Oven and watcher threads started")

        print(f"Starting server on {config.host}:{config.port}")
        try:
            server = WSGIServer(
                (config.host, config.port),
                app,
                handler_class=WebSocketHandler
            )
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down...")
            self.shutdown()
        except Exception as e:
            print(f"Server error: {e}")
            self.shutdown()

    def shutdown(self):
        print("Shutting down kiln controller...")
        self.watcher.stop()
        self.oven.shutdown()
        self.temp_sensor.stop()
        self.hardware.cleanup()
        print("Shutdown complete")
        sys.exit(0)

    # --- Command helpers (called from REST route handlers) ---

    def run_profile(self, profile_name, startat=0):
        try:
            profile_path = os.path.join(config.profiles_dir, f"{profile_name}.json")
            if not os.path.exists(profile_path):
                return json.dumps({'success': False, 'error': f'profile {profile_name} not found'})

            with open(profile_path, 'r') as f:
                profile_data = json.load(f)
            profile = Profile.from_dict(profile_data)

            if not self.hardware.enable_safety_relay():
                return json.dumps({'success': False, 'error': 'Cannot start: lid is open'})

            self.oven.run_profile(profile, startat=startat)
            self.watcher.record(profile)
            self.alert_manager.send_alert(
                "FIRING_STARTED",
                f"Started firing profile '{profile_name}'",
                "info"
            )
            return json.dumps({'success': True})

        except Exception as e:
            print(f"Error running profile: {e}")
            return json.dumps({'success': False, 'error': f'Failed to run profile: {str(e)}'})

    def pause(self):
        if controller.oven.state != 'RUNNING':
            return json.dumps({'success': False, 'error': 'Can only pause when RUNNING'})
        controller.oven.pause()
        controller.alert_manager.send_alert(
            "FIRING_PAUSED",
            f"Firing paused at {controller.oven.runtime:.1f}s",
            "info"
        )
        return json.dumps({'success': True})

    def resume(self):
        if controller.oven.state != 'PAUSED':
            return json.dumps({'success': False, 'error': 'Can only resume when PAUSED'})
        controller.oven.resume()
        controller.alert_manager.send_alert(
            "FIRING_RESUMED",
            f"Firing resumed at {controller.oven.runtime:.1f}s",
            "info"
        )
        return json.dumps({'success': True})

    def stop(self):
        controller.oven.stop()
        controller.watcher.record(None)
        controller.alert_manager.send_alert(
            "FIRING_STOPPED",
            f"Firing stopped at {controller.oven.runtime:.1f}s",
            "warning"
        )
        return json.dumps({'success': True})


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    global controller
    try:
        controller = KilnController()
        controller.start()
    except Exception as e:
        print(f"Fatal error: {e}")
        if controller:
            controller.shutdown()
        sys.exit(1)


if __name__ == '__main__':
    main()
