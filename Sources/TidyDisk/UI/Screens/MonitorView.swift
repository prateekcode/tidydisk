import SwiftUI
import AppKit

// MARK: - Monitor

/// Live readings: eight tiles, a low-disk nudge and the busiest apps.
struct MonitorView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var monitor: MonitorStore
    @State private var sort = ProcessSort.cpu

    private var diskFree: Double {
        state.totalSpace > 0 ? Double(state.freeSpace) / Double(state.totalSpace) : 1
    }

    private var subtitle: String {
        let pace = monitor.paused ? "paused" : "every \(Int(MonitorStore.interval))s"
        return "\(monitor.modelName) · up \(MonitorText.uptime(monitor.uptime)) · \(pace)"
    }

    var body: some View {
        Page(icon: AppTab.monitor.icon, title: "Monitor", subtitle: subtitle) {
            HStack(spacing: 10) {
                HealthBadge(health: monitor.health)
                KitButton(monitor.paused ? "Resume" : "Pause",
                          icon: monitor.paused ? "play.fill" : "pause.fill") {
                    monitor.paused ? monitor.resume() : monitor.pause()
                }
                IconButton(icon: "arrow.clockwise", help: "Refresh now") { monitor.refresh() }
            }
        } content: {
            VStack(spacing: MonitorLayout.gap) {
                HStack(spacing: MonitorLayout.gap) {
                    CPUTile()
                    GPUTile()
                    MemoryTile()
                    DiskTile(free: state.freeSpace, total: state.totalSpace)
                }
                HStack(spacing: MonitorLayout.gap) {
                    NetworkTile()
                    BatteryTile()
                    UptimeTile()
                    SpeedTestTile()
                }
                if diskFree < MonitorLayout.lowDisk {
                    LowDiskBanner { state.tab = .clean }
                }
                ProcessPanel(sort: $sort)
            }
        }
        .onAppear {
            monitor.start()
            monitor.startProcesses()
        }
        .onDisappear {
            monitor.stopProcesses()
            monitor.stop()
            // Pause belongs to this screen; Overview should not inherit frozen numbers.
            monitor.resume()
        }
    }
}

private enum MonitorLayout {
    static let gap: CGFloat = 12
    static let tileHeight: CGFloat = 126
    static let chartHeight: CGFloat = 22
    /// Free share of the disk under which the banner and the FULL badge show.
    static let lowDisk = 0.10
    static let rowCount = 9
    static let cpuColumn: CGFloat = 170
    static let memoryColumn: CGFloat = 190
    static let barWidth: CGFloat = 92

    /// Top of a 0…1 chart: the peak rounded up to the next quarter, so a quiet
    /// Mac still draws a readable curve and the scale only moves in big steps.
    static func shareCeiling(_ history: [Double]) -> Double {
        min(max(((history.max() ?? 0) * 4).rounded(.up) / 4, 0.25), 1)
    }
}

/// Wording the shared `Format` does not cover.
private enum MonitorText {
    /// "6d 5h", "5h 12m", "12m".
    static func uptime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let days = minutes / 1440, hours = minutes % 1440 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    /// Per-process CPU, where 100 is one whole core.
    static func cores(_ percent: Double) -> String {
        percent >= 10 ? "\(Int(percent.rounded()))%" : String(format: "%.1f%%", percent)
    }

    static func load(_ values: [Double]) -> String {
        values.map { String(format: "%.1f", $0) }.joined(separator: " / ")
    }

    static func mbps(_ value: Double) -> String {
        String(format: value >= 100 ? "%.0f" : "%.1f", value)
    }
}

// MARK: - Header pieces

private struct HealthBadge: View {
    let health: MonitorStore.Health

    var body: some View {
        switch health {
        case .good: Badge("Good", color: Theme.green)
        case .fair: Badge("Fair", color: Theme.amber)
        case .poor: Badge("Poor", color: Theme.red)
        }
    }
}

