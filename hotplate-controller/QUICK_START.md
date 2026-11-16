# Quick Start Guide

## Installation

### 1. Prepare Raspberry Pi

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y python3 python3-pip python3-venv python3-dev libgpiod-dev git
```

### 2. Clone or Copy Project

```bash
# If using git
git clone <repository-url>
cd hotplate-controller

# Or copy files to /home/pi/hotplate-controller
```

### 3. Run Installation Script

```bash
cd /home/pi/hotplate-controller
bash scripts/install.sh
```

### 4. Reboot (Required for SPI)

```bash
sudo reboot
```

### 5. Start Service

After reboot:

```bash
sudo systemctl start hotplate-controller
sudo systemctl status hotplate-controller
```

## Manual Installation (Alternative)

```bash
cd /home/pi/hotplate-controller

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Enable SPI
sudo raspi-config nonint do_spi 0

# Test run
python3 hotplate-controller.py
```

## Configuration

Edit `config.json` after first run, or use API to configure.

### Hardware Configuration

Default GPIO pins:
- SSR Control: GPIO 18
- Safety Relay: GPIO 23
- Lid Switch: GPIO 24

Edit `config.json`:
```json
{
  "hardware": {
    "pin_ssr": 18,
    "pin_safety_relay": 23,
    "pin_lid_switch": 24
  }
}
```

### Temperature Sensor

Default: MAX31856 with Type K thermocouple

Edit `config.json`:
```json
{
  "hardware": {
    "sensor_type": "MAX31856",
    "thermocouple_type": "K"
  }
}
```

### PID Tuning

Default: Kp=3.0, Ki=75.0, Kd=12.0

Edit `config.json`:
```json
{
  "pid": {
    "kp": 3.0,
    "ki": 75.0,
    "kd": 12.0
  }
}
```

### EMI Mitigation

Default: 90% max on-time, 0.5s settle time

Edit `config.json`:
```json
{
  "pid": {
    "max_ssr_on_percentage": 90.0,
    "temp_settle_time": 0.5
  }
}
```

## Testing

### Run API Tests

```bash
cd /home/pi/hotplate-controller
source venv/bin/activate
python3 scripts/test_api.py
```

Test with custom host/port:

```bash
python3 scripts/test_api.py 192.168.1.100 8080
```

### Manual Testing

```bash
# Check connection
curl http://localhost:8080/api/stats

# Get configuration
curl http://localhost:8080/api/config

# Stop (if running)
curl -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{"cmd":"stop"}'
```

## Creating Profiles

### Method 1: Via WebSocket (Recommended)

Use the iOS app or a WebSocket client to save profiles.

### Method 2: Manual JSON File

Create a JSON file in `storage/profiles/`:

```json
{
  "type": "profile",
  "name": "My_Profile",
  "temp_units": "c",
  "data": [
    [0, 25],
    [3600, 100],
    [7200, 200],
    [10800, 300],
    [14400, 300],
    [18000, 25]
  ]
}
```

Data format: `[time_seconds, temperature]`

## Service Management

### Start/Stop/Restart

```bash
sudo systemctl start hotplate-controller
sudo systemctl stop hotplate-controller
sudo systemctl restart hotplate-controller
```

### Enable at Boot

```bash
sudo systemctl enable hotplate-controller
```

### View Logs

```bash
# Live logs
sudo journalctl -u hotplate-controller -f

# Last 100 lines
sudo journalctl -u hotplate-controller -n 100

# Since boot
sudo journalctl -u hotplate-controller --since boot
```

### Service Status

```bash
sudo systemctl status hotplate-controller
```

## Network Configuration

### Static IP (Recommended)

Edit `/etc/dhcpcd.conf`:

```
interface eth0
static ip_address=192.168.178.120/24
static routers=192.168.178.1
static domain_name_servers=192.168.178.1
```

### Firewall

```bash
# Install ufw
sudo apt install -y ufw

# Allow SSH
sudo ufw allow ssh

# Allow hotplate controller
sudo ufw allow 8080/tcp

# Enable firewall
sudo ufw enable
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs
sudo journalctl -u hotplate-controller -n 50

# Check if port is in use
sudo netstat -tlnp | grep 8080

