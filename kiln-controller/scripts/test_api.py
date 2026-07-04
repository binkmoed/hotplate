#!/usr/bin/env python3

import requests
import websocket
import json
import time
import sys


class APITester:
    def __init__(self, host='localhost', port=8080):
        self.base_url = f"http://{host}:{port}"
        self.ws_url = f"ws://{host}:{port}"
        self.session = requests.Session()

    def print_result(self, test_name, success, message=""):
        status = "✓ PASS" if success else "✗ FAIL"
        print(f"{status}: {test_name}")
        if message:
            print(f"  {message}")

    def test_connection(self):
        try:
            response = self.session.get(f"{self.base_url}/api/stats", timeout=5)
            success = response.status_code == 200
            self.print_result("Connection Test", success, f"Status: {response.status_code}")
            return success
        except Exception as e:
            self.print_result("Connection Test", False, str(e))
            return False

    def test_get_stats(self):
        try:
            response = self.session.get(f"{self.base_url}/api/stats", timeout=5)
            success = response.status_code == 200
            self.print_result("GET /api/stats", success, f"Status: {response.status_code}")
            return success
        except Exception as e:
            self.print_result("GET /api/stats", False, str(e))
            return False

    def test_stop_command(self):
        try:
            response = self.session.post(
                f"{self.base_url}/api",
                json={"cmd": "stop"},
                timeout=5
            )
            data = response.json()
            success = data.get('success', False)
            self.print_result("POST /api (stop)", success)
            return success
        except Exception as e:
            self.print_result("POST /api (stop)", False, str(e))
            return False

    def test_invalid_json(self):
        try:
            response = self.session.post(
                f"{self.base_url}/api",
                data="invalid json",
                timeout=5
            )
            data = response.json()
            success = 'error' in data and data['error'] == 'Invalid JSON'
            self.print_result("POST /api (invalid JSON)", success, f"Error: {data.get('error')}")
            return success
        except Exception as e:
            self.print_result("POST /api (invalid JSON)", False, str(e))
            return False

    def test_missing_cmd(self):
        try:
            response = self.session.post(
                f"{self.base_url}/api",
                json={"other": "data"},
                timeout=5
            )
            data = response.json()
            success = 'error' in data and 'cmd' in data['error']
            self.print_result("POST /api (missing cmd)", success, f"Error: {data.get('error')}")
            return success
        except Exception as e:
            self.print_result("POST /api (missing cmd)", False, str(e))
            return False

    def test_unknown_command(self):
        try:
            response = self.session.post(
                f"{self.base_url}/api",
                json={"cmd": "unknown"},
                timeout=5
            )
            data = response.json()
            success = 'error' in data and 'Unknown command' in data['error']
            self.print_result("POST /api (unknown command)", success, f"Error: {data.get('error')}")
            return success
        except Exception as e:
            self.print_result("POST /api (unknown command)", False, str(e))
            return False

    def test_run_nonexistent_profile(self):
        try:
            response = self.session.post(
                f"{self.base_url}/api",
                json={"cmd": "run", "profile": "NonExistentProfile"},
                timeout=5
            )
            data = response.json()
            success = data.get('success', False) == False and 'not found' in data.get('error', '')
            self.print_result("POST /api (run nonexistent profile)", success, f"Error: {data.get('error')}")
            return success
        except Exception as e:
            self.print_result("POST /api (run nonexistent profile)", False, str(e))
            return False

    def test_status_websocket(self):
        try:
            ws = websocket.create_connection(f"{self.ws_url}/status", timeout=5)

            first_message = ws.recv()
            data = json.loads(first_message)

            success = data.get('type') == 'backlog'
            self.print_result("WebSocket /status (backlog)", success, f"Type: {data.get('type')}")

            ws.close()
            return success
        except Exception as e:
            self.print_result("WebSocket /status (backlog)", False, str(e))
            return False

    def test_config_websocket(self):
        try:
            ws = websocket.create_connection(f"{self.ws_url}/config", timeout=5)

            ws.send("GET")

            response = ws.recv()
            data = json.loads(response)

            success = 'temp_scale' in data and 'kwh_rate' in data
            self.print_result("WebSocket /config", success, f"Keys: {list(data.keys())}")

            ws.close()
            return success
        except Exception as e:
            self.print_result("WebSocket /config", False, str(e))
            return False

    def test_storage_websocket(self):
        try:
            ws = websocket.create_connection(f"{self.ws_url}/storage", timeout=5)

            first_response = ws.recv()
            profiles = json.loads(first_response)

            success = isinstance(profiles, list)
            self.print_result("WebSocket /storage (list)", success, f"Profiles: {len(profiles)}")

            ws.close()
            return success
        except Exception as e:
            self.print_result("WebSocket /storage (list)", False, str(e))
            return False

    def test_save_profile(self):
        test_profile = {
            "type": "profile",
            "name": "Test_Profile_API",
            "temp_units": "c",
            "data": [[0, 25], [600, 100], [1200, 150]]
        }

        try:
            ws = websocket.create_connection(f"{self.ws_url}/storage", timeout=5)

            ws.recv()

            ws.send(json.dumps({
                "cmd": "PUT",
                "profile": test_profile,
                "force": True
            }))

            response = ws.recv()
            data = json.loads(response)

            success = data.get('resp') == 'OK'
            self.print_result("WebSocket /storage (save profile)", success, f"Response: {data.get('resp')}")

            if success:
                ws.close()
                return self._delete_profile("Test_Profile_API")

            ws.close()
            return success
        except Exception as e:
            self.print_result("WebSocket /storage (save profile)", False, str(e))
            return False

    def _delete_profile(self, profile_name):
        try:
            ws = websocket.create_connection(f"{self.ws_url}/storage", timeout=5)

            ws.recv()

            ws.send(json.dumps({
                "cmd": "DELETE",
                "profile": {"name": profile_name}
            }))

            response = ws.recv()
            data = json.loads(response)

            success = data.get('resp') == 'OK'
            self.print_result("WebSocket /storage (delete profile)", success, f"Response: {data.get('resp')}")

            ws.close()
            return success
        except Exception as e:
            self.print_result("WebSocket /storage (delete profile)", False, str(e))
            return False

    def test_control_websocket(self):
        try:
            ws = websocket.create_connection(f"{self.ws_url}/control", timeout=5)

            ws.send(json.dumps({"cmd": "STOP"}))

            time.sleep(0.5)

            ws.close()

            self.print_result("WebSocket /control (stop)", True, "Command sent")
            return True
        except Exception as e:
            self.print_result("WebSocket /control (stop)", False, str(e))
            return False

    def test_get_config(self):
        try:
            response = self.session.get(f"{self.base_url}/api/config", timeout=5)
            data = response.json()
            success = 'hardware' in data and 'pid' in data and 'safety' in data
            self.print_result("GET /api/config", success, f"Sections: {list(data.keys())}")
            return success
        except Exception as e:
            self.print_result("GET /api/config", False, str(e))
            return False

    def test_update_config(self):
        try:
            updates = {
                "display.kwh_rate": 0.30,
                "display.currency_type": "$"
            }

            response = self.session.post(
                f"{self.base_url}/api/config",
                json=updates,
                timeout=5
            )
            data = response.json()

            success = data.get('success', False)
            self.print_result("POST /api/config (update)", success, f"Response: {data}")

            if success:
                updates_restore = {
                    "display.kwh_rate": 0.25,
                    "display.currency_type": "€"
                }
                self.session.post(f"{self.base_url}/api/config", json=updates_restore, timeout=5)

            return success
        except Exception as e:
            self.print_result("POST /api/config (update)", False, str(e))
            return False

    def run_all_tests(self):
        print("\n" + "="*60)
        print("KILN CONTROLLER API TEST SUITE")
        print("="*60 + "\n")

        tests = [
            ("Connection", self.test_connection),
            ("GET /api/stats", self.test_get_stats),
            ("POST /api (stop)", self.test_stop_command),
            ("POST /api (invalid JSON)", self.test_invalid_json),
            ("POST /api (missing cmd)", self.test_missing_cmd),
            ("POST /api (unknown command)", self.test_unknown_command),
            ("POST /api (run nonexistent)", self.test_run_nonexistent_profile),
            ("WebSocket /status", self.test_status_websocket),
            ("WebSocket /config", self.test_config_websocket),
            ("WebSocket /storage (list)", self.test_storage_websocket),
            ("WebSocket /storage (save)", self.test_save_profile),
            ("WebSocket /control", self.test_control_websocket),
            ("GET /api/config", self.test_get_config),
            ("POST /api/config (update)", self.test_update_config),
        ]

        passed = 0
        failed = 0

        for test_name, test_func in tests:
            try:
                if test_func():
                    passed += 1
                else:
                    failed += 1
            except Exception as e:
                print(f"✗ FAIL: {test_name} - Exception: {e}")
                failed += 1

            time.sleep(0.2)

        print("\n" + "="*60)
        print(f"RESULTS: {passed} passed, {failed} failed out of {passed + failed} tests")
        print("="*60 + "\n")

        return failed == 0


def main():
    if len(sys.argv) > 1:
        host = sys.argv[1]
    else:
        host = 'localhost'

    if len(sys.argv) > 2:
        port = int(sys.argv[2])
    else:
        port = 8080

    print(f"Testing API at {host}:{port}")

    tester = APITester(host=host, port=port)
    success = tester.run_all_tests()

    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()