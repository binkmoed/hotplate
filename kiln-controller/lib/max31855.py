class MAX31855:
    """Wrapper around the Adafruit MAX31855 CircuitPython driver.

    The MAX31855 chip only supports Type K thermocouples (hardware
    limitation).  All hardware imports are deferred to ``__init__``
    so the module can be imported on non-Pi machines.
    """

    SUPPORTED_THERMOCOUPLE_TYPE = 'K'

    def __init__(self, spi_bus=0, spi_device=0, thermocouple_type='K'):
        if thermocouple_type.upper() != 'K':
            print(
                f"WARNING: MAX31855 only supports Type K thermocouples. "
                f"Configured type '{thermocouple_type}' will be ignored."
            )

        try:
            import digitalio
            import board
            from adafruit_max31855 import MAX31855 as AdafruitMAX31855
        except ImportError as e:
            raise RuntimeError(
                "Adafruit MAX31855 libraries not installed. "
                "Install: pip install adafruit-circuitpython-max31855"
            ) from e

        self.spi = board.SPI()
        self.cs = digitalio.DigitalInOut(board.CE0)
        self.cs.direction = digitalio.Direction.OUTPUT
        self.sensor = AdafruitMAX31855(self.spi, self.cs)

    @classmethod
    def get_supported_types(cls):
        return [cls.SUPPORTED_THERMOCOUPLE_TYPE]

    @classmethod
    def is_type_supported(cls, tc_type):
        return tc_type.upper() == cls.SUPPORTED_THERMOCOUPLE_TYPE

    def read_temperature(self):
        if self.sensor is None:
            raise RuntimeError("Sensor not initialised")
        temp_c = self.sensor.temperature
        if temp_c is None:
            raise RuntimeError("Temperature reading failed")
        return temp_c

    def check_faults(self):
        if self.sensor is None:
            return True
        try:
            # MAX31855: reading internal temp as a sanity check
            _ = self.sensor.internal_temperature
            return False
        except Exception:
            return True

    def close(self):
        if hasattr(self, 'spi'):
            try:
                self.spi.deinit()
            except Exception:
                pass
        if hasattr(self, 'cs'):
            try:
                self.cs.deinit()
            except Exception:
                pass
