import SwiftUI

/// The first screen: free space, what could be cleared, and a summary of every other tab.
struct OverviewView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var disk: DiskStore
    @EnvironmentObject var apps: AppsStore
    @EnvironmentObject var ai: AIStore
    @EnvironmentObject var monitor: MonitorStore

    private var subtitle: String {
        let scan = state.lastScan.map { "last scan \(Format.ago($0))" } ?? "not scanned yet"
        return "\(Engine.machineName()) · \(Engine.volumeName()) · \(scan)"
    }

    private var isScanning: Bool { state.phase == .scanning || disk.measuring }

    var body: some View {
        Page(icon: AppTab.overview.icon, title: "Overview", subtitle: subtitle) {
            if isScanning {
                BusyLabel(text: state.phase == .scanning ? state.scanningTaskName : "Measuring the disk…")
                    .frame(maxWidth: 260, alignment: .trailing)
            }
            KitButton(state.hasScanned ? "Scan again" : "Scan this Mac", icon: "magnifyingglass",
                      kind: .primary) { scanAll() }
                .disabled(isScanning || state.isBusy)
        } content: {
            ScrollView {
                VStack(spacing: Theme.gap) {
                    SpaceCard()
                    HStack(alignment: .top, spacing: Theme.gap) {
                        CleanSummary()
                        MonitorSummary()
                        AISummary()
                    }
                    .frame(height: 318)
                    HStack(spacing: Theme.gap) {
                        StatTile(label: "Cleaned all time", icon: "sparkles", color: Theme.green,
                                 value: Format.bytes(state.cleanedAllTime),
                                 detail: state.cleanUps == 1 ? "1 clean-up" : "\(state.cleanUps) clean-ups")
                        StatTile(label: "Applications", icon: AppTab.apps.icon,
                                 value: apps.scanned ? "\(apps.apps.count)" : "—",
                                 detail: apps.apps.first.map { "Largest: \($0.name) (\(Format.bytes($0.bytes)))" }
                                     ?? (apps.scanning ? "Sizing apps…" : "Not scanned yet"))
                        StatTile(label: "Large files", icon: "doc.text", color: Theme.amber,
                                 value: disk.index == nil ? "—" : Format.bytes(disk.largeFilesBytes),
                                 detail: disk.index == nil ? "Not measured yet"
                                     : "\(disk.largeFiles.count) over \(Format.bytes(disk.largeThreshold))")
                        StatTile(label: "Trash", icon: "trash",
                                 value: state.hasScanned ? Format.bytes(state.sizes["trash"] ?? 0) : "—",
                                 detail: "Emptied with Safe to clean")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .scrollIndicators(.never)
        }
        .onAppear {
            monitor.start()
            ai.refreshLive()
            // Once the user has scanned this Mac, keep the summaries filled in.
            if state.hasScanned {
                if !apps.scanned { apps.scan() }
                if !ai.diskScanned { ai.scanDisk() }
            }
        }
        .onDisappear { monitor.stop() }
    }

    private func scanAll() {
        state.scanEverything()
        apps.scan()
        ai.scanDisk()
    }
}

// MARK: - Free space

private struct SpaceCard: View {
    @EnvironmentObject var state: AppState

    private var freeFraction: Double {
        state.totalSpace > 0 ? Double(state.freeSpace) / Double(state.totalSpace) : 1
    }

    private var segments: [StackedBar.Segment] {
        let clearable = RiskTier.allCases.map { state.totalJunk(tier: $0) }
        let used = max(0, state.totalSpace - state.freeSpace - clearable.reduce(0, +))
        return [.init(id: "used", color: Theme.accent, value: Double(used))]
            + zip(RiskTier.allCases, clearable).map {
                .init(id: $0.shortTitle, color: Theme.tierColor($0), value: Double($1))
            }
            + [.init(id: "free", color: Theme.track, value: Double(state.freeSpace))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.bytes(state.freeSpace))
                    .font(.display(30))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("free of \(Format.bytes(state.totalSpace))")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                if freeFraction < 0.1 {
                    Badge(freeFraction < 0.05 ? "Full" : "Nearly full", color: Theme.red,
                          icon: "exclamationmark.triangle")
                }
                Spacer()
                if state.hasScanned {
                    Text(Format.bytes(state.clearable)).fontWeight(.bold).foregroundStyle(Theme.textPrimary)
                        + Text(" could be cleared").foregroundStyle(Theme.textSecondary)
                    KitButton("Clean the safe part", icon: "bolt", kind: .gold) {
                        state.selectTier(.safe)
                        state.tab = .clean
                    }
                    .disabled(state.totalJunk(tier: .safe) == 0 || state.isBusy)
                }
            }
            .font(.system(size: 15))

            StackedBar(segments: segments, height: 16)

            HStack(spacing: 22) {
                LegendItem(color: Theme.accent, label: "Used",
                           value: Format.bytes(max(0, state.totalSpace - state.freeSpace - state.clearable)))
                ForEach(RiskTier.allCases, id: \.self) { tier in
                    LegendItem(color: Theme.tierColor(tier), label: tier.shortTitle,
                               value: state.hasScanned ? Format.bytes(state.totalJunk(tier: tier)) : "—")
                }
                LegendItem(color: Theme.track, label: "Free", value: Format.bytes(state.freeSpace))
                Spacer()
            }
        }
        .padding(20)
        .panel()
    }
}

