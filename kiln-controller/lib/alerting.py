import smtplib
import time
import threading
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from config import config


class AlertManager:
    """Send email / SMS alerts asynchronously so the control loop is never blocked."""

    def __init__(self):
        self.enabled = config.alerting_enabled
        self.email_enabled = config.email_enabled
        self.sms_enabled = config.sms_enabled

    def send_alert(self, event_type, message, severity="info"):
        if not self.enabled:
            return
        print(f"[ALERT] {event_type}: {message}")
        # Dispatch in a background thread — SMTP calls are slow
        threading.Thread(
            target=self._dispatch,
            args=(event_type, message, severity),
            daemon=True,
        ).start()

    def _dispatch(self, event_type, message, severity):
        if self.email_enabled:
            self.send_email_alert(event_type, message, severity)
        if self.sms_enabled:
            self.send_sms_alert(event_type, message, severity)

    # ------------------------------------------------------------------
    # Email
    # ------------------------------------------------------------------

    def send_email_alert(self, event_type, message, severity):
        try:
            msg = MIMEMultipart()
            msg['From'] = config.email_from
            msg['To'] = ', '.join(config.email_to)
            msg['Subject'] = f"[Kiln Alert] {event_type} - {severity.upper()}"

            body = (
                f"Kiln Controller Alert\n\n"
                f"Event: {event_type}\n"
                f"Severity: {severity.upper()}\n"
                f"Message: {message}\n"
                f"Time: {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n"
                f"This is an automated message from your kiln controller."
            )
            msg.attach(MIMEText(body, 'plain'))

            server = smtplib.SMTP(config.email_smtp_server, config.email_smtp_port)
            server.starttls()
            server.login(config.email_username, config.email_password)
            server.sendmail(config.email_from, config.email_to, msg.as_string())
            server.quit()
            print(f"Email alert sent: {event_type}")
        except Exception as e:
            print(f"Failed to send email alert: {e}")

    # ------------------------------------------------------------------
    # SMS
    # ------------------------------------------------------------------

    def send_sms_alert(self, event_type, message, severity):
        try:
            if config.sms_provider.lower() == 'twilio':
                self._send_twilio_sms(event_type, message)
            else:
                print(f"SMS provider '{config.sms_provider}' not implemented")
        except Exception as e:
            print(f"Failed to send SMS alert: {e}")

    def _send_twilio_sms(self, event_type, message):
        try:
            from twilio.rest import Client
        except ImportError:
            print("Twilio library not installed. Install with: pip install twilio")
            return

        try:
            client = Client(config.sms_account_sid, config.sms_auth_token)
            sms_body = f"[Kiln] {event_type}: {message}"
            for phone in config.sms_to:
                client.messages.create(
                    body=sms_body,
                    from_=config.sms_from,
                    to=phone,
                )
            print(f"SMS alert sent via Twilio: {event_type}")
        except Exception as e:
            print(f"Failed to send Twilio SMS: {e}")

    # ------------------------------------------------------------------
    # Convenience helpers
    # ------------------------------------------------------------------

    def alert_temperature_exceeded(self, current_temp, limit_temp):
        self.send_alert(
            "TEMP_EXCEEDED",
            f"Temperature exceeded safety limit! "
            f"Current: {current_temp}\u00b0{config.temp_scale.upper()}, "
            f"Limit: {limit_temp}\u00b0{config.temp_scale.upper()}",
            "critical",
        )

    def alert_thermocouple_error(self, error_rate):
        self.send_alert(
            "THERMOCOUPLE_ERROR",
            f"Thermocouple error rate too high: {error_rate:.1%}",
            "warning",
        )

    def alert_lid_opened(self):
        self.send_alert("LID_OPENED", "Kiln lid opened during firing", "warning")

    def alert_firing_complete(self, profile_name, duration, cost):
        self.send_alert(
            "FIRING_COMPLETE",
            f"Firing complete. Profile: {profile_name}, "
            f"Duration: {duration:.1f}s, Cost: {cost:.2f}{config.currency_type}",
            "info",
        )

    def alert_emergency_shutdown(self, reason):
        self.send_alert(
            "EMERGENCY_SHUTDOWN",
            f"Emergency shutdown triggered: {reason}",
            "critical",
        )

    def alert_connection_lost(self):
        self.send_alert("CONNECTION_LOST", "Lost connection to kiln controller", "warning")

    def alert_profile_error(self, profile_name, error):
        self.send_alert(
            "PROFILE_ERROR",
            f"Error running profile '{profile_name}': {error}",
            "error",
        )

    def reload_config(self):
        config.load()
        self.enabled = config.alerting_enabled
        self.email_enabled = config.email_enabled
        self.sms_enabled = config.sms_enabled
        print("Alert configuration reloaded")
