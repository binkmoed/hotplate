# Temperature Sensor Configuration Guide

## Overview

The kiln controller supports two thermocouple amplifier boards:

1. **MAX31855** - Type K thermocouples only
2. **MAX31856** - Supports multiple thermocouple types (B, E, J, K, N, R, S, T)

## MAX31855

### Supported Thermocouple Types
- **Type K only** (most common for ceramic kilns)

### Temperature Range
- Type K: -270°C to +1372°C (-454°F to +2502°F)

### Features
- Low cost
- Simple interface
- Type K only (hardware limitation)
- Cold junction compensation
- Open circuit detection

### When to Use
- Standard ceramic firing (Type K thermocouple is sufficient)
- Cost-sensitive applications
- Simple installations

### Configuration
```json
{
  "hardware": {
    "sensor_type": "MAX31855",
    "thermocouple_type_max31855": "K"
  }
}
```

**Note:** The `thermocouple_type_max31855` must be "K". Any other value will be ignored with a warning.

## MAX31856

### Supported Thermocouple Types
- **Type B** - 0°C to 1820°C (32°F to 3308°F)
- **Type E** - -270°C to +1000°C (-454°F to +1832°F)
- **Type J** - -210°C to +1200°C (-346°F to +2192°F)
- **Type K** - -270°C to +1372°C (-454°F to +2502°F)
- **Type N** - -270°C to +1300°C (-454°F to +2372°F)
- **Type R** - -50°C to +1768°C (-58°F to +3214°F)
- **Type S** - -50°C to +1768°C (-58°F to +3214°F)
- **Type T** - -270°C to +400°C (-454°F to +752°F)

### Features
- Multiple thermocouple type support
- Higher accuracy
- Cold junction compensation
- Open circuit detection
- Short circuit detection
- Adjustable temperature thresholds
- Better EMI rejection

### When to Use
- High-temperature firing (Type B, R, S)
- Specialty applications requiring specific thermocouple types
- Need for better accuracy
- High-EMI environments

### Configuration
```json
{
  "hardware": {
    "sensor_type": "MAX31856",
    "thermocouple_type_max31856": "K"
  }
}
```

Replace `"K"` with your thermocouple type: `"B"`, `"E"`, `"J"`, `"K"`, `"N"`, `"R"`, `"S"`, or `"T"`.

## Thermocouple Type Selection Guide

### Type K (Most Common)
**Applications:**
- General ceramic firing
- Glass fusing
- Enameling
- Raku firing
- Most hobby kiln applications

**Temperature Range:** -270°C to +1372°C (-454°F to +2502°F)

**Pros:**
- Widely available
- Inexpensive
- Good accuracy (±2°C)
- Standard in the ceramics industry

**Cons:**
- Limited to ~1300°C continuous use
- Degrades over time at high temperatures

**Recommended for:** Bisque, glaze, and most standard ceramic firings up to cone 10 (~1300°C)

### Type B
**Applications:**
- High-temperature ceramics
- Industrial kilns
- Porcelain firing
- High-fire stoneware

**Temperature Range:** 0°C to 1820°C (32°F to 3308°F)

**Pros:**
- Highest temperature capability
- Good stability at high temps
- Low drift

**Cons:**
- Expensive
- Lower sensitivity at low temps
- Requires specialized instrumentation

**Recommended for:** Cone 12+ firings (1372°C to 1820°C)

### Type R and S (Platinum-Based)
**Applications:**
- High-precision applications
- Industrial processes
- Laboratory use
- High-temperature ceramics

**Temperature Range:** -50°C to +1768°C (-58°F to +3214°F)

**Pros:**
- High accuracy (±1°C)
- Excellent stability
- Long lifespan

**Cons:**
- Very expensive
- Fragile
- Platinum cost volatility

**Recommended for:** Precision applications and industrial use where cost is not a concern

### Type J (Iron-Constantan)
**Applications:**
- Lower-temperature applications
- Plastic molding
- Food industry
- HVAC

**Temperature Range:** -210°C to +1200°C (-346°F to +2192°F)

