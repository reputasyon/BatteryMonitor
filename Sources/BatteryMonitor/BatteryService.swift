import Foundation
import IOKit
import Observation

@Observable
@MainActor
final class BatteryService {
    var current: BatteryInfo?
    var startInfo: BatteryInfo?

    @ObservationIgnored private var history: [BatteryInfo] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastState: BatteryState?
    @ObservationIgnored private var stateChangeTime: Date?
    @ObservationIgnored var onUpdate: (() -> Void)?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard let info = Self.readBattery() else { return }

        // Reset history when charging state changes (plug/unplug)
        if let last = lastState, last != info.state {
            history.removeAll()
            stateChangeTime = Date()
        }
        lastState = info.state

        current = info
        history.append(info)
        if history.count > 600 { history.removeFirst(history.count - 600) }
        if startInfo == nil { startInfo = info }

        onUpdate?()
    }

    // MARK: - Computed Stats

    var measuredRatePctPerHour: Double? {
        guard history.count >= 2 else { return nil }

        let now = Date()
        let window: TimeInterval = 120 // 2 minutes
        let recent = history.filter { now.timeIntervalSince($0.timestamp) <= window }
        guard recent.count >= 2,
              let first = recent.first,
              let last = recent.last else { return nil }

        let dtHours = last.timestamp.timeIntervalSince(first.timestamp) / 3600
        guard dtHours >= 0.005 else { return nil } // at least ~18 seconds
        return Double(last.percentage - first.percentage) / dtHours
    }

    var sessionDelta: Int {
        guard let s = startInfo, let c = current else { return 0 }
        return c.percentage - s.percentage
    }

    var sessionMinutes: Double {
        guard let s = startInfo else { return 0 }
        return Date().timeIntervalSince(s.timestamp) / 60
    }

    // MARK: - IOKit Battery Reading

    nonisolated static func readBattery() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service, &propsRef, kCFAllocatorDefault, 0
        )
        guard result == KERN_SUCCESS,
              let dict = propsRef?.takeRetainedValue() as? [String: Any] else { return nil }

        func val<T>(_ key: String) -> T? { dict[key] as? T }

        let percentage: Int = val("CurrentCapacity") ?? 0
        let rawCap: Int = val("AppleRawCurrentCapacity") ?? 0
        let maxCap: Int = val("NominalChargeCapacity") ?? 0
        let designCap: Int = val("DesignCapacity") ?? 0
        let voltage: Int = val("AppleRawBatteryVoltage") ?? 0
        let external: Bool = val("ExternalConnected") ?? false
        let fullyCharged: Bool = val("FullyCharged") ?? false
        let isCharging: Bool = val("IsCharging") ?? false
        let cycleCount: Int = val("CycleCount") ?? 0
        let tempRaw: Int? = val("Temperature")

        // Amperage: IOKit may store signed 16-bit as unsigned.
        // Int16 truncation handles both cases correctly:
        //   signed -907 → Int16(-907) = -907
        //   unsigned 64629 (0xFC75) → Int16(truncating) = -907
        var amperage: Int = 0
        if let raw: Int = val("Amperage") {
            amperage = Int(Int16(truncatingIfNeeded: raw))
        }

        // Temperature in centidegrees Celsius
        let temperature: Double? = tempRaw.map { Double($0) / 100.0 }

        // Adapter info from AppleRawAdapterDetails
        var adapterWatts: Int?
        var adapterName: String?
        var adapterVoltage: Int?
        var adapterCurrent: Int?

        if let adapters = dict["AppleRawAdapterDetails"] as? [[String: Any]],
           let first = adapters.first {
            adapterWatts = first["Watts"] as? Int
            adapterName = first["Name"] as? String
            adapterVoltage = first["AdapterVoltage"] as? Int
            adapterCurrent = first["Current"] as? Int
        }

        return BatteryInfo(
            percentage: percentage,
            rawCapacityMah: rawCap,
            maxCapacityMah: maxCap,
            designCapacityMah: designCap,
            voltageMv: voltage,
            amperageMa: amperage,
            isCharging: isCharging,
            isPluggedIn: external,
            isFullyCharged: fullyCharged,
            cycleCount: cycleCount,
            temperatureC: temperature,
            adapterWatts: adapterWatts,
            adapterName: adapterName,
            adapterVoltageMv: adapterVoltage,
            adapterCurrentMa: adapterCurrent,
            timestamp: Date()
        )
    }
}
