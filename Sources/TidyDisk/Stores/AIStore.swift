import AppKit
import Foundation

/// What AI tools cost this Mac: disk, memory, local servers.
///
/// Disk is scanned on request (`scanDisk()`). Live readings (processes, MCP
/// servers, ports) are sampled only between `startLive()` and `stopLive()`,
/// or once per `refreshLive()` call, so the store costs nothing while no
/// screen shows it.
@MainActor
final class AIStore: ObservableObject {
    // MARK: - Summary (read by Overview)

    /// Models + caches + app data of every detected AI tool.
    @Published var diskBytes: Int64 = 0
    /// Names of the tools with data on disk, largest first.
    @Published var diskToolNames: [String] = []
    @Published var diskScanned = false
    @Published var diskScanning = false
    /// Memory held by running AI apps right now.
    @Published var memoryBytes: Int64 = 0
    @Published var runningNames: [String] = []
    /// "Ollama :11434" style labels of local AI servers that are listening.
    @Published var serverLabels: [String] = []

    // MARK: - Detail (the AI tab)

    /// Tools with data on disk, largest first.
    @Published private(set) var tools: [AIToolUsage] = []
    /// When the disk was last scanned; remembered between launches.
    @Published private(set) var diskScannedAt: Date?
    /// Installed tools whose protected folders were skipped (no Full Disk Access).
    @Published private(set) var needsAccess: [String] = []
    /// Tools first, then MCP servers.
    @Published private(set) var groups: [AIProcessGroup] = []
    /// Everything listening on a TCP port, AI servers first.
    @Published private(set) var servers: [AIServer] = []
    /// Percent of one core, summed across AI processes.
    @Published private(set) var cpuPercent: Double = 0
    /// False until the first live sample has landed.
    @Published private(set) var liveSampled = false
    /// Ids of the ticked `AIItem`s.
    @Published private(set) var selection: Set<String> = []
    @Published private(set) var trashing = false
    /// Set when a trash run could not move everything; the tab shows it once.
    @Published var trashFailure: String?

    private static let scannedAtKey = "aiDiskScannedAt"
    private let sampler = AILiveSampler()
    private var timer: Timer?
    private var sampling = false

    init() {
        diskScannedAt = UserDefaults.standard.object(forKey: Self.scannedAtKey) as? Date
    }

    // MARK: - Disk

    func scanDisk() {
        guard !diskScanning else { return }
        diskScanning = true
        let home = Self.home
        Task.detached(priority: .userInitiated) {
            let scan = AICatalog.scan(home: home, fullDiskAccess: Engine.hasFullDiskAccess())
            await MainActor.run { self.apply(scan) }
        }
    }

    private func apply(_ scan: AIDiskScan) {
        tools = scan.tools
        needsAccess = scan.needsAccess
        diskBytes = scan.tools.reduce(0) { $0 + $1.bytes }
        diskToolNames = scan.tools.map(\.tool.name)
        diskScannedAt = Date()
        UserDefaults.standard.set(diskScannedAt, forKey: Self.scannedAtKey)
        selection.formIntersection(allItems.map(\.id))
        diskScanned = true
        diskScanning = false
        if Self.debug.contains("dump") { print(diskReport()) }
    }

    func bytes(of kind: AIKind) -> Int64 {
        tools.reduce(0) { $0 + $1.bytes(of: kind) }
    }

    private var allItems: [AIItem] { tools.flatMap(\.items) }

    // MARK: - Live

    /// One immediate sample of processes and ports.
    func refreshLive() {
        guard !sampling else { return }
        sampling = true
        let sampler = sampler
        Task.detached(priority: .utility) {
            let sample = sampler.sample()
            await MainActor.run {
                self.apply(sample)
                self.sampling = false
            }
        }
    }

