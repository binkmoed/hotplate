# Kiln Controller - Python Backend

Bottle + gevent server for kiln temperature control via MAX31855/56 thermocouple.

## Installation

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Usage

```bash
python3 kiln-controller.py
```

## Configuration

Edit `config.py` to customize hardware pins, PID parameters, and settings.

## API Documentation

See `api.md` for full API reference.

## Testing

```bash
python3 scripts/test_api.py
```

## Systemd Service

```bash
sudo cp scripts/kiln-controller.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kiln-controller
sudo systemctl start kiln-controller
```