**Pros:**
- Good sensitivity
- Moderate cost
- Accurate in low-mid range

**Cons:**
- Iron oxidizes at high temperatures
- Not ideal for kiln applications
- Limited to ~800°C continuous

**Not recommended for:** Ceramic kilns (oxidizes at firing temperatures)

### Type N (Nicrosil-Nisil)
**Applications:**
- High-temperature stability
- Industrial processes
- Alternative to Type K

**Temperature Range:** -270°C to +1300°C (-454°F to +2372°F)

**Pros:**
- Better high-temp stability than Type K
- Less drift
- Good oxidation resistance

**Cons:**
- Less common
- Higher cost than Type K
- Limited availability

**Recommended for:** Alternative to Type K for high-temp applications

### Type E (Chromel-Constantan)
**Applications:**
- Low-temperature applications
- Cryogenics
- Precise low-temp work

**Temperature Range:** -270°C to +1000°C (-454°F to +1832°F)

**Pros:**
- Highest sensitivity (68 µV/°C)
- Good low-temp accuracy

**Cons:**
- Limited to ~800°C continuous
- Not suitable for kiln applications

**Not recommended for:** Ceramic kilns (temperature too high)

### Type T (Copper-Constantan)
**Applications:**
- Low-temperature applications
- Food industry
- Cryogenics
- HVAC

**Temperature Range:** -270°C to +400°C (-454°F to +752°F)

**Pros:**
- Excellent low-temp accuracy
- Stable
- Good for moist environments

**Cons:**
- Too low for kiln applications
- Copper oxidizes

**Not recommended for:** Ceramic kilns (temperature too low)

## Sensor Comparison

| Feature | MAX31855 | MAX31856 |
|---------|----------|----------|
| Thermocouple Types | K only | B, E, J, K, N, R, S, T |
| Temperature Range | -270 to 1372°C | Depends on thermocouple |
| Accuracy | ±2°C | ±0.25°C (Type K) |
| Cold Junction Compensation | Yes | Yes |
| Open Circuit Detection | Yes | Yes |
| Short Circuit Detection | No | Yes |
| Cost | Low | Moderate |
| Interface | SPI | SPI |
| Recommended for | Standard kilns | All applications |
| Power Consumption | Low | Low |

## Configuration Examples

### Standard Ceramic Kiln (MAX31855, Type K)
```json
{
  "hardware": {
    "sensor_type": "MAX31855",
    "thermocouple_type_max31855": "K"
  }
}
```

### High-Temperature Kiln (MAX31856, Type B)
```json
{
  "hardware": {
    "sensor_type": "MAX31856",
    "thermocouple_type_max31856": "B"
  }
}
```

### Precision Industrial (MAX31856, Type S)
```json
{
  "hardware": {
    "sensor_type": "MAX31856",
    "thermocouple_type_max31856": "S"
  }
}
```

### Alternative to Type K (MAX31856, Type N)
```json
{
  "hardware": {
    "sensor_type": "MAX31856",
    "thermocouple_type_max31856": "N"
  }
}
```

## Updating Configuration via API

### Get Current Configuration
```bash
curl http://<ip>:8080/api/config | jq .hardware
```

### Update Sensor Type
```bash
curl -X POST http://<ip>:8080/api/config \
  -H "Content-Type: application/json" \
  -d '{
    "hardware.sensor_type": "MAX31856",
    "hardware.thermocouple_type_max31856": "K"
  }'
```

**Response:**
```json
{
  "success": true,
  "restart_required": true,
  "warnings": [],
  "message": "Configuration updated. Restart required for hardware changes."
}
```

### Update Thermocouple Type Only
```bash
curl -X POST http://<ip>:8080/api/config \
  -H "Content-Type: application/json" \
  -d '{
    "hardware.thermocouple_type_max31856": "B"
  }'
```

## Validation

The controller validates thermocouple type compatibility:

### MAX31855 Validation
- Only accepts "K"
- Any other type returns an error:
```json
{
  "success": false,
  "error": "Invalid thermocouple type 'J' for MAX31855. Only Type K is supported."
}
```

