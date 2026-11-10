import os
import json
import threading


def _deep_merge(base, override):
    """Recursively merge *override* into *base* (returns a new dict)."""
    result = dict(base)
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


class Config:
    """JSON-backed configuration with sensible defaults.

    The config file lives next to this script so the application works
    regardless of the current working directory (important for systemd).
    """

    def __init__(self):
        # Absolute path next to this file (kiln-controller/config.json)
        self._base_dir = os.path.dirname(os.path.abspath(__file__))
        self.config_file = os.path.join(self._base_dir, "config.json")
        self._lock = threading.RLock()
        self.load()

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def load(self):
        with self._lock:
            self.data = self._defaults()
            if os.path.exists(self.config_file):
                try:
                    with open(self.config_file, 'r') as f:
                        stored = json.load(f)
                    # Deep-merge so new default keys appear automatically
                    self.data = _deep_merge(self.data, stored)
                except Exception as e:
                    print(f"Error loading config, using defaults: {e}")
            # Ensure profiles dir exists (resolve relative to base dir)
            self._ensure_dirs()

    def save(self):
        with self._lock:
            tmp = self.config_file + ".tmp"
            with open(tmp, 'w') as f:
                json.dump(self.data, f, indent=2)
            os.replace(tmp, self.config_file)  # atomic

    def _ensure_dirs(self):
        profiles_dir = self.get("paths", "profiles_dir", default="storage/profiles")
        if not os.path.isabs(profiles_dir):
            profiles_dir = os.path.join(self._base_dir, profiles_dir)
        os.makedirs(profiles_dir, exist_ok=True)

    # ------------------------------------------------------------------
    # Dict helpers
    # ------------------------------------------------------------------

    def _defaults(self):
        return {
            "hardware": {
                "spi_bus": 0,
                "spi_device": 1,
                "sensor_type": "MAX31856",
                "thermocouple_type_max31856": "S",
                "thermocouple_type_max31855": "K",
                "ac_frequency": 50,
                "pin_ssr": 23,
                "pin_safety_relay": 18,
                "pin_lid_switch": 24,
                "kw_elements": 7.1,
            },
            "pid": {
                "kp": 3.0,
                "ki": 75.0,
                "kd": 12.0,
                "control_window": 50.0,
                "max_ssr_on_time": 6.0,
                "duty_cycle": 3.0,
                "max_ssr_on_percentage": 90.0,
                "temp_settle_time": 0.5,
            },
            "safety": {
                "emergency_shutoff_temp": 1300.0,
                "emergency_shutoff_temp_scale": "c",
                "ignore_temp_too_high": False,
                "max_tc_error_rate": 0.3,
                "ignore_tc_too_many_errors": False,
            },
            "display": {
                "temp_scale": "c",
                "time_scale_slope": "h",
                "time_scale_profile": "m",
                "kwh_rate": 0.25,
                "currency_type": "\u20ac",
            },
            "restart": {
                "automatic_restarts": True,
                "automatic_restart_window": 15,
                "seek_start": True,
            },
            "paths": {
                "storage_dir": "storage",
                "profiles_dir": "storage/profiles",
                "state_file": "state.json",
                "log_file": "kiln.log",
            },
            "alerting": {
                "enabled": False,
                "email_enabled": False,
                "email_smtp_server": "smtp.gmail.com",
                "email_smtp_port": 587,
                "email_username": "",
                "email_password": "",
                "email_from": "",
                "email_to": [],
                "sms_enabled": False,
                "sms_provider": "twilio",
                "sms_account_sid": "",
                "sms_auth_token": "",
                "sms_from": "",
                "sms_to": [],
            },
            "server": {
                "host": "0.0.0.0",
                "port": 8080,
            },
        }

    def get(self, *keys, default=None):
        current = self.data
        for key in keys:
            if not isinstance(current, dict) or key not in current:
                return default
            current = current[key]
        return current

    def set(self, *keys, value):
        current = self.data
        for key in keys[:-1]:
            if key not in current or not isinstance(current[key], dict):
                current[key] = {}
            current = current[key]
        current[keys[-1]] = value

    def update(self, updates):
        """Apply flat dot-notation updates, e.g. {'display.kwh_rate': 0.30}."""
        with self._lock:
            for key_path, value in updates.items():
                keys = key_path.split('.')
                self.set(*keys, value=value)
            self.save()

    def to_dict(self):
        return self.data

    # ------------------------------------------------------------------
    # Convenience properties
    # ------------------------------------------------------------------

    @property
    def spi_bus(self):
        return self.get("hardware", "spi_bus", default=0)

    @property
    def spi_device(self):
        return self.get("hardware", "spi_device", default=0)

    @property
    def sensor_type(self):
        return self.get("hardware", "sensor_type", default="MAX31856")

    @property
    def thermocouple_type(self):
        return self.get("hardware", "thermocouple_type", default="K")

    @property
    def thermocouple_type_max31856(self):
        return self.get("hardware", "thermocouple_type_max31856", default="K")

    @property
    def thermocouple_type_max31855(self):
        return self.get("hardware", "thermocouple_type_max31855", default="K")

    @property
    def ac_frequency(self):
        return self.get("hardware", "ac_frequency", default=50)

    @property
    def pin_ssr(self):
        return self.get("hardware", "pin_ssr", default=18)

    @property
    def pin_safety_relay(self):
        return self.get("hardware", "pin_safety_relay", default=23)

    @property
    def pin_lid_switch(self):
        return self.get("hardware", "pin_lid_switch", default=24)

    @property
    def lid_switch_enabled(self):
        return self.get("hardware", "lid_switch_enabled", default=True)

    @property
    def kw_elements(self):
        return self.get("hardware", "kw_elements", default=7.1)

    @property
    def pid_kp(self):
        return self.get("pid", "kp", default=3.0)

    @property
    def pid_ki(self):
        return self.get("pid", "ki", default=75.0)

    @property
    def pid_kd(self):
        return self.get("pid", "kd", default=12.0)

    @property
    def pid_control_window(self):
        return self.get("pid", "control_window", default=50.0)

    @property
    def pid_approach_window(self):
        """Degrees from target within which the soft-landing cap applies.
        0 disables the soft landing (full PID authority at all times)."""
        return self.get("pid", "approach_window", default=15.0)

    @property
    def pid_approach_max_output(self):
        """Maximum duty (percent) while inside the approach window."""
        return self.get("pid", "approach_max_output", default=40.0)

    @property
    def max_ssr_on_time(self):
        return self.get("pid", "max_ssr_on_time", default=6.0)

    @property
    def stall_window(self):
        """Seconds of saturated power (>=90% duty) with less than 2 degrees
        of temperature rise before a heating-stall warning is raised
        (suspect element / SSR / thermocouple). 0 disables the detection."""
        return self.get("pid", "stall_window", default=600.0)

    @property
    def stall_action(self):
        """What to do on a detected heating stall: 'abort' cuts power via the
        safety relay (safe default — a stuck-low thermocouple drives the
        elements at 100% uncontrolled), 'warn' only logs/alerts."""
        return self.get("pid", "stall_action", default="abort")

    @property
    def duty_cycle(self):
        return self.get("pid", "duty_cycle", default=3.0)

    @property
    def max_consecutive_read_failures(self):
        return self.get("pid", "max_consecutive_read_failures", default=3)

    @property
    def sessions_dir(self):
        return self.get("storage", "sessions_dir", default=os.path.join(os.path.dirname(__file__), "storage", "sessions"))

    @property
    def max_sessions(self):
        return self.get("storage", "max_sessions", default=0)

    @property
    def max_ssr_on_percentage(self):
        return self.get("pid", "max_ssr_on_percentage", default=90.0)

    @property
    def temp_settle_time(self):
        return self.get("pid", "temp_settle_time", default=0.5)

    @property
    def emergency_shutoff_temp(self):
        return self.get("safety", "emergency_shutoff_temp", default=1300.0)

    @property
    def emergency_shutoff_temp_scale(self):
        return self.get("safety", "emergency_shutoff_temp_scale", default="c")

    @property
    def ignore_temp_too_high(self):
        return self.get("safety", "ignore_temp_too_high", default=False)

    @property
    def max_tc_error_rate(self):
        return self.get("safety", "max_tc_error_rate", default=0.3)

    @property
    def ignore_tc_too_many_errors(self):
        return self.get("safety", "ignore_tc_too_many_errors", default=False)

    @property
    def temp_scale(self):
        return self.get("display", "temp_scale", default="c")

    @property
    def time_scale_slope(self):
        return self.get("display", "time_scale_slope", default="h")

    @property
    def time_scale_profile(self):
        return self.get("display", "time_scale_profile", default="m")

    @property
    def kwh_rate(self):
        return self.get("display", "kwh_rate", default=0.25)

    @property
    def currency_type(self):
        return self.get("display", "currency_type", default="\u20ac")

    @property
    def automatic_restarts(self):
        return self.get("restart", "automatic_restarts", default=True)

    @property
    def automatic_restart_window(self):
        return self.get("restart", "automatic_restart_window", default=15)

    @property
    def seek_start(self):
        return self.get("restart", "seek_start", default=True)

    @property
    def storage_dir(self):
        d = self.get("paths", "storage_dir", default="storage")
        return d if os.path.isabs(d) else os.path.join(self._base_dir, d)

    @property
    def profiles_dir(self):
        d = self.get("paths", "profiles_dir", default="storage/profiles")
        return d if os.path.isabs(d) else os.path.join(self._base_dir, d)

    @property
    def state_file(self):
        d = self.get("paths", "state_file", default="state.json")
        return d if os.path.isabs(d) else os.path.join(self._base_dir, d)

    @property
    def log_file(self):
        d = self.get("paths", "log_file", default="kiln.log")
        return d if os.path.isabs(d) else os.path.join(self._base_dir, d)

    @property
    def alerting_enabled(self):
        return self.get("alerting", "enabled", default=False)

    @property
    def email_enabled(self):
        return self.get("alerting", "email_enabled", default=False)

    @property
    def email_smtp_server(self):
        return self.get("alerting", "email_smtp_server", default="smtp.gmail.com")

    @property
    def email_smtp_port(self):
        return self.get("alerting", "email_smtp_port", default=587)

    @property
    def email_username(self):
        return self.get("alerting", "email_username", default="")

    @property
    def email_password(self):
        return self.get("alerting", "email_password", default="")

    @property
    def email_from(self):
        return self.get("alerting", "email_from", default="")

    @property
    def email_to(self):
        return self.get("alerting", "email_to", default=[])

    @property
    def sms_enabled(self):
        return self.get("alerting", "sms_enabled", default=False)

    @property
    def sms_provider(self):
        return self.get("alerting", "sms_provider", default="twilio")

    @property
    def sms_account_sid(self):
        return self.get("alerting", "sms_account_sid", default="")

    @property
    def sms_auth_token(self):
        return self.get("alerting", "sms_auth_token", default="")

    @property
    def sms_from(self):
        return self.get("alerting", "sms_from", default="")

    @property
    def sms_to(self):
        return self.get("alerting", "sms_to", default=[])

    @property
    def host(self):
        return self.get("server", "host", default="0.0.0.0")

    @property
    def port(self):
        return self.get("server", "port", default=8080)


config = Config()