    /// Samples now and then every 3 s until `stopLive()`. The AI tab calls
    /// these from onAppear / onDisappear; nothing else keeps the timer alive.
    func startLive() {
        guard timer == nil else { return }
        refreshLive()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // A window nobody can see does not need fresh numbers.
                guard NSApp.occlusionState.contains(.visible) else { return }
                self?.refreshLive()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopLive() {
        timer?.invalidate()
        timer = nil
    }

    private func apply(_ sample: AILiveSample) {
        let firstSample = !liveSampled
        groups = sample.groups
        servers = sample.servers
        memoryBytes = sample.memory
        cpuPercent = sample.cpu
        runningNames = sample.groups.filter { $0.role == .tool }.map(\.title)
        serverLabels = sample.servers.filter(\.isAI).map { "\($0.label) :\($0.port)" }
        liveSampled = true
        if firstSample, Self.debug.contains("dump") { print(liveReport()) }
    }

    func isRunning(_ tool: AITool) -> Bool {
        groups.contains { $0.role == .tool && $0.toolID == tool.id }
    }

    // MARK: - Selection

    var selectedItems: [AIItem] { allItems.filter { selection.contains($0.id) } }

    /// What trashing the ticked items frees (an Ollama blob another model needs stays).
    var selectedBytes: Int64 { AICatalog.freedBytes(selected: selectedItems, among: allItems) }

    /// Models downloaded more than 90 days ago. Never caches, never app data.
    var staleModels: [AIItem] {
        let cutoff = Date().addingTimeInterval(-AICatalog.staleAfter)
        return allItems.filter { $0.kind == .models && ($0.date ?? .distantFuture) < cutoff }
    }

    func isSelected(_ item: AIItem) -> Bool { selection.contains(item.id) }

    func toggle(_ item: AIItem) {
        if !selection.insert(item.id).inserted { selection.remove(item.id) }
    }

    /// Off, on (every item ticked) or mixed.
    func mark(of usage: AIToolUsage) -> CheckBox.Mark {
        let ticked = usage.items.filter { selection.contains($0.id) }.count
        return ticked == 0 ? .off : ticked == usage.items.count ? .on : .mixed
    }

    /// The items a tool's own tick box covers: models and caches. App data
    /// holds chat history, so it is only ever ticked on its own row.
    func bulkItems(of usage: AIToolUsage) -> [AIItem] {
        usage.items.filter { $0.kind != .appData }
    }

    func toggle(_ usage: AIToolUsage) {
        let bulk = bulkItems(of: usage).map(\.id)
        if mark(of: usage) != .off, selection.isSuperset(of: bulk) {
            selection.subtract(usage.items.map(\.id))
        } else {
            selection.formUnion(bulk)
        }
    }

    func selectStaleModels() {
        selection.formUnion(staleModels.map(\.id))
    }

    func clearSelection() {
        selection.removeAll()
    }

    // MARK: - Trash

    /// The text of the confirmation alert for the current selection.
    var trashWarning: String {
        let items = selectedItems
        let owners = tools.filter { usage in usage.items.contains { selection.contains($0.id) } }
        var text = "This moves \(Format.bytes(selectedBytes)) from \(Self.list(owners.map(\.tool.name))) to the Trash. "
            + "You can put it back until the Trash is emptied."
        let appData = items.filter { $0.kind == .appData }.count
        if appData > 0 {
            text += "\n\n\(appData) of \(items.count) \(appData == 1 ? "is" : "are") app data, which holds "
                + "your chat history, sessions and settings. Those do not come back by themselves."
        }
        let running = owners.map(\.tool).filter(isRunning).map(\.name)
        if !running.isEmpty {
            text += "\n\n\(Self.list(running)) \(running.count == 1 ? "is" : "are") running. "
                + "Quit \(running.count == 1 ? "it" : "them") first, or the files may be written again."
        }
        return text
    }

    /// Dry run: exactly the paths `trashSelected()` would trash, and nothing touched.
    func trashPlan() -> [String] {
        Self.plan(for: selectedItems, home: Self.home)
    }

    private nonisolated static func plan(for items: [AIItem], home: String) -> [String] {
        AICatalog.trashPlan(for: items).filter { AICatalog.isSafeToTrash($0, home: home) }
    }

    /// Moves the ticked items to the Trash, then rescans. The tab asks first.
    func trashSelected() {
        let items = selectedItems
        guard !items.isEmpty, !trashing else { return }
        trashing = true
        let home = Self.home
        Task.detached(priority: .userInitiated) {
            let result = Self.moveToTrash(Self.plan(for: items, home: home))
            await MainActor.run { self.finishTrash(of: items.count, result) }
        }
    }

    /// The only place this store removes anything. Returns the bytes moved and one log line per path.
    private nonisolated static func moveToTrash(_ plan: [String]) -> (freed: Int64, lines: [String]) {
        var freed: Int64 = 0
        var lines: [String] = []
        for path in plan {
            let bytes = Engine.size(of: [path])
            let line = Engine.trashFile(path)
            if line.hasPrefix("[trash]") { freed += bytes }
            lines.append(line)
        }
        return (freed, lines)
    }

    private func finishTrash(of count: Int, _ result: (freed: Int64, lines: [String])) {
        ActivityLog.shared.add("[trash] AI usage: \(count) \(count == 1 ? "item" : "items"), "
            + "\(Format.bytes(result.freed)) moved to Trash")
        result.lines.forEach(ActivityLog.shared.add)
        Engine.reportFreed(result.freed)
        let failed = result.lines.filter { $0.hasPrefix("[fail]") }.count
        if failed > 0 {
            trashFailure = "\(failed) of \(result.lines.count) could not be moved to the Trash. The Log lists each one."
        }
        selection.removeAll()
        trashing = false
        scanDisk()
    }

    private static func list(_ names: [String]) -> String {
        ListFormatter.localizedString(byJoining: names)
    }

    // MARK: - Development hooks

    /// `TIDYDISK_AI_HOME=/path` scans a fixture folder in place of the home folder.
    private static let home = ProcessInfo.processInfo.environment["TIDYDISK_AI_HOME"] ?? NSHomeDirectory()

    /// `TIDYDISK_AI_DEBUG=dump,expand,select`: print the scan, the live sample and
    /// the dry-run trash plans; open every tool; tick the stale models. For `--shot`.
    static let debug = Set((ProcessInfo.processInfo.environment["TIDYDISK_AI_DEBUG"] ?? "")
        .split(separator: ",").map(String.init))

    private func diskReport() -> String {
        var lines = ["== AI disk scan: \(Format.bytes(diskBytes)) (\(diskBytes) bytes) =="]
        for usage in tools {
            lines.append("\(usage.tool.name)  \(Format.bytes(usage.bytes))  shared \(usage.sharedBytes)")
            for item in usage.items {
                let plan = Self.plan(for: [item], home: Self.home)
                lines.append("  [\(item.kind.label)] \(item.name)  \(Format.bytes(item.bytes))  "
                    + "\(item.files) files  \(item.date.map { "\($0)" } ?? "-")")
                lines.append("      alone would trash \(plan.count): "
                    + plan.prefix(4).map(Engine.abbreviate).joined(separator: " | ")
                    + (plan.count > 4 ? " | …" : ""))
            }
        }
        lines.append("needs Full Disk Access: \(needsAccess)")
        for (title, items) in [("models older than 90 days", staleModels),
                               ("every model and cache", allItems.filter { $0.kind != .appData })] {
            let plan = Self.plan(for: items, home: Self.home)
            lines.append("== Dry run, \(title): \(items.count) items, "
                + "\(Format.bytes(AICatalog.freedBytes(selected: items, among: allItems))), \(plan.count) paths ==")
            lines += plan.map { "  would trash " + Engine.abbreviate($0) }
        }
        return lines.joined(separator: "\n")
    }

    private func liveReport() -> String {
        var lines = ["== AI live sample: \(Format.bytes(memoryBytes)), \(Int(cpuPercent))% CPU =="]
        lines += groups.map {
            "  \($0.role == .mcp ? "MCP " : "tool") \($0.title) ×\($0.count)  \(Int($0.cpu))%  "
                + "\(Format.bytes($0.memory))  [\($0.detail)]"
        }
        lines += servers.map { "  :\($0.port) \($0.process) \($0.label) \($0.bind) ai=\($0.isAI)" }
        return lines.joined(separator: "\n")
    }
}
