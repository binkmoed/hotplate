import threading
import time
import os
import json
from config import config


class PID:
    def __init__(self, kp, ki, kd):
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.reset()

    def reset(self):
        self.iterm = 0.0
        self.last_err = 0.0
        self.last_time = None
        self.pidstats = {}

    def compute(self, setpoint, input_val):
        now = time.time()

        if self.last_time is None:
            # First compute: initialise state, return a conservative
            # output based on the sign of the error so the oven starts
            # heating immediately (avoids a cold first cycle).
            self.last_time = now
            self.last_err = setpoint - input_val
            out = 1.0 if setpoint > input_val else 0.0
            self.pidstats = {
                'time': now,
                'timeDelta': 0.0,
                'setpoint': setpoint,
                'ispoint': input_val,
                'err': self.last_err,
                'errDelta': 0.0,
                'p': self.kp * self.last_err,
                'i': 0.0,
                'd': 0.0,
                'kp': self.kp,
                'ki': self.ki,
                'kd': self.kd,
                'pid': self.kp * self.last_err,
                'out': out,
            }
            return out

        dt = now - self.last_time
        if dt <= 0:
            dt = 0.001  # guard against zero-division

        err = setpoint - input_val
        err_delta = err - self.last_err

        p = self.kp * err

        # Anti-windup (conditional integration): only let the integrator
        # accumulate when doing so can actually change the output. If the
        # unsaturated output is already beyond a limit and the error pushes
        # further into that limit, freeze the integrator instead of winding
        # up. Without this, a long ramp saturates the i-term at +100 for the
        # whole climb and causes severe overshoot on low-mass loads
        # (hotplates) once the target is reached.
        unsat = p + self.iterm + (self.kd * (err_delta / dt))
        windup = (unsat > 100 and err > 0) or (unsat < 0 and err < 0)
        if not windup:
            self.iterm += self.ki * err * dt
            self.iterm = max(min(self.iterm, 100), -100)

        i = self.iterm

        d = self.kd * (err_delta / dt)

        pid = p + i + d
        pid = max(min(pid, 100), 0.0)  # negative output means no heating

        # Direct mapping: pid 0 -> 0% duty, pid 100 -> 100% duty
        out = pid / 100.0

        self.last_time = now
        self.last_err = err

        self.pidstats = {
            'time': now,
            'timeDelta': dt,
            'setpoint': setpoint,
            'ispoint': input_val,
            'err': err,
            'errDelta': err_delta,
            'p': p,
            'i': i,
            'd': d,
            'kp': self.kp,
            'ki': self.ki,
            'kd': self.kd,
            'pid': pid,
            'out': out,
        }
        return out

    def get_stats(self):
        return self.pidstats.copy() if self.pidstats else {}


class Profile:
    def __init__(self, name, data, temp_units="c"):
        self.name = name
        self.type = "profile"
        self.temp_units = temp_units.lower()
        self.data = sorted(data, key=lambda x: x[0]) if data else []

    def get_target_temperature(self, time_seconds):
        if not self.data:
            return 0.0

        last_time = self.data[-1][0]
        if time_seconds >= last_time:
            return 0.0

        if time_seconds <= self.data[0][0]:
            return self.data[0][1]

        for i in range(len(self.data) - 1):
            current_time, current_temp = self.data[i]
            next_time, next_temp = self.data[i + 1]
            if current_time <= time_seconds <= next_time:
                span = next_time - current_time
                if span <= 0:
                    return current_temp
                ratio = (time_seconds - current_time) / span
                return current_temp + ratio * (next_temp - current_temp)

        return 0.0

    def get_duration(self):
        return self.data[-1][0] if self.data else 0.0

    def get_start_from_temperature(self, current_temp):
        if not self.data:
            return 0.0
        for time_point, temp in self.data:
            if temp >= current_temp:
                return time_point
        return 0.0

    def to_dict(self):
        return {
            'type': self.type,
            'name': self.name,
            'temp_units': self.temp_units,
            'data': self.data,
        }

    @classmethod
    def from_dict(cls, data):
        return cls(
            name=data['name'],
            data=data['data'],
            temp_units=data.get('temp_units', 'c'),
        )


