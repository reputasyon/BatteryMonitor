# Battery Monitor for macOS

A lightweight, native macOS menu bar app that shows real-time battery charging rate, power consumption, and detailed battery health information.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu Bar Integration** - Lives in your menu bar showing battery % and charging rate
- **Real-time Charging Rate** - Shows %/hour charging or discharging speed
- **Power Details** - Adapter input power, battery charging power, voltage, current
- **Time Estimates** - Estimated time to full charge or battery empty
- **Battery Health** - Health percentage, cycle count, capacity vs design capacity
- **Temperature Monitoring** - Real-time battery temperature
- **Session Tracking** - Tracks charge change since app launch
- **Zero Dependencies** - Pure Swift, uses IOKit directly for battery data

## Screenshot

```
Menu Bar:  🔋 14% ⚡16%/h

┌─────────────────────────────────┐
│ 🔋 Sarj Ediliyor         16%/sa │
│    14%                          │
│ [====........................]   │
│                                 │
│ Guc Detaylari                   │
│ Adaptor:    20W USB-C Adapter   │
│ Adaptor:    20.0W / 20W         │
│ Pile Giden: 10.3W               │
│ Voltaj:     11.03V              │
│ Sarj Akimi: 907mA               │
│                                 │
│ Sarj Hizi                       │
│ Anlik Hiz:  16.3%/saat          │
│ Tam Dolu:   5sa 23dk            │
│                                 │
│ Pil Sagligi                     │
│ Saglik:     91.4%               │
│ Dongu:      140 / 1000          │
│ Kapasite:   641/5551 mAh        │
│ Sicaklik:   31.0°C              │
└─────────────────────────────────┘
```

## Installation

### Build from Source

Requires **Xcode 16+** and **macOS 14+**.

```bash
git clone https://github.com/abdullahkaragoz/BatteryMonitor.git
cd BatteryMonitor
swift build -c release
```

The built binary will be at `.build/release/BatteryMonitor`.

### Run

```bash
# Run directly
swift run

# Or run the built binary
.build/release/BatteryMonitor
```

### Optional: Add to Login Items

To start automatically on login:

1. Build release: `swift build -c release`
2. Copy to Applications: `cp .build/release/BatteryMonitor /usr/local/bin/`
3. Add to Login Items in System Settings

## How It Works

The app reads battery data directly from macOS IOKit (`AppleSmartBattery`) which provides:

| Data | Source |
|------|--------|
| Charge % | `CurrentCapacity` |
| Capacity | `AppleRawCurrentCapacity` / `NominalChargeCapacity` |
| Voltage | `AppleRawBatteryVoltage` |
| Current | `Amperage` (signed 64-bit) |
| Adapter | `AppleRawAdapterDetails` (watts, voltage, current) |
| Health | `NominalChargeCapacity` / `DesignCapacity` |
| Temperature | `Temperature` (centidegrees) |
| Cycles | `CycleCount` |

### Charging Rate Calculation

```
Instant Rate = (|Amperage| / MaxCapacity) * 100  →  %/hour
Power        = |Voltage * Amperage| / 1,000,000  →  Watts
Health       = MaxCapacity / DesignCapacity * 100 →  %
```

## Tech Stack

- **SwiftUI** - Popover UI
- **AppKit** - Menu bar (NSStatusItem)
- **IOKit** - Native battery data access
- **Swift Package Manager** - Build system

## License

MIT License - see [LICENSE](LICENSE) for details.
