# Battery Monitor for macOS

A lightweight, native macOS menu bar app that shows real-time battery charging rate, power consumption, and detailed battery health information.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Menu Bar Integration** - Lives in your menu bar showing power (W) and charging rate (%/h)
- **Real-time Charging Rate** - Shows %/hour charging or discharging speed
- **Power Details** - Adapter input power, battery charging power, voltage, current
- **Time Estimates** - Estimated time to full charge or battery empty
- **Battery Health** - Health percentage, cycle count, capacity vs design capacity
- **Temperature Monitoring** - Real-time battery temperature
- **Session Tracking** - Tracks charge change since app launch
- **Launch at Login** - Built-in toggle to start on login (SMAppService)
- **Zero Dependencies** - Pure Swift, uses IOKit directly for battery data

## Screenshot

```
Menu Bar:  5W ⚡7%/h

┌─────────────────────────────────┐
│ 🔋 Şarj Ediliyor         16%/sa │
│    14%                          │
│ [====........................]   │
│                                 │
│ Güç Detayları                   │
│ Adaptör:    20W USB-C Adapter   │
│ Adaptör:    20.0W / 20W         │
│ Pile Giden: 10.3W               │
│ Voltaj:     11.03V              │
│ Şarj Akımı: 907mA              │
│                                 │
│ Şarj Hızı                      │
│ Anlık Hız:  16.3%/saat          │
│ Tam Dolu:   5sa 23dk            │
│                                 │
│ Pil Sağlığı                    │
│ Sağlık:     91.4%              │
│ Döngü:      140 / 1000         │
│ Kapasite:   641/5551 mAh       │
│ Sıcaklık:   31.0°C             │
│                                 │
│ ◻ Başlangıçta Aç        Çıkış │
└─────────────────────────────────┘
```

## Installation

### Build from Source

Requires **Xcode 16+** and **macOS 14+**.

```bash
git clone https://github.com/reputasyon/BatteryMonitor.git
cd BatteryMonitor
chmod +x build.sh
./build.sh
```

### Install

```bash
cp -r BatteryMonitor.app /Applications/
```

### Run

```bash
open /Applications/BatteryMonitor.app
```

The app lives in your menu bar (no Dock icon). Click the menu bar text to see details.

### Auto-start on Login

Use the built-in **Başlangıçta Aç** toggle in the panel footer, or manually:

1. Open **System Settings > General > Login Items**
2. Click **+** and select `/Applications/BatteryMonitor.app`

## Project Structure

```
Sources/BatteryMonitor/
├── main.swift              # Entry point (5 lines)
├── BatteryInfo.swift       # Data model + BatteryState enum
├── BatteryService.swift    # IOKit reading, timer, history tracking
├── BatteryPopoverView.swift # SwiftUI panel UI
└── AppDelegate.swift       # NSPanel, NSStatusItem, menu bar
```

| File | Responsibility |
|------|---------------|
| `BatteryInfo.swift` | Battery data struct, state enum, computed properties (power, health, rates, menu bar text) |
| `BatteryService.swift` | IOKit `AppleSmartBattery` reading, 3-second refresh timer, sliding window rate measurement |
| `BatteryPopoverView.swift` | SwiftUI view with header, battery bar, power/rate/health sections, session info, footer |
| `AppDelegate.swift` | NSPanel positioning below status item, global click-to-dismiss, fade-in animation |

## How It Works

The app reads battery data directly from macOS IOKit (`AppleSmartBattery`) which provides:

| Data | Source |
|------|--------|
| Charge % | `CurrentCapacity` |
| Capacity | `AppleRawCurrentCapacity` / `NominalChargeCapacity` |
| Voltage | `AppleRawBatteryVoltage` |
| Current | `Amperage` (signed 16-bit via Int16 truncation) |
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

### Architecture

- **`@Observable`** macro (Observation framework) for reactive UI updates
- **`@ObservationIgnored`** on history array to prevent unnecessary SwiftUI rebuilds
- **Single timer** in BatteryService with `onUpdate` callback to AppDelegate
- **NSPanel** (not NSPopover) for precise positioning below the menu bar
- **`nonisolated static`** IOKit reader for thread-safe battery access
- **Int16 truncation** for correct signed amperage from IOKit unsigned values

## Tech Stack

- **SwiftUI** - Panel UI
- **AppKit** - Menu bar (NSStatusItem) + NSPanel
- **IOKit** - Native battery data access
- **Observation** - `@Observable` reactive state
- **ServiceManagement** - Launch at login (SMAppService)
- **Swift Package Manager** - Build system

## License

MIT License - see [LICENSE](LICENSE) for details.
