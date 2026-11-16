#!/bin/bash

set -e

echo "=========================================="
echo "Hotplate Controller Installation Script"
echo "=========================================="
echo ""

INSTALL_DIR="/home/pi/hotplate-controller"
VENV_DIR="$INSTALL_DIR/venv"

echo "1. Checking system..."
if [ "$(id -u)" -eq 0 ]; then
    echo "ERROR: Do not run as root. Run as 'pi' user."
    exit 1
fi

echo "2. Updating system..."
sudo apt update
sudo apt upgrade -y

echo "3. Installing dependencies..."
sudo apt install -y python3 python3-pip python3-venv python3-dev libgpiod-dev git

echo "3b. Enabling SPI without claiming the CE pins..."
sudo raspi-config nonint do_spi 0
# The Adafruit MAX31856 driver toggles chip-select as a plain GPIO; the default
# SPI overlay claims CE0/CE1 and makes that fail with 'Device or resource busy'.
if ! grep -q '^dtoverlay=spi0-0cs' /boot/firmware/config.txt 2>/dev/null; then
    echo 'dtoverlay=spi0-0cs' | sudo tee -a /boot/firmware/config.txt > /dev/null
fi
sudo mkdir -p /etc/sudoers.d
if [ ! -f /etc/sudoers.d/hotplate-restart ]; then
    echo "$USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart hotplate-controller" | sudo tee /etc/sudoers.d/hotplate-restart > /dev/null
    sudo chmod 440 /etc/sudoers.d/hotplate-restart
fi

echo "5. Creating installation directory..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/storage/profiles"
mkdir -p "$INSTALL_DIR/public"
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/scripts"

echo "6. Creating virtual environment..."
cd "$INSTALL_DIR"
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "7. Installing Python packages..."
pip install --upgrade pip
pip install -r requirements.txt

echo "8. Installing systemd service..."
sudo cp scripts/hotplate-controller.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable hotplate-controller.service

echo ""
echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Reboot to enable SPI: sudo reboot"
echo "2. After reboot, start service: sudo systemctl start hotplate-controller"
echo "3. Check status: sudo systemctl status hotplate-controller"
echo "4. View logs: sudo journalctl -u hotplate-controller -f"
echo ""
echo "Test the API:"
echo "  python3 scripts/test_api.py"
echo ""