# Try manual start
cd /home/pi/hotplate-controller
source venv/bin/activate
python3 hotplate-controller.py
```

### Temperature Reading Errors

```bash
# Check SPI is enabled
ls /dev/spidev*

# Should show /dev/spidev0.0 and /dev/spidev0.1

# Test sensor manually
python3 -c "
from lib.tempSensor import TempSensor
sensor = TempSensor()
sensor.start()
import time
time.sleep(1)
print(f'Temperature: {sensor.get_temperature()}°')
sensor.stop()
"
```

### GPIO Issues

```bash
# Check GPIO pins
gpio readall

# Check for conflicts
sudo raspi-config nonint get_spi
sudo raspi-config nonint get_i2c
```

### Permission Issues

```bash
# Ensure pi user owns the directory
sudo chown -R pi:pi /home/pi/hotplate-controller

# Check file permissions
ls -la /home/pi/hotplate-controller
```

### Network Issues

```bash
# Check IP address
ip addr show

# Test connectivity
ping 8.8.8.8

# Check if service is listening
sudo netstat -tlnp | grep 8080
```

## Safety Checks

Before first firing:

1. **Verify wiring:**
   - SSR connected to correct GPIO
   - Safety relay wired correctly
   - Lid switch normally closed

2. **Test lid switch:**
   ```bash
   # Open lid, check GPIO state
   gpio read 24
   ```

3. **Test SSR control:**
   ```bash
   # Manual SSR test
   python3 -c "
   import RPi.GPIO as GPIO
   GPIO.setmode(GPIO.BCM)
   GPIO.setup(18, GPIO.OUT)
   GPIO.output(18, GPIO.HIGH)  # ON
   GPIO.output(18, GPIO.LOW)   # OFF
   GPIO.cleanup()
   "
   ```

4. **Test temperature reading:**
   ```bash
   # Should return room temperature
   python3 -c "
   from lib.tempSensor import TempSensor
   sensor = TempSensor()
   sensor.start()
   import time
   time.sleep(1)
   print(f'Temp: {sensor.get_temperature()}°C')
   sensor.stop()
   "
   ```

5. **Test emergency shutdown:**
   ```bash
   # Set low temp limit
   # Edit config.json: emergency_shutoff_temp = 100
   # Start firing and watch for shutdown
   ```

## First Firing

1. **Create test profile:**
   - Low max temperature (200-300°C)
   - Short duration (30-60 minutes)

2. **Monitor closely:**
   - Watch temperature readings
   - Verify SSR switching
   - Check heat rate

3. **Verify safety features:**
   - Test lid opening (should stop firing)
   - Monitor temperature limits

4. **Log review:**
   ```bash
   sudo journalctl -u hotplate-controller --since "1 hour ago"
   ```

## Getting Help

### Check Logs First

```bash
sudo journalctl -u hotplate-controller -f
```

### Enable Debug Logging

Edit `hotplate-controller.py` to add more print statements.

### Community Support

- Check issue tracker
- Review documentation
- Search for similar problems

## Next Steps

1. Configure iOS app with server IP
2. Test remote connection
3. Create firing profiles
4. Perform test firing
5. Monitor and tune PID
6. Set up alerting (optional)

## Maintenance

### Regular Tasks

- Check logs weekly
- Update software monthly
- Backup profiles
- Inspect hardware connections

### Software Updates

```bash
cd /home/pi/hotplate-controller
git pull  # or copy new files
source venv/bin/activate
pip install -r requirements.txt
sudo systemctl restart hotplate-controller
```

### Profile Backup

```bash
cd /home/pi/hotplate-controller
tar -czf profiles-backup-$(date +%Y%m%d).tar.gz storage/profiles/
```

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `sudo systemctl start hotplate-controller` | Start service |
| `sudo systemctl stop hotplate-controller` | Stop service |
| `sudo systemctl restart hotplate-controller` | Restart service |
| `sudo systemctl status hotplate-controller` | Check status |
| `sudo journalctl -u hotplate-controller -f` | View logs |
| `python3 scripts/test_api.py` | Test API |
| `http://<ip>:8080/api/stats` | Health check |
| `http://<ip>:8080/api/config` | Get config |

## Default Ports

- HTTP API: 8080
- WebSocket: 8080 (same port)

## Default Credentials

None (no authentication by default). Consider adding authentication for production use.