/// Icon-only twin of the secondary `KitButton`.
private struct IconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34, height: 34)
                .panel(radius: 8, fill: Theme.panel.opacity(hovering ? 0.86 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Tile parts

/// A reading card: icon + label (+ badge) on top, then whatever the reading needs.
private struct Tile<Accessory: View, Content: View>: View {
    let label: String
    let icon: String
    let color: Color
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconTile(icon, color: color, size: 24)
                SectionLabel(label)
                Spacer(minLength: 6)
                accessory()
            }
            .frame(height: 24)
            VStack(alignment: .leading, spacing: 6, content: content)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: MonitorLayout.tileHeight,
               maxHeight: MonitorLayout.tileHeight, alignment: .topLeading)
        .panel()
    }
}

extension Tile where Accessory == EmptyView {
    init(label: String, icon: String, color: Color, @ViewBuilder content: @escaping () -> Content) {
        self.init(label: label, icon: icon, color: color, accessory: { EmptyView() }, content: content)
    }
}

/// The tile's big number, with an optional leading arrow and a quiet unit.
private struct BigValue: View {
    let text: String
    var unit: String?
    var icon: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(text)
                .font(.display(22))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            if let unit {
                Text(unit)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .lineLimit(1)
    }
}

private struct Caption: View {
    let text: String
    var icon: String?

    init(_ text: String, icon: String? = nil) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).monospacedDigit()
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
    }
}

/// The kit `Sparkline` on a fixed three-minute window: samples enter from the
/// right, and the part with no samples yet stays empty instead of stretching.
private struct History: View {
    let values: [Double]
    let color: Color
    var ceiling: Double?

    var body: some View {
        GeometryReader { geo in
            let share = CGFloat(max(values.count - 1, 0)) / CGFloat(MonitorStore.historyLength - 1)
            Sparkline(values: values, color: color, ceiling: ceiling)
                .frame(width: geo.size.width * min(share, 1))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: MonitorLayout.chartHeight)
        .overlay(alignment: .bottom) { Rule() }
    }
}

// MARK: - Tiles

private struct CPUTile: View {
    @EnvironmentObject var monitor: MonitorStore

    var body: some View {
        Tile(label: "CPU", icon: "cpu", color: Theme.amber) {
            BigValue(text: Format.percent(monitor.cpu))
            History(values: monitor.cpuHistory, color: Theme.amber,
                    ceiling: MonitorLayout.shareCeiling(monitor.cpuHistory))
            Caption("\(monitor.cores) cores · load \(MonitorText.load(monitor.load))")
        }
    }
}

private struct GPUTile: View {
    @EnvironmentObject var monitor: MonitorStore

    var body: some View {
        Tile(label: "GPU", icon: "gauge.with.needle", color: Theme.violet) {
            BigValue(text: monitor.gpu.map(Format.percent) ?? "–")
            History(values: monitor.gpuHistory, color: Theme.violet,
                    ceiling: MonitorLayout.shareCeiling(monitor.gpuHistory))
            Caption(monitor.gpu == nil ? "Not reported by this Mac" : "Device utilisation")
        }
    }
}

private struct MemoryTile: View {
    @EnvironmentObject var monitor: MonitorStore

