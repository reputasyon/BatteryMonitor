import SwiftUI
import ServiceManagement

struct BatteryPopoverView: View {
    var service: BatteryService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let info = service.current {
                headerSection(info)
                Divider().padding(.horizontal)
                batteryBarSection(info)
                Divider().padding(.horizontal)
                powerSection(info)
                Divider().padding(.horizontal)
                rateSection(info)
                Divider().padding(.horizontal)
                healthSection(info)
                sessionSection()
            } else {
                Text("Pil bilgisi okunamadı")
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
                        .frame(width: geo.size.width * CGFloat(max(0, min(info.percentage, 100))) / 100)
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
                    let delta = service.sessionDelta
                    Text("Oturum: \(formatTime(service.sessionMinutes)), \(delta >= 0 ? "+" : "")\(delta)%")
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
        VStack(spacing: 6) {
            Toggle(isOn: $launchAtLogin) {
                Label("Başlangıçta Aç", systemImage: "power")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Revert toggle on failure
                    launchAtLogin = !newValue
                }
            }

            HStack {
                Spacer()
                Button("Çıkış") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
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
        guard minutes.isFinite, minutes > 0, minutes < 100_000 else { return "---" }
        let totalMinutes = Int(minutes)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 { return "\(h)sa \(m)dk" }
        return "\(m)dk"
    }
}