class Oven(threading.Thread):
    STATES = ['IDLE', 'RUNNING', 'PAUSED']

    def __init__(self, temp_sensor, hardware_controller, alert_manager=None):
        super().__init__()
        self.daemon = True
        self.running = False

        self.temp_sensor = temp_sensor
        self.hardware = hardware_controller
        self.alert_manager = alert_manager

        self.pid = PID(config.pid_kp, config.pid_ki, config.pid_kd)

        self.state = 'IDLE'
        self.profile = None
        self.start_time = None
        self.runtime = 0.0
        self.totaltime = 0.0
        self.target_temp = 0.0
        self.current_temp = 0.0

        self.cost = 0.0
        self.heat = 0.0
        self.heat_rate = 0.0
        self.catching_up = False

        self.last_temp_for_heat_rate = None
        self.last_time_for_heat_rate = None

        self.lock = threading.Lock()

    # ------------------------------------------------------------------
    # Thread entry point
    # ------------------------------------------------------------------

    def run(self):
        self.running = True
        while self.running:
            try:
                if self.state == 'RUNNING':
                    self._control_cycle()
                else:
                    # Still read temperature when idle so the dashboard
                    # shows the current kiln temperature (SSR is already
                    # off when idle, so no EMI concern).
                    self.current_temp = self.temp_sensor.get_temperature()
                    time.sleep(config.duty_cycle)
            except Exception as e:
                print(f"Error in oven control loop: {e}")
                # Ensure SSR is off on any unexpected error
                self.hardware.disable_ssr()
                time.sleep(1)

    # ------------------------------------------------------------------
    # Control cycle — one iteration per duty_cycle
    #
    # EMI-safe sequence (per user requirement):
    #   1. Ensure SSR is OFF
    #   2. Wait settle_time for EMI to dissipate
    #   3. Read temperature (retries on fault)
    #   4. Check safety conditions (fresh temp)
    #   5. Check catch-up             (fresh temp)
    #   6. Update runtime / target
    #   7. Compute PID
    #   8. Turn SSR ON for on_time    (lid checked in chunks)
    #   9. Turn SSR OFF
    #  10. Sleep remaining time to fill duty_cycle
    # ------------------------------------------------------------------

    def _control_cycle(self):
        cycle_start = time.time()

        # --- Phase 1-3: EMI-safe temperature read ---
        self.hardware.disable_ssr()
        self.heat = 0.0
        time.sleep(config.temp_settle_time)

        consecutive_failures = getattr(self, '_consecutive_read_failures', 0)
        try:
            current_temp = self.temp_sensor.safe_read()
            consecutive_failures = 0
        except RuntimeError as e:
            print(f"Temperature read failed: {e}")
            # Use last known temperature as fallback
            current_temp = self.current_temp
            consecutive_failures += 1
        self._consecutive_read_failures = consecutive_failures

        with self.lock:
            self.current_temp = current_temp
            self._update_heat_rate()

        # Abort if the sensor has failed repeatedly — heating blind is
        # not safe even if the error-rate check would eventually fire.
        if consecutive_failures >= config.max_consecutive_read_failures:
            print("Aborting: temperature sensor failed repeatedly")
            if self.alert_manager:
                self.alert_manager.alert_thermocouple_error(1.0)
            self.abort_run()
            return

        # --- Phase 4: Safety (with fresh temperature) ---
        with self.lock:
            self.check_safety_conditions()
            if self.state != 'RUNNING':
                return

        # --- Phase 5-6: Catch-up, runtime, target ---
            self.check_catch_up()
            self.update_runtime()
            self.update_target_temperature()

            if self.runtime >= self.totaltime:
                self._complete_firing()
                return

        # --- Phase 7: PID ---
            pid_output = self.pid.compute(self.target_temp, current_temp)

            # Soft landing: when close to the target, cap the duty cycle so
            # thermal momentum can't carry a low-mass load (hotplate) past
            # the setpoint. Disabled when approach_window is 0.
            if config.pid_approach_window > 0 and \
                    abs(self.target_temp - current_temp) <= config.pid_approach_window:
                pid_output = min(pid_output, config.pid_approach_max_output / 100.0)

        # --- Phase 8-9: Apply heating ---
            on_time = self._calc_on_time(pid_output)
            self.update_cost(on_time)

        if on_time > 0:
            energised = self.hardware.enable_ssr(duration=on_time)
            self.heat = 1.0 if energised else 0.0
            if not energised:
                # Lid opened mid-cycle (or interlock tripped): the
                # hardware layer has already cut power and dropped the
                # relay — bring the oven state machine in line now
                # instead of waiting for the next control cycle.
                self.abort_run()
                return
        else:
            self.heat = 0.0

        # --- Phase 10: Sleep remaining duty cycle time ---
        elapsed = time.time() - cycle_start
        sleep_time = config.duty_cycle - elapsed
        if sleep_time > 0:
            time.sleep(sleep_time)

    def _calc_on_time(self, pid_output):
        """Convert PID output (0..1) to SSR on-time in seconds."""
        duty = config.duty_cycle
        max_pct = config.max_ssr_on_percentage / 100.0

        # Reserve settle_time so the *next* cycle can read EMI-safe
        max_available = duty - config.temp_settle_time
        max_by_pct = duty * max_pct
        max_on = min(max_available, max_by_pct, config.max_ssr_on_time)

        if pid_output >= 1.0:
            return max(0, max_on)
        if pid_output <= 0.0:
            return 0.0

        on_time = pid_output * duty
        return min(on_time, max_on)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _update_heat_rate(self):
        now = time.time()
        if self.last_temp_for_heat_rate is not None:
            dt = now - self.last_time_for_heat_rate
            if dt > 0:
                temp_change = self.current_temp - self.last_temp_for_heat_rate
                self.heat_rate = (temp_change / dt) * 3600.0
        self.last_temp_for_heat_rate = self.current_temp
        self.last_time_for_heat_rate = now

    def _complete_firing(self):
        profile_name = self.profile.name if self.profile else "Unknown"
        duration = self.runtime
        cost = self.cost
        self.abort_run()
        if self.alert_manager:
            self.alert_manager.alert_firing_complete(profile_name, duration, cost)
        print(f"Firing complete: {profile_name}, "
              f"Duration: {duration:.1f}s, Cost: {cost:.2f}{config.currency_type}")

    # ------------------------------------------------------------------
    # State transitions
    # ------------------------------------------------------------------

    def run_profile(self, profile, startat=0, allow_seek=True):
        with self.lock:
            self.state = 'RUNNING'
            self.profile = profile
            self.totaltime = profile.get_duration()
            self.start_time = time.time() - startat
            self.runtime = startat
            self.cost = 0.0
            self.catching_up = False
            self.pid.reset()

            if allow_seek and config.seek_start:
                current_temp = self.temp_sensor.get_temperature()
                seek_time = profile.get_start_from_temperature(current_temp)
                if seek_time > 0 and startat == 0:
                    self.start_time = time.time() - seek_time
                    self.runtime = seek_time

            if not self.is_alive():
                self.start()

    def pause(self):
        with self.lock:
            if self.state == 'RUNNING':
                self.state = 'PAUSED'
                self.hardware.disable_ssr()
                self.heat = 0.0

    def resume(self):
        with self.lock:
            if self.state == 'PAUSED':
                self.state = 'RUNNING'
                self.adjust_start_time()

    def stop(self):
        with self.lock:
            self.abort_run()

    def abort_run(self):
        self.state = 'IDLE'
        self.profile = None
        self.start_time = None
        self.runtime = 0.0
        self.totaltime = 0.0
        self.target_temp = 0.0
        self.cost = 0.0
        self.heat = 0.0
        self.heat_rate = 0.0
        self.catching_up = False
        self.pid.reset()
        self.hardware.disable_safety_relay()

    def adjust_start_time(self):
        self.start_time = time.time() - self.runtime

    # ------------------------------------------------------------------
    # Per-cycle checks
    # ------------------------------------------------------------------

    def check_catch_up(self):
        if not self.profile or self.state != 'RUNNING':
            return
        window = config.pid_control_window
        if abs(self.current_temp - self.target_temp) > window:
            self.catching_up = True
            self.adjust_start_time()
        else:
            self.catching_up = False

    def update_runtime(self):
        if self.state == 'RUNNING':
            self.runtime = time.time() - self.start_time

    def update_target_temperature(self):
        if self.profile and self.state == 'RUNNING':
            self.target_temp = self.profile.get_target_temperature(self.runtime)

    def update_cost(self, on_time):
        """Accumulate energy cost from the *actual* planned on-time.

        Called before the SSR is energised (self.heat not yet set),
        so we key off on_time rather than self.heat.  If the SSR is
        cut early (lid opened) the next cycle sees heat=0 and no
        further cost accrues; the small over-report for the final
        partial cycle is acceptable.
        """
        if self.state == 'RUNNING' and on_time > 0:
            cycle_cost = (config.kw_elements * config.kwh_rate * on_time) / 3600.0
            self.cost += cycle_cost

    def check_safety_conditions(self):
        # Lid switch
        if self.hardware.is_lid_open():
            if self.alert_manager:
                self.alert_manager.alert_lid_opened()
            self.abort_run()
            return

        # Over-temperature (convert limit to current display scale)
        temp_limit = config.emergency_shutoff_temp
        if config.emergency_shutoff_temp_scale == 'f' and config.temp_scale == 'c':
            temp_limit = (temp_limit - 32) * 5 / 9
        elif config.emergency_shutoff_temp_scale == 'c' and config.temp_scale == 'f':
            temp_limit = temp_limit * 9 / 5 + 32

        if self.current_temp >= temp_limit and not config.ignore_temp_too_high:
            if self.alert_manager:
                self.alert_manager.alert_temperature_exceeded(
                    self.current_temp, temp_limit
                )
            self.abort_run()
            return

        # Thermocouple error rate
        error_rate = self.temp_sensor.get_error_rate()
        if error_rate > config.max_tc_error_rate and not config.ignore_tc_too_many_errors:
            if self.alert_manager:
                self.alert_manager.alert_thermocouple_error(error_rate)
            self.abort_run()
            return

    # ------------------------------------------------------------------
    # Restart persistence
    # ------------------------------------------------------------------

    def save_automatic_restart_state(self):
        if config.automatic_restarts and self.state == 'RUNNING':
            state_dict = self.get_state()
            state_dict['saved_at'] = time.time()
            try:
                with open(config.state_file, 'w') as f:
                    json.dump(state_dict, f)
            except Exception as e:
                print(f"Error saving state: {e}")

    def get_state(self):
        return {
            'cost': round(self.cost, 2),
            'runtime': round(self.runtime, 1),
            'temperature': round(self.current_temp, 1),
            'target': round(self.target_temp, 1),
            'state': self.state,
            'heat': self.heat,
            'heat_rate': round(self.heat_rate, 1),
            'totaltime': round(self.totaltime, 1),
            'kwh_rate': config.kwh_rate,
            'currency_type': config.currency_type,
            'profile': self.profile.name if self.profile else None,
            'pidstats': self.pid.get_stats(),
            'catching_up': self.catching_up,
        }

    @classmethod
    def load_state(cls):
        if not os.path.exists(config.state_file):
            return None
        try:
            with open(config.state_file, 'r') as f:
                state = json.load(f)
            saved_at = state.get('saved_at', 0)
            window = config.automatic_restart_window * 60
            if time.time() - saved_at > window:
                os.remove(config.state_file)
                return None
            return state
        except Exception as e:
            print(f"Error loading state: {e}")
            return None

    def shutdown(self):
        self.running = False
        self.abort_run()