    private var color: Color {
        switch monitor.pressure {
        case .normal: return Theme.blue
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

    private var swap: String {
        monitor.swapUsed > 0 ? "swap \(Format.memory(monitor.swapUsed))" : "no swap"
    }

    var body: some View {
        Tile(label: "Memory", icon: "memorychip", color: color) {
            if monitor.pressure != .normal { Badge(pressureWord, color: color) }
        } content: {
            BigValue(text: Format.memory(monitor.memUsed),
                     unit: "of \(Format.memory(monitor.memTotal))")
            History(values: monitor.memHistory, color: color, ceiling: 1)
            Caption("Pressure \(pressureWord) · \(swap)")
        }
    }
}

private struct DiskTile: View {
    let free: Int64
    let total: Int64

    private var used: Double { total > 0 ? 1 - Double(free) / Double(total) : 0 }
    private var isFull: Bool { 1 - used < MonitorLayout.lowDisk }
    private var color: Color { isFull ? Theme.red : used > 0.8 ? Theme.amber : Theme.green }

    var body: some View {
        Tile(label: "Disk", icon: "internaldrive", color: color) {
            if isFull { Badge("Full", color: Theme.red, icon: "exclamationmark.triangle") }
        } content: {
            BigValue(text: Format.bytes(free), unit: "free")
            Meter(value: used, color: color, height: 5).padding(.vertical, 3)
            Caption("\(Format.bytes(total - free)) used · \(Format.percent(used))")
        }
    }
}

private struct NetworkTile: View {
    @EnvironmentObject var monitor: MonitorStore

    /// Keeps an idle line flat instead of magnifying a few bytes of chatter.
    private var ceiling: Double { max(monitor.netDownHistory.max() ?? 0, 100_000) }

    var body: some View {
        Tile(label: "Network", icon: "wifi", color: Theme.accent) {
            BigValue(text: Format.rate(monitor.netDown), icon: "arrow.down")
            History(values: monitor.netDownHistory, color: Theme.accent, ceiling: ceiling)
            Caption("\(Format.rate(monitor.netUp)) up", icon: "arrow.up")
        }
    }
}

private struct BatteryTile: View {
    @EnvironmentObject var monitor: MonitorStore

    var body: some View {
        if let battery = monitor.battery {
            let color = !battery.onBattery || battery.percent > 20 ? Theme.green
                : battery.percent > 10 ? Theme.amber : Theme.red
            Tile(label: "Battery", icon: battery.isCharging ? "battery.100.bolt" : "battery.100",
                 color: color) {
                BigValue(text: "\(battery.percent)%")
                Meter(value: Double(battery.percent) / 100, color: color, height: 5).padding(.vertical, 3)
                Caption(caption(battery))
            }
        } else {
            Tile(label: "Battery", icon: "powerplug", color: Theme.gray) {
                BigValue(text: "No battery")
                Caption("This Mac runs on mains power.")
            }
        }
    }

    private func caption(_ battery: MonitorStore.Battery) -> String {
        let source = battery.isCharging ? "Charging" : battery.onBattery ? "On battery" : "Plugged in"
        return battery.cycles.map { "\(source) · \($0) cycles" } ?? source
    }
}

private struct UptimeTile: View {
    @EnvironmentObject var monitor: MonitorStore

    var body: some View {
        Tile(label: "Uptime", icon: "clock", color: Theme.gray) {
            BigValue(text: MonitorText.uptime(monitor.uptime))
            if let boot = monitor.bootTime {
                Caption("Since \(boot.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
            }
        }
    }
}

private struct SpeedTestTile: View {
    @EnvironmentObject var monitor: MonitorStore

    var body: some View {
        Tile(label: "Speed test", icon: "bolt", color: Theme.magenta) {
            switch monitor.speedTest {
            case .idle:
                BigValue(text: "–")
                Caption("Cloudflare · about 6 seconds")
            case .running:
                BusyLabel(text: "Measuring your download speed…").frame(height: 27)
                Caption("Cloudflare · about 6 seconds")
            case .done(let mbps):
                BigValue(text: MonitorText.mbps(mbps), unit: "Mbps down")
                Caption("Measured against Cloudflare")
            case .failed:
                BigValue(text: "–")
                Caption("Could not reach Cloudflare. Try again.")
            }
        }
        .overlay(alignment: .topTrailing) {
            // Only this button starts a test; nothing runs it on a timer.
            KitButton(monitor.speedTest == .idle ? "Run" : "Run again") { monitor.runSpeedTest() }
                .disabled(monitor.speedTest == .running)
                .padding(.top, 8)
                .padding(.trailing, 10)
        }
    }
}

// MARK: - Low disk

private struct LowDiskBanner: View {
    let scan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            (Text("You are low on disk space. ").fontWeight(.bold)
                + Text("Clearing caches, logs and other clutter frees room in a few minutes."))
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            KitButton("Scan for clutter", action: scan)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 7)
        .panel(fill: Theme.amber.opacity(0.16))
    }
}

// MARK: - Apps and processes

private enum ProcessSort: Hashable { case cpu, memory }

private struct ProcessPanel: View {
    @EnvironmentObject var monitor: MonitorStore
    @Binding var sort: ProcessSort

