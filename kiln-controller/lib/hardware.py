import time
from config import config

# GPIO import — fall back to a stub on non-Pi platforms so the module
# can still be imported during development / unit tests.
try:
    import RPi.GPIO as GPIO
    _HAS_GPIO = True
except (ImportError, RuntimeError):
    _HAS_GPIO = False
    print("WARNING: RPi.GPIO not available — running in stub mode "
          "(no real hardware control).")


class HardwareController:
    """Low-level GPIO control for SSR, safety relay, and lid switch."""

    # Maximum time between lid-switch checks while the SSR is energised
    # (seconds).  Keeps safety response time bounded.
    LID_CHECK_INTERVAL = 0.5

    def __init__(self):
        self.pin_ssr = config.pin_ssr
        self.pin_safety_relay = config.pin_safety_relay
        self.pin_lid_switch = config.pin_lid_switch

        self.ssr_on = False
        self.safety_relay_on = False
        self.lid_open = False
        self._emergency_fired = False

        if _HAS_GPIO:
            GPIO.setmode(GPIO.BCM)
            GPIO.setwarnings(False)
            GPIO.setup(self.pin_ssr, GPIO.OUT)
            GPIO.setup(self.pin_safety_relay, GPIO.OUT)
            GPIO.setup(self.pin_lid_switch, GPIO.IN,
                       pull_up_down=GPIO.PUD_UP)
            GPIO.output(self.pin_ssr, GPIO.LOW)
            GPIO.output(self.pin_safety_relay, GPIO.LOW)

        self.update_lid_state()

    # ------------------------------------------------------------------
    # Lid switch
    # ------------------------------------------------------------------

    def update_lid_state(self):
        """Read the lid switch GPIO pin. Returns True if lid is open."""
        if _HAS_GPIO:
            self.lid_open = GPIO.input(self.pin_lid_switch) == GPIO.LOW
        else:
            self.lid_open = False
        return self.lid_open

    def is_lid_open(self):
        return self.update_lid_state()

    # ------------------------------------------------------------------
    # Safety relay
    # ------------------------------------------------------------------

    def enable_safety_relay(self):
        if self.lid_open:
            print("Cannot enable safety relay: lid is open")
            return False
        if _HAS_GPIO:
            GPIO.output(self.pin_safety_relay, GPIO.HIGH)
        self.safety_relay_on = True
        self._emergency_fired = False
        return True

    def disable_safety_relay(self):
        if _HAS_GPIO:
            GPIO.output(self.pin_ssr, GPIO.LOW)
            GPIO.output(self.pin_safety_relay, GPIO.LOW)
        self.ssr_on = False
        self.safety_relay_on = False

    # ------------------------------------------------------------------
    # SSR
    # ------------------------------------------------------------------

    def enable_ssr(self, duration=None):
        """
        Energise the SSR.

        If *duration* is given the method blocks until the requested
        on-time expires, checking the lid switch every LID_CHECK_INTERVAL
        seconds.  If the lid opens mid-cycle the SSR is cut immediately
        and the method returns False.
        """
        if not self.safety_relay_on:
            print("Cannot enable SSR: safety relay is off")
            return False
        if self.lid_open:
            print("Cannot enable SSR: lid is open")
            return False

        # Energise
        if _HAS_GPIO:
            GPIO.output(self.pin_ssr, GPIO.HIGH)
        self.ssr_on = True

        # Timed operation with safety polling
        if duration is not None and duration > 0:
            elapsed = 0.0
            while elapsed < duration:
                chunk = min(self.LID_CHECK_INTERVAL, duration - elapsed)
                time.sleep(chunk)
                elapsed += chunk
                if self.is_lid_open():
                    self.disable_ssr()
                    self._trigger_emergency("Lid opened during heating")
                    return False
            # Turn off after the requested on-time
            self.disable_ssr()
        return True

    def disable_ssr(self):
        if _HAS_GPIO:
            GPIO.output(self.pin_ssr, GPIO.LOW)
        self.ssr_on = False

    # ------------------------------------------------------------------
    # Emergency
    # ------------------------------------------------------------------

    def _trigger_emergency(self, reason):
        """Fire once per incident (avoids duplicate alerts)."""
        if self._emergency_fired:
            return
        self._emergency_fired = True
        print(f"EMERGENCY: {reason}")
        self.disable_ssr()
        self.disable_safety_relay()

    def emergency_shutdown(self, reason="Emergency"):
        self._trigger_emergency(reason)

    # ------------------------------------------------------------------
    # Cleanup
    # ------------------------------------------------------------------

    def cleanup(self):
        self.disable_ssr()
        self.disable_safety_relay()
        if _HAS_GPIO:
            GPIO.cleanup()
        print("Hardware cleaned up")
