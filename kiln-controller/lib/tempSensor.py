import threading
import time
from config import config


class TempSensor(threading.Thread):
    def __init__(self):
        super().__init__()
        self.daemon = True
        self.running = False
        self.temperature = 0.0
        self.temperature_raw = 0.0
        self.error_count = 0
        self.total_readings = 0
        self.last_error = None

        self._initialize_sensor()

    def _initialize_sensor(self):
        try:
            if config.sensor_type.upper() == 'MAX31856':
                from .max31856 import MAX31856
                tc_type = config.thermocouple_type_max31856
                print(f"Initializing MAX31856 with thermocouple type: {tc_type}")
                self.sensor = MAX31856(
                    spi_bus=config.spi_bus,
                    spi_device=config.spi_device,
                    thermocouple_type=tc_type,
                    ac_frequency=config.ac_frequency,
                )
            else:
                from .max31855 import MAX31855
                tc_type = config.thermocouple_type_max31855
                print(f"Initializing MAX31855 (thermocouple type must be K)")
                if tc_type.upper() != 'K':
                    print(f"WARNING: MAX31855 only supports Type K. Configured type '{tc_type}' will be ignored.")
                self.sensor = MAX31855(
                    spi_bus=config.spi_bus,
                    spi_device=config.spi_device,
                    thermocouple_type=tc_type
                )

            print(f"Initialized {config.sensor_type} sensor successfully")

        except Exception as e:
            print(f"Failed to initialize temperature sensor: {e}")
            self.sensor = None
            self.running = False

    def run(self):
        self.running = True

        while self.running:
            try:
                if self.sensor is not None:
                    temp_c = self.sensor.read_temperature()

                    if self.sensor.check_faults():
                        self.error_count += 1
                        self.last_error = "Sensor fault detected"
                        print(f"Sensor fault detected (error #{self.error_count})")
                    else:
                        self.temperature_raw = temp_c

                        if config.temp_scale == 'f':
                            self.temperature = (temp_c * 9/5) + 32
                        else:
                            self.temperature = temp_c

                        self.last_error = None

                self.total_readings += 1

            except Exception as e:
                self.error_count += 1
                self.last_error = str(e)
                print(f"Temperature reading error: {e}")

            time.sleep(0.1)

    def get_temperature(self):
        return self.temperature

    def get_temperature_raw(self):
        return self.temperature_raw

    def get_error_rate(self):
        if self.total_readings == 0:
            return 0.0
        return self.error_count / self.total_readings

    def get_last_error(self):
        return self.last_error

    def reset_error_count(self):
        self.error_count = 0
        self.last_error = None

    def stop(self):
        self.running = False
        if self.sensor:
            self.sensor.close()

    def safe_read(self, settle_time=None):
        if settle_time is None:
            settle_time = config.temp_settle_time

        time.sleep(settle_time)

        max_retries = 3
        for i in range(max_retries):
            try:
                if self.sensor is not None:
                    temp_c = self.sensor.read_temperature()

                    if self.sensor.check_faults():
                        print(f"Sensor fault during safe read (attempt {i+1})")
                        continue

                    if config.temp_scale == 'f':
                        return (temp_c * 9/5) + 32
                    else:
                        return temp_c

            except Exception as e:
                print(f"Safe read error (attempt {i+1}): {e}")

        raise RuntimeError(f"Failed to read temperature after {max_retries} attempts")