# Pi Deployment & Watchdog Setup

## Deploying code updates

The Pi checkout at `~/kiln-controller` is not a git clone; copy changed
files across and restart the service:

```sh
scp kiln-controller/{kiln-controller.py,config.py} oven@192.168.178.35:~/kiln-controller/
scp kiln-controller/lib/{oven.py,ovenWatcher.py,sessionlog.py} oven@192.168.178.35:~/kiln-controller/lib/
ssh oven@192.168.178.35 'sudo systemctl restart kiln-controller'
```

Only restart when no firing is running.

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

See `kiln-controller.service` in this directory. It matches the unit
already installed on the Pi, plus a `KillMode=control-group` hardening
line (harmless if not re-copied, but recommended).
