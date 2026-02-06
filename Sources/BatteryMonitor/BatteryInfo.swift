import Foundation

// MARK: - Battery State

enum BatteryState {
    case charging, discharging, full, pluggedNotCharging
}

// MARK: - Battery Data Model

struct BatteryInfo {
    let percentage: Int
    let rawCapacityMah: Int
    let maxCapacityMah: Int
    let designCapacityMah: Int
    let voltageMv: Int
    let amperageMa: Int
    let isCharging: Bool
    let isPluggedIn: Bool
    let isFullyCharged: Bool
    let cycleCount: Int
    let temperatureC: Double?
    let adapterWatts: Int?
    let adapterName: String?
    let adapterVoltageMv: Int?
    let adapterCurrentMa: Int?
    let timestamp: Date

    var state: BatteryState {
        if isFullyCharged && isPluggedIn { return .full }
        if isPluggedIn && isCharging { return .charging }
        if isPluggedIn { return .pluggedNotCharging }
        return .discharging
    }

    var powerWatts: Double {
        abs(Double(voltageMv) * Double(amperageMa)) / 1_000_000
    }

    var adapterInputWatts: Double? {
        guard let v = adapterVoltageMv, let a = adapterCurrentMa else { return nil }
        return Double(v) * Double(a) / 1_000_000
    }

    var healthPercent: Double {
        guard designCapacityMah > 0 else { return 0 }
        return (Double(maxCapacityMah) / Double(designCapacityMah)) * 100
    }

    var chargingRatePctPerHour: Double? {
        guard maxCapacityMah > 0, amperageMa != 0 else { return nil }
        return (Double(abs(amperageMa)) / Double(maxCapacityMah)) * 100
    }

    var estimatedMinutesRemaining: Double? {
        guard let rate = chargingRatePctPerHour, rate > 0.1 else { return nil }
        let pct = max(0, min(percentage, 100))
        let remaining = state == .charging ? Double(100 - pct) : Double(pct)
        guard remaining > 0 else { return nil }
        let minutes = (remaining / rate) * 60
        guard minutes.isFinite, minutes < 100_000 else { return nil }
        return minutes
    }

    var batteryIcon: String {
        switch state {
        case .charging:
            return "battery.100.bolt"
        case .full:
            return "battery.100"
        case .pluggedNotCharging:
            return "battery.100.bolt"
        case .discharging:
            if percentage <= 10 { return "battery.0" }
            if percentage <= 25 { return "battery.25" }
            if percentage <= 50 { return "battery.50" }
            if percentage <= 75 { return "battery.75" }
            return "battery.100"
        }
    }

    var menuBarText: String {
        let w = String(format: "%.0fW", powerWatts)
        let rate = chargingRatePctPerHour.map { String(format: "%.0f%%/h", $0) }

        switch state {
        case .charging:
            if let rate { return "\(w) \u{26A1}\(rate)" }
            return "\(w) \u{26A1}"
        case .discharging:
            if let rate { return "\(w) \u{2193}\(rate)" }
            return w
        case .full:
            return "\u{2713} Dolu"
        case .pluggedNotCharging:
            return "\(w) \u{23F8}"
        }
    }
}
