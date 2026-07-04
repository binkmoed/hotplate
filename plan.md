# KilnControllerV2 Project Plan

## Project Overview
KilnControllerV2 is a SwiftUI application designed to monitor and control a kiln. It communicates with a kiln controller via a WebSocket for real-time updates and a REST API for configuration and program management.

## Architecture
The project follows the MVVM (Model-View-ViewModel) architecture.

### 1. Models
Data structures representing the domain:
- `FiringProgram.swift`: Defines the sequence of temperature steps for a kiln firing.
- `ControllerSettings.swift`: Configuration settings for the controller.
- `KilnStatus.swift`: Current state of the kiln (temperature, status, etc.).
- `WebSocketMessage.swift`: Structure for messages received via WebSocket.
- `TempLogEntry.swift`: Individual temperature reading for graphing.

### 2. ViewModels
Business logic and state management for views:
- `DashboardViewModel.swift`: Manages the main status screen and quick actions.
- `ProgramsViewModel.swift`: Handles loading, creating, and updating firing programs.
- `ProgramEditorViewModel.swift`: Specifically handles the logic for editing a program's segments.
- `GraphViewModel.swift`: Processes temperature logs for visualization.
- `SettingsViewModel.swift`: Manages connection settings and general app configuration.

### 3. Views
UI components organized by feature:
- **Dashboard**:
    - `DashboardView.swift`: Main entry point for monitoring.
    - `StatusCardView.swift`, `TemperatureGaugeView.swift`, `QuickActionsView.swift`: Modular components for the dashboard.
- **Programs**:
    - `ProgramsListView.swift`: List of available firing programs.
    - `ProgramEditorView.swift`: Interface for modifying firing steps.
    - `ProgramCardView.swift`, `SegmentRowView.swift`, `ProgramPickerView.swift`: Supporting views for programs.
- **Graph**:
    - `GraphView.swift`: Visualization of actual and setpoint temperature over time from Schedule start to projected end time.
- **Settings**:
    - `SettingsView.swift`: General settings. Temperature unit Celcius or Farenheit. Temperature measurement board Max31855 or Max31856 using Hardware or Software SPI. Thermocouple type possible depending on Temperature measurement board. Kiln elements power in kW. Electricity price per kilowatt. Currency Unit.
    - `ConnectionSetupView.swift`: Configuration for the controller's IP and port. Ping test for ip address.
- **Components**:
    - `TempDisplay.swift`, `ConnectionIndicator.swift`, `LoadingOverlay.swift`: Common UI elements used across multiple views.

### 4. Services
Infrastructure and communication layers:
- `WebSocketService.swift`: Handles the real-time bidirectional communication with the kiln.
- `ControllerAPI.swift`: Handles REST API requests (e.g., sending programs, updating settings).
- `KeychainService.swift`: Securely stores sensitive information like API keys or credentials.
- `KilnWatcher.swift`: Monitors kiln for errors. The kiln is heating at full power but fails to reach the required temperature increase (often due to worn heating elements, low voltage, or a blown fuse). Thermocouple defect or broken connection. Thermocouple polarity is reversed or the temperature sensor is reading colder than -15° C, Safety alarm activated, usually due to a stuck relay or the kiln exceeding the maximum target temperature, Internal hardware failure detected during the controller's self-check at power-up. Emergency button pressed or lid open or other critical error? stop firing, disconnect contactor and SSR.
Event Messages: Certain conditions like power interruptions cause an event message and typically hold or terminate the program
upon return. PC & Mobile Integration: You can track firings live and receive alerts or firing results via imessage/sms/email.
Error Logs:  store recent events internally. Up to the 50 most recent errors can be viewed or sent via email for deep troubleshooting. A built-in safety function monitors the rate of temperature rise during the full-power heating phase. If the temperature fails to rise by a minimum required threshold of 1 or 2 degrees C over a set period, usually 15 to 30 minutes, the controller cuts power to the heating elements to prevent damage or fire hazards.

- `KilnSelfTest.swift` : Check for valid temperature. Check for network connectivity.

### 5. Utilities
Helper classes and extensions:
- `TemperatureFormatter.swift`: Handles conversion and formatting of temperature values.
- `Extensions.swift`: General SwiftUI/Swift extensions.
- `HapticsManager.swift`: Manages tactile feedback for user interactions.

### 6. State Management
- `AppState.swift`: A central state object (likely an `ObservableObject`) that coordinates state across different ViewModels and Services.

## Testing
- `KilnControllerV2Tests`: Unit tests for logic.
- `KilnControllerV2UITests`: UI tests for user flow verification.

## Future Goals / Roadmap
*(This section can be updated as new requirements emerge)*
- [ ] Implement real-time alerting for temperature thresholds.
- [ ] Improve graph interactivity (zoom/pan).
- [ ] Implement offline caching for programs.
- [ ] Ask me questions for other ideas of improvements and extra functionality.

