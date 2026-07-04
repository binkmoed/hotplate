class MAX31856:
    """Wrapper around the Adafruit MAX31856 CircuitPython driver.

    All hardware imports are deferred to ``__init__`` so the module can
    be imported on non-Pi machines (development / CI) without crashing.
    """

    # Supported thermocouple types (maps letter → MAX31856 register value)
    THERMOCOUPLE_TYPES = ['B', 'E', 'J', 'K', 'N', 'R', 'S', 'T']

    _TC_VALUES = {
        'B': 0,
        'E': 1,
        'J': 2,
        'K': 3,
        'N': 4,
        'R': 5,
        'S': 6,
        'T': 7,
    }

    def __init__(self, spi_bus=0, spi_device=0, thermocouple_type='K',
                 ac_frequency=50):
        tc = thermocouple_type.upper()
        if tc not in self.THERMOCOUPLE_TYPES:
            raise ValueError(
                f"Unsupported thermocouple type: {thermocouple_type}. "
                f"Supported: {', '.join(self.THERMOCOUPLE_TYPES)}"
            )

        try:
            import busio
            import digitalio
            import board
            from adafruit_max31856 import MAX31856 as AdafruitMAX31856
        except ImportError as e:
            raise RuntimeError(
                "Adafruit MAX31856 libraries not installed. "
                "Install: pip install adafruit-circuitpython-max31856"
            ) from e

        self.spi = busio.SPI(board.SCK, board.MOSI, board.MISO)

        # Select CS pin based on spi_device: 0=CE0 (D8), 1=CE1 (D7)
        if spi_device == 1:
            cs_pin = board.D7   # CE1 / GPIO7 / physical pin 26
        else:
            cs_pin = board.CE0  # CE0 / GPIO8 / physical pin 24

        self.cs = digitalio.DigitalInOut(cs_pin)
        self.cs.direction = digitalio.Direction.OUTPUT

        # Newer library versions take thermocouple_type as an int
        tc_val = self._TC_VALUES[tc]

        try:
            self.sensor = AdafruitMAX31856(
                self.spi,
                self.cs,
                thermocouple_type=tc_val,
            )
        except TypeError:
            # Older library versions use named constants
            self.sensor = AdafruitMAX31856(
                self.spi,
                self.cs,
                thermocouple_type=self._get_type_value(AdafruitMAX31856, tc),
            )

        # Set AC noise rejection filter (50Hz for Europe, 60Hz for US)
        if hasattr(self.sensor, 'noise_rejection'):
            try:
                self.sensor.noise_rejection = ac_frequency
            except Exception:
                pass  # not all firmware versions support setting this

    @staticmethod
    def _get_type_value(driver, tc_type):
        """Fallback for older library versions that use class constants."""
        type_map = {
            'B': getattr(driver, 'THERMOCOUPLE_B', 0),
            'E': getattr(driver, 'THERMOCOUPLE_E', 1),
            'J': getattr(driver, 'THERMOCOUPLE_J', 2),
            'K': getattr(driver, 'THERMOCOUPLE_K', 3),
            'N': getattr(driver, 'THERMOCOUPLE_N', 4),
            'R': getattr(driver, 'THERMOCOUPLE_R', 5),
            'S': getattr(driver, 'THERMOCOUPLE_S', 6),
            'T': getattr(driver, 'THERMOCOUPLE_T', 7),
        }
        return type_map.get(tc_type.upper(), 3)

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
            fault = self.sensor.fault
            # fault can be a dict of individual fault flags or an int
            if isinstance(fault, dict):
                has_fault = any(fault.values())
                if has_fault:
                    print(f"MAX31856 fault: {fault}")
                return has_fault
            # Legacy: integer bitmask
            if fault:
                print(f"MAX31856 fault: {fault}")
            return bool(fault)
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