// MARK: - Summary panels

/// Panel with a label row on top; the three summaries share this frame.
private struct SummaryPanel<Accessory: View, Content: View>: View {
    let label: String
    let icon: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(label, icon: icon)
                Spacer()
                accessory()
            }
            .padding(.horizontal, 18)
            .frame(height: 50)
            Rule()
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .panel()
    }
}

private struct CleanSummary: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        SummaryPanel(label: "Clean", icon: AppTab.clean.icon) {
            Text(state.hasScanned ? Format.bytes(state.clearable) : "—")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        } content: {
            ForEach(RiskTier.allCases, id: \.self) { tier in
                let found = state.tasks(in: tier).filter { state.size(of: $0) > 0 }
                NavRow(icon: tier.icon, color: Theme.tierColor(tier), title: tier.title,
                       subtitle: state.hasScanned
                           ? (found.count == 1 ? "1 place" : "\(found.count) places") : tier.blurb,
                       value: state.hasScanned ? Format.bytes(state.totalJunk(tier: tier)) : "—") {
                    state.tab = .clean
                }
                Rule()
            }
            Spacer(minLength: 0)
            KitButton(state.hasScanned
                      ? "Review and clean \(Format.bytes(state.totalJunk(tier: .safe)))" : "Scan this Mac",
                      kind: .primary, fill: true) {
                if state.hasScanned {
                    state.selectTier(.safe)
                    state.tab = .clean
                } else {
                    state.scanEverything()
                }
            }
            .disabled(state.isBusy)
            .padding(14)
        }
    }
}