### MAX31856 Validation
- Accepts: B, E, J, K, N, R, S, T
- Invalid types return an error:
```json
{
  "success": false,
  "error": "Invalid thermocouple type 'X' for MAX31856. Supported: B, E, J, K, N, R, S, T"
}
```

## Switching Between Sensors

To switch from MAX31855 to MAX31856:

1. Update configuration:
```bash
curl -X POST http://<ip>:8080/api/config \
  -H "Content-Type: application/json" \
  -d '{
    "hardware.sensor_type": "MAX31856",
    "hardware.thermocouple_type_max31856": "K"
  }'
```

2. Stop the controller:
```bash
sudo systemctl stop kiln-controller
```

3. Replace the sensor hardware if needed

4. Restart the controller:
```bash
sudo systemctl start kiln-controller
```

5. Verify the sensor is working:
```bash
curl http://<ip>:8080/api/stats
```

## Troubleshooting

### Sensor Not Detected

**Symptom:** "Failed to initialize temperature sensor" in logs

**Check:**
```bash
ls /dev/spidev*
```

**Solution:** Enable SPI:
```bash
sudo raspi-config nonint do_spi 0
sudo reboot
```

### Invalid Thermocouple Type

**Symptom:** Configuration update fails

**Check:** Verify the thermocouple type matches your sensor:
- MAX31855: Must be "K"
- MAX31856: Can be B, E, J, K, N, R, S, or T

### Temperature Readings Incorrect

**Symptom:** Temperature way off from expected

**Check:**
1. Verify thermocouple type matches the actual thermocouple
2. Check thermocouple polarity (yellow +, red -)
3. Verify good electrical connections
4. Check for EMI sources

**Test:**
```bash
python3 -c "
from lib.tempSensor import TempSensor
import time
sensor = TempSensor()
sensor.start()
time.sleep(1)
print(f'Temperature: {sensor.get_temperature()}°C')
sensor.stop()
"
```

### Faults Detected

**Symptom:** "Sensor fault detected" in logs

**Check:**
1. Thermocouple disconnected
2. Short circuit
3. Open circuit
4. Invalid thermocouple type

**Solution:** Check connections and verify thermocouple type matches hardware.

## Wiring

### MAX31855/56 to Raspberry Pi

```
MAX31855/56        Raspberry Pi
-----------        ------------
VCC        →       3.3V
GND        →       GND
DO         →       MISO (GPIO 9)
DI         →       MOSI (GPIO 10)
CS         →       CE0 (GPIO 8)
CLK        →       SCLK (GPIO 11)
```

### Thermocouple Connection

```
MAX31855/56        Thermocouple
-----------        -------------
T+         →       Yellow (+)
T-         →       Red (-)
```

**Important:** Thermocouple polarity must be correct. Reversed thermocouple will read incorrectly (often very low temperatures).

## Recommendations

### For Hobby/Small Studio Kilns
- **Sensor:** MAX31855
- **Thermocouple:** Type K
- **Reason:** Cost-effective, Type K is standard for ceramics

### For Production/Industrial Kilns
- **Sensor:** MAX31856
- **Thermocouple:** Type K or Type N
- **Reason:** Better accuracy, more features, Type N offers better high-temp stability

### For High-Temperature Applications (>1300°C)
- **Sensor:** MAX31856
- **Thermocouple:** Type B, R, or S
- **Reason:** Type K limited to ~1300°C continuous use

### For Precision Applications
- **Sensor:** MAX31856
- **Thermocouple:** Type R or S (platinum-based)
- **Reason:** Highest accuracy (±1°C) and stability

## Additional Resources

- MAX31855 Datasheet: https://www.analog.com/en/products/max31855.html
- MAX31856 Datasheet: https://www.analog.com/en/products/max31856.html
- Thermocouple Reference: https://www.omega.com/prodinfo/thermocouples.html
- Pyroelectric Supplies: https://www.pyrometric.com/