    private var rows: [MonitorStore.ProcessGroup] {
        let sorted = monitor.processes.sorted { a, b in
            switch sort {
            case .cpu: return a.cpu != b.cpu ? a.cpu > b.cpu : a.name < b.name
            case .memory: return a.memory != b.memory ? a.memory > b.memory : a.name < b.name
            }
        }
        return Array(sorted.prefix(MonitorLayout.rowCount))
    }

    var body: some View {
        let rows = rows
        // One whole core is the least a full CPU bar can stand for.
        let cpuScale = max(rows.map(\.cpu).max() ?? 0, 100)
        let memoryScale = Double(max(rows.map(\.memory).max() ?? 1, 1))

        VStack(spacing: 0) {
            HStack {
                SectionLabel("Apps and processes · Top \(MonitorLayout.rowCount)")
                Spacer()
                Segmented(selection: $sort, options: [.init(.cpu, "By CPU"), .init(.memory, "By memory")])
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            Rule()
            ProcessColumns {
                SectionLabel("Name").padding(.leading, 38)
            } cpu: {
                SectionLabel("CPU")
            } memory: {
                SectionLabel("Memory")
            }
            .frame(height: 26)
            Rule()
            if rows.isEmpty {
                BusyLabel(text: monitor.paused ? "Paused" : "Reading processes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            ProcessRow(row: row, cpuScale: cpuScale, memoryScale: memoryScale)
                            if row.id != rows.last?.id { Rule() }
                        }
                    }
                }
            }
            Rule()
            Text("macOS keeps free memory busy with caches, so high memory use is normal; memory pressure is the number that matters.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }
}

/// The table's three columns, shared by the header and every row.
private struct ProcessColumns<Name: View, CPU: View, Memory: View>: View {
    @ViewBuilder var name: () -> Name
    @ViewBuilder var cpu: () -> CPU
    @ViewBuilder var memory: () -> Memory

    var body: some View {
        HStack(spacing: 20) {
            name().frame(maxWidth: .infinity, alignment: .leading)
            cpu().frame(width: MonitorLayout.cpuColumn, alignment: .leading)
            memory().frame(width: MonitorLayout.memoryColumn, alignment: .leading)
        }
        .padding(.horizontal, 18)
    }
}

private struct ProcessRow: View {
    let row: MonitorStore.ProcessGroup
    let cpuScale: Double
    let memoryScale: Double

    var body: some View {
        ProcessColumns {
            HStack(spacing: 12) {
                if let path = row.appPath {
                    Image(nsImage: AppIcons.icon(forApp: path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 26, height: 26)
                } else {
                    IconTile("terminal", color: Theme.gray, size: 26)
                }
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(row.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    if row.count > 1 {
                        Text("×\(row.count)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if row.appPath == nil {
                        Text("Command-line process")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .lineLimit(1)
            }
        } cpu: {
            bar(row.cpu / cpuScale, color: row.cpu >= 50 ? Theme.amber : Theme.accent,
                text: MonitorText.cores(row.cpu))
        } memory: {
            bar(Double(row.memory) / memoryScale, color: Theme.blue, text: Format.memory(row.memory))
        }
        .frame(height: 38)
    }

    private func bar(_ value: Double, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Meter(value: value, color: color).frame(width: MonitorLayout.barWidth)
            Text(text)
                .font(.system(size: 13.5))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
    }
}

/// App icons by bundle path, fetched once.
@MainActor
private enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(forApp path: String) -> NSImage {
        if let icon = cache[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}