private struct MonitorSummary: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var monitor: MonitorStore

    private var healthBadge: (String, Color) {
        switch monitor.health {
        case .good: return ("Good", Theme.green)
        case .fair: return ("Fair", Theme.amber)
        case .poor: return ("Poor", Theme.red)
        }
    }

    private var memoryColor: Color {
        switch monitor.pressure {
        case .normal: return Theme.accent
        case .warning: return Theme.amber
        case .critical: return Theme.red
        }
    }

    private var pressureWord: String {
        switch monitor.pressure {
        case .normal: return "normal"
        case .warning: return "warning"
        case .critical: return "critical"
        }
    }

    private var message: (title: String, text: String) {
        let freeFraction = state.totalSpace > 0 ? Double(state.freeSpace) / Double(state.totalSpace) : 1
        if freeFraction < 0.1 {
            return ("You are low on disk space",
                    "Clear caches, logs and build output to get room back.")
        }
        if monitor.pressure != .normal {
            return ("Memory is under pressure", "Quit apps you are not using; Monitor shows the heaviest.")
        }
        return ("This Mac is running well", "Nothing needs your attention right now.")
    }

    var body: some View {
        SummaryPanel(label: "Monitor", icon: "cpu") {
            Badge(healthBadge.0, color: healthBadge.1)
        } content: {
            Button { state.tab = .monitor } label: {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Reading(label: "CPU", icon: "cpu", value: Format.percent(monitor.cpu),
                                meter: monitor.cpu, color: Theme.green,
                                caption: "\(monitor.cores) cores · load \(String(format: "%.1f", monitor.load.first ?? 0))")
                        Rectangle().fill(Theme.line).frame(width: 1)
                        Reading(label: "Memory", icon: "memorychip", value: Format.memory(monitor.memUsed),
                                meter: Double(monitor.memUsed) / Double(max(monitor.memTotal, 1)),
                                color: memoryColor,
                                caption: "of \(Format.memory(monitor.memTotal)) · \(pressureWord)")
                    }
                    Rule()
                    HStack(spacing: 0) {
                        Reading(label: "Network", icon: "wifi", value: "↓ " + Format.rate(monitor.netDown),
                                meter: nil, color: Theme.blue, caption: "↑ " + Format.rate(monitor.netUp))
                        Rectangle().fill(Theme.line).frame(width: 1)
                        if let battery = monitor.battery {
                            Reading(label: "Battery", icon: "battery.75percent", value: "\(battery.percent)%",
                                    meter: Double(battery.percent) / 100, color: Theme.green,
                                    caption: battery.isCharging ? "Charging"
                                        : battery.onBattery ? "On battery" : "Plugged in")
                        } else {
                            Reading(label: "Battery", icon: "powerplug", value: "—", meter: nil,
                                    color: Theme.green, caption: "No battery")
                        }
                    }
                    Rule()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(message.title).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(message.text).font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// One quadrant: label, big value, optional bar, caption.
    private struct Reading: View {
        let label: String
        let icon: String
        let value: String
        let meter: Double?
        let color: Color
        let caption: String

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(label, icon: icon)
                Text(value).font(.display(18)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let meter { Meter(value: meter, color: color) }
                Text(caption).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 100)
        }
    }
}

private struct AISummary: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var ai: AIStore
    @EnvironmentObject var monitor: MonitorStore

    private func names(_ list: [String], empty: String) -> String {
        guard !list.isEmpty else { return empty }
        let shown = list.prefix(3).joined(separator: ", ")
        return list.count > 3 ? "\(shown) +\(list.count - 3)" : shown
    }

    var body: some View {
        SummaryPanel(label: "AI on this Mac", icon: AppTab.ai.icon) {
            if let gpu = monitor.gpu { Badge("GPU \(Format.percent(gpu))", color: Theme.violet) }
        } content: {
            NavRow(icon: "brain", color: Theme.violet, title: "AI data on disk",
                   subtitle: ai.diskScanning ? "Sizing…"
                       : names(ai.diskToolNames, empty: ai.diskScanned ? "No AI tools found" : "Not scanned yet"),
                   value: ai.diskScanned ? Format.bytes(ai.diskBytes) : "—") { state.tab = .ai }
            Rule()
            NavRow(icon: "memorychip", color: Theme.violet, title: "AI apps in memory now",
                   subtitle: names(ai.runningNames, empty: "None running"),
                   value: Format.memory(ai.memoryBytes)) { state.tab = .ai }
            Rule()
            NavRow(icon: "dot.radiowaves.left.and.right", color: Theme.violet,
                   title: "Local AI servers",
                   subtitle: names(ai.serverLabels, empty: "None"),
                   value: "\(ai.serverLabels.count)") { state.tab = .ai }
            Rule()
            Spacer(minLength: 0)
            KitButton("Open AI usage", fill: true) { state.tab = .ai }.padding(14)
        }
    }
}
