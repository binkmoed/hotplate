# Pi Deployment & Watchdog Setup

## Deploying code updates

The Pi checkout at `~/hotplate-controller` is not a git clone; copy changed
files across and restart the service:

```sh
scp hotplate-controller/{hotplate-controller.py,config.py} pi@192.168.178.35:~/hotplate-controller/
scp hotplate-controller/lib/{oven.py,ovenWatcher.py,sessionlog.py} pi@192.168.178.35:~/hotplate-controller/lib/
ssh pi@192.168.178.35 'sudo systemctl restart hotplate-controller'
```

Only restart when no firing is running.

## SPI overlay requirement

The MAX31856 driver toggles chip-select as a plain GPIO, but the default
Bookworm SPI overlay claims CE0/CE1 (`Device or resource busy` on sensor
init). `scripts/install.sh` appends `dtoverlay=spi0-0cs` to
`/boot/firmware/config.txt`; on an existing Pi you can add it by hand —
reboot required. Symptom if missing: no temperature readings.


## Hardware watchdog (recommended, one-time)

If the controller process is SIGKILLed in the seconds the SSR pin is
HIGH, the elements could stay energised. Software cannot fix that; the
Pi's BCM hardware watchdog reboots the whole board instead. On restart,
GPIO init drives the SSR and safety-relay pins LOW and systemd revives
the controller (`Restart=always`).

Enable:

```sh
sudo sed -i 's/^#\?RuntimeWatchdogSec=.*/RuntimeWatchdogSec=15/' /etc/systemd/system.conf
grep -q RuntimeWatchdogSec /etc/systemd/system.conf || \
  echo 'RuntimeWatchdogSec=15' | sudo tee -a /etc/systemd/system.conf
sudo reboot   # takes effect at boot
```

Verify after reboot: `journalctl -b -u systemd | grep -i watchdog`
(should show "Hardware watchdog 'Broadcom BCM2835 Watchdog timer'").

## Service unit

See `hotplate-controller.service` in this directory. It matches the unit
already installed on the Pi, plus a `KillMode=control-group` hardening
line (harmless if not re-copied, but recommended).

## In-app server restart

`POST /api/system/restart` restarts the service via
`sudo -n systemctl restart hotplate-controller`. Allow it on the Pi:

```sh
echo 'hotplate ALL=(root) NOPASSWD: /usr/bin/systemctl restart hotplate-controller' | \
  sudo tee /etc/sudoers.d/hotplate-restart
sudo chmod 440 /etc/sudoers.d/hotplate-restart
```

(The install script adds this automatically.)
Without this rule the endpoint returns an error and nothing happens.
