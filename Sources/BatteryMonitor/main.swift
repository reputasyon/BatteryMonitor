import AppKit
import SwiftUI
import IOKit
import Combine

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
        if isFullyCharged { return .full }
        if isPluggedIn && (isCharging || amperageMa < 0) { return .charging }
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
        guard let rate = chargingRatePctPerHour, rate > 0 else { return nil }
        let remaining = state == .charging ? Double(100 - percentage) : Double(percentage)
        return (remaining / rate) * 60
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

enum BatteryState {
    case charging, discharging, full, pluggedNotCharging
}

// MARK: - Battery Service

@MainActor
final class BatteryService: ObservableObject {
    @Published var current: BatteryInfo?
    @Published var history: [BatteryInfo] = []
    @Published var startInfo: BatteryInfo?

    private var timer: Timer?

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

    private var lastState: BatteryState?
    private var stateChangeTime: Date?

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
        if history.count > 600 { history.removeFirst() }
        if startInfo == nil { startInfo = info }
    }

    var measuredRatePctPerHour: Double? {
        guard history.count >= 2 else { return nil }

        // Use last 2 minutes of data for a sliding window
        let now = Date()
        let window: TimeInterval = 120 // 2 minutes
        let recent = history.filter { now.timeIntervalSince($0.timestamp) <= window }
        guard recent.count >= 2 else { return nil }

        let first = recent.first!
        let last = recent.last!
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
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let dict = propsRef?.takeRetainedValue() as? [String: Any] else { return nil }

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

        // Amperage is unsigned 64-bit, convert to signed
        var amperage: Int = 0
        if let raw: Int = val("Amperage") {
            if raw > Int(Int64.max) / 2 {
                amperage = raw &- Int(bitPattern: UInt.max) - 1
            } else {
                amperage = raw
            }
        }

        // Temperature in centidegrees
        let temperature: Double? = tempRaw.map { Double($0) / 100.0 }

        // Adapter info from AppleRawAdapterDetails
        var adapterWatts: Int?
        var adapterName: String?
        var adapterVoltage: Int?
        var adapterCurrent: Int?

        if let adapters = dict["AppleRawAdapterDetails"] as? [[String: Any]], let first = adapters.first {
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

// MARK: - SwiftUI Views

struct BatteryPopoverView: View {
    @ObservedObject var service: BatteryService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let info = service.current {
                // Header
                headerSection(info)
                Divider().padding(.horizontal)

                // Battery bar
                batteryBarSection(info)
                Divider().padding(.horizontal)

                // Power details
                powerSection(info)
                Divider().padding(.horizontal)

                // Charging rate
                rateSection(info)
                Divider().padding(.horizontal)

                // Health
                healthSection(info)

                // Session
                sessionSection()
            } else {
                Text("Pil bilgisi okunamadi")
                    .foregroundStyle(.secondary)
                    .padding()
            }

            Divider().padding(.horizontal)
            footerSection()
        }
        .frame(width: 320)
    }

    // MARK: - Header

    @ViewBuilder
    func headerSection(_ info: BatteryInfo) -> some View {
        HStack {
            Image(systemName: info.batteryIcon)
                .font(.title2)
                .foregroundStyle(stateColor(info.state))
                .symbolEffect(.pulse, isActive: info.state == .charging)

            VStack(alignment: .leading, spacing: 2) {
                Text(stateLabel(info.state))
                    .font(.headline)
                    .foregroundStyle(stateColor(info.state))
                Text("\(info.percentage)%")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
            }

            Spacer()

            if let rate = info.chargingRatePctPerHour {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(info.state == .charging ? "Şarj Hızı" : "Tüketim")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f%%/sa", rate))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(stateColor(info.state))
                }
            }
        }
        .padding()
    }

    // MARK: - Battery Bar

    @ViewBuilder
    func batteryBarSection(_ info: BatteryInfo) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(barGradient(info))
                        .frame(width: geo.size.width * CGFloat(info.percentage) / 100)
                }
            }
            .frame(height: 14)

            HStack {
                Text("0%")
                Spacer()
                if let est = info.estimatedMinutesRemaining {
                    let label = info.state == .charging ? "Dolu" : "Boş"
                    Text("\(label): \(formatTime(est))")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(stateColor(info.state))
                }
                Spacer()
                Text("100%")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Power

    @ViewBuilder
    func powerSection(_ info: BatteryInfo) -> some View {
        VStack(spacing: 6) {
            sectionHeader("Güç Detayları", icon: "bolt.fill")

            if info.isPluggedIn {
                if let name = info.adapterName {
                    infoRow("Adaptör", name)
                }
                if let inputW = info.adapterInputWatts {
                    let maxW = info.adapterWatts ?? 0
                    infoRow("Adaptör Giriş", String(format: "%.1fW / %dW", inputW, maxW))
                }
            }

            let powerLabel = info.state == .charging ? "Pile Giden Güç" : "Tüketim"
            infoRow(powerLabel, String(format: "%.1fW", info.powerWatts))

            infoRow("Voltaj", String(format: "%.2fV", Double(info.voltageMv) / 1000))

            let ampLabel = info.amperageMa < 0 ? "Şarj Akımı" : "Çekilen Akım"
            infoRow(ampLabel, "\(abs(info.amperageMa)) mA")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Rate

    @ViewBuilder
    func rateSection(_ info: BatteryInfo) -> some View {
        VStack(spacing: 6) {
            let title = info.state == .charging ? "Şarj Hızı" : "Tüketim Hızı"
            sectionHeader(title, icon: "speedometer")

            if let rate = info.chargingRatePctPerHour {
                let prefix = info.state == .charging ? "+" : "-"
                infoRow("Anlık Hız", "\(prefix)\(String(format: "%.1f", rate))%/saat")

                if rate > 0 {
                    let minsPerPct = 60 / rate
                    infoRow("Her %1 için", String(format: "%.1f dk", minsPerPct))
                }

                if let est = info.estimatedMinutesRemaining {
                    let label = info.state == .charging ? "Tamamen Dolu" : "Kalan Süre"
                    HStack {
                        Text(label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatTime(est))
                            .foregroundStyle(stateColor(info.state))
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                }
            } else {
                Text("Hesaplanıyor...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let measured = service.measuredRatePctPerHour, abs(measured) > 0.1 {
                // Only show if direction matches current state
                let isConsistent = (info.state == .charging && measured > 0) ||
                                   (info.state == .discharging && measured < 0)
                if isConsistent {
                    HStack {
                        Text("Ölçülen Ort.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%+.1f%%/sa", measured))
                            .foregroundStyle(.blue)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Health

    @ViewBuilder
    func healthSection(_ info: BatteryInfo) -> some View {
        VStack(spacing: 6) {
            sectionHeader("Pil Sağlığı", icon: "heart.fill")

            let hp = info.healthPercent
            let hColor: Color = hp >= 80 ? .green : hp >= 60 ? .yellow : .red
            HStack {
                Text("Sağlık")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", hp))
                    .foregroundStyle(hColor)
                    .fontWeight(.semibold)
            }
            .font(.caption)

            let ccColor: Color = info.cycleCount < 500 ? .green : info.cycleCount < 800 ? .yellow : .red
            HStack {
                Text("Döngü Sayısı")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(info.cycleCount) / 1000")
                    .foregroundStyle(ccColor)
            }
            .font(.caption)

            infoRow("Kapasite", "\(info.rawCapacityMah) / \(info.maxCapacityMah) mAh")
            infoRow("Fabrika", "\(info.designCapacityMah) mAh")

            if let temp = info.temperatureC {
                let tColor: Color = temp < 35 ? .green : temp < 40 ? .yellow : .red
                HStack {
                    Text("Sıcaklık")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f\u{00B0}C", temp))
                        .foregroundStyle(tColor)
                }
                .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Session

    @ViewBuilder
    func sessionSection() -> some View {
        if service.sessionMinutes > 0.5 {
            VStack(spacing: 4) {
                Divider().padding(.horizontal)
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Oturum: \(formatTime(service.sessionMinutes)), \(service.sessionDelta >= 0 ? "+" : "")\(service.sessionDelta)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    func footerSection() -> some View {
        HStack {
            Text("\(service.history.count) örnek")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            Button("Kapat") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    @ViewBuilder
    func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
    }

    @ViewBuilder
    func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption)
    }

    func stateColor(_ state: BatteryState) -> Color {
        switch state {
        case .charging: return .green
        case .discharging: return .orange
        case .full: return .cyan
        case .pluggedNotCharging: return .purple
        }
    }

    func stateLabel(_ state: BatteryState) -> String {
        switch state {
        case .charging: return "Şarj Ediliyor"
        case .discharging: return "Pil Kullanılıyor"
        case .full: return "Tam Dolu"
        case .pluggedNotCharging: return "Takılı (şarj etmiyor)"
        }
    }

    func barGradient(_ info: BatteryInfo) -> LinearGradient {
        let colors: [Color]
        switch info.state {
        case .charging:
            colors = [.green.opacity(0.7), .green]
        case .full:
            colors = [.cyan.opacity(0.7), .cyan]
        default:
            if info.percentage <= 10 {
                colors = [.red.opacity(0.7), .red]
            } else if info.percentage <= 25 {
                colors = [.orange.opacity(0.7), .orange]
            } else {
                colors = [.green.opacity(0.7), .green]
            }
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    func formatTime(_ minutes: Double) -> String {
        if minutes <= 0 { return "---" }
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        if h > 0 { return "\(h)sa \(m)dk" }
        return "\(m)dk"
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var service: BatteryService!

    func applicationDidFinishLaunching(_ notification: Notification) {
        service = BatteryService()

        // Hide from dock
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: BatteryPopoverView(service: service))

        // Start battery monitoring
        service.start()
        updateButton()

        // Update menu bar text periodically
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateButton()
            }
        }
    }

    func updateButton() {
        guard let button = statusItem.button else { return }
        if let info = service.current {
            button.image = nil
            let text = info.menuBarText
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ]
            button.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        } else {
            button.title = "..."
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Offset the rect downward so popover doesn't stick to the menu bar
            var rect = button.bounds
            rect.origin.y -= 8
            popover.show(relativeTo: rect, of: button, preferredEdge: .minY)
            NSApp.activate()
        }
    }
}

// MARK: - Launch

let app = NSApplication.shared
let delegate = { @MainActor in AppDelegate() }()
app.delegate = delegate
app.run()
