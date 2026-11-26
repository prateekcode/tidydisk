import SwiftUI
import AppKit

// MARK: - AI usage

/// What AI tools cost this Mac: disk on the left, live processes and local
/// servers on the right. Live readings run only while this view is on screen.
struct AIView: View {
    @EnvironmentObject var ai: AIStore
    @EnvironmentObject var monitor: MonitorStore

    private enum RunningFilter { case all, tools, mcp }

    @State private var expanded: Set<String> = []
    @State private var filter = RunningFilter.all
    @State private var query = ""
    @State private var confirming = false

    private var subtitle: String {
        var text = "What AI tools cost this Mac"
        if ai.diskScanning {
            text += " · scanning disk"
        } else if ai.diskScanned, let date = ai.diskScannedAt {
            text += " · disk scanned \(Format.ago(date))"
        }
        return text
    }

    var body: some View {
        Page(icon: AppTab.ai.icon, title: "AI usage", subtitle: subtitle) {
            if ai.diskScanning { BusyLabel(text: "Scanning disk…") }
            KitButton("Rescan disk", icon: "arrow.clockwise") { ai.scanDisk() }
                .disabled(ai.diskScanning || ai.trashing)
        } content: {
            VStack(spacing: Theme.gap) {
                tiles
                GeometryReader { geo in
                    let side = max(360, (geo.size.width - Theme.gap) * 0.4)
                    HStack(alignment: .top, spacing: Theme.gap) {
                        diskPanel.frame(width: max(0, geo.size.width - Theme.gap - side))
                        VStack(spacing: Theme.gap) {
                            runningPanel
                            serversPanel
                        }
                        .frame(width: side)
                    }
                }
            }
        }
        .onAppear {
            monitor.start()
            ai.startLive()
            if !ai.diskScanned { ai.scanDisk() }
        }
        .onDisappear {
            monitor.stop()
            ai.stopLive()
        }
        .onChange(of: ai.tools.map(\.id)) { _, ids in
            expanded.formIntersection(ids)
            if AIStore.debug.contains("expand") { expanded = Set(ids) }
            if AIStore.debug.contains("select") { ai.selectStaleModels() }
        }
        .alert("Move \(Self.count(ai.selection.count, "item")) to Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) { ai.trashSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ai.trashWarning)
        }
        .alert("Not everything was moved", isPresented: Binding(
            get: { ai.trashFailure != nil },
            set: { if !$0 { ai.trashFailure = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ai.trashFailure ?? "")
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        let apps = ai.groups.filter { $0.role == .tool }.count
        let aiServers = ai.servers.filter(\.isAI).count
        return HStack(spacing: Theme.gap) {
            StatTile(label: "On disk", icon: "internaldrive", color: Theme.accent,
                   value: ai.diskScanned ? Format.bytes(ai.diskBytes) : "—", detail: diskCaption, detailLines: 2)
            StatTile(label: "Memory now", icon: "memorychip", color: Theme.blue,
                   value: ai.liveSampled ? Format.bytes(ai.memoryBytes) : "—",
                   detail: apps == 0 ? "No AI apps running" : "\(Self.count(apps, "AI app")) running", detailLines: 2)
            StatTile(label: "CPU now", icon: "cpu", color: Theme.amber,
                   value: ai.liveSampled ? "\(Int(ai.cpuPercent.rounded()))%" : "—",
                   detail: "Summed across AI processes", detailLines: 2)
            StatTile(label: "GPU", icon: "gauge.with.needle", color: Theme.violet,
                   value: monitor.gpu.map(Format.percent) ?? "—",
                   detail: "Whole system, from the driver", meter: monitor.gpu ?? 0, detailLines: 2)
            StatTile(label: "Local servers", icon: "dot.radiowaves.left.and.right", color: Theme.green,
                   value: ai.liveSampled ? "\(ai.servers.count)" : "—",
                   detail: aiServers == 0 ? "No AI servers listening"
                       : "\(Self.count(aiServers, "AI server")) listening", detailLines: 2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var diskCaption: String {
        guard ai.diskScanned else { return "Sizing models, caches and app data" }
        let parts = AIKind.allCases.filter { ai.bytes(of: $0) > 0 }
            .map { "\(Format.bytes(ai.bytes(of: $0))) \($0.label)" }
        return parts.isEmpty ? "No AI tools found" : parts.joined(separator: " · ")
    }

    // MARK: On disk

    private var allExpanded: Bool { !ai.tools.isEmpty && expanded.count == ai.tools.count }

    private var diskPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                SectionLabel("On disk", icon: "internaldrive")
                Spacer(minLength: 8)
                if !ai.tools.isEmpty {
                    LinkButton(title: allExpanded ? "Collapse all" : "Expand all") {
                        withAnimation(.easeOut(duration: 0.15)) {
                            expanded = allExpanded ? [] : Set(ai.tools.map(\.id))
                        }
                    }
                    let stale = ai.staleModels
                    LinkButton(title: stale.isEmpty ? "Nothing older than 90 days"
                                   : "Select \(stale.count) older than 90 days",
                               icon: "clock.arrow.circlepath") {
                        ai.selectStaleModels()
                        expanded.formUnion(stale.map(\.toolID))
                    }
                    .disabled(stale.isEmpty)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            Rule()

            if ai.tools.isEmpty {
                EmptyState(icon: AppTab.ai.icon,
                           title: ai.diskScanned ? "No AI tools found" : "Sizing AI tools…",
                           message: "TidyDisk looks for the models, caches and app data of Ollama, LM Studio, Hugging Face, Claude, ChatGPT, Cursor and other AI tools.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(ai.tools) { usage in
                            let isOpen = expanded.contains(usage.id)
                            ToolRow(usage: usage, isOpen: isOpen) { open in
                                withAnimation(.easeOut(duration: 0.15)) {
                                    if open ?? !isOpen { expanded.insert(usage.id) } else { expanded.remove(usage.id) }
                                }
                            }
                            if isOpen {
                                ForEach(usage.items) { ItemRow(item: $0) }
                            }
                            Rule()
                        }
                    }
                }
                Rule()
                diskNote
                if !ai.selection.isEmpty {
                    Rule()
                    selectionBar
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }

    private var diskNote: some View {
        var note = "Caches are safe to clear. Models re-download when a tool needs them; app data holds your chat history and logs. A model's date is when it was downloaded; macOS does not record when it was last used."
        if !ai.needsAccess.isEmpty {
            note += " Not counted without Full Disk Access: sandboxed data of \(ListFormatter.localizedString(byJoining: ai.needsAccess))."
        }
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "info.circle")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionBar: some View {
        HStack(spacing: 14) {
            Text("\(ai.selection.count) selected · \(Format.bytes(ai.selectedBytes))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if ai.selectedItems.contains(where: { $0.kind == .appData }) {
                Badge("Includes app data", color: Theme.amber)
            }
            Spacer(minLength: 8)
            if ai.trashing {
                BusyLabel(text: "Moving to Trash…")
            } else {
                LinkButton(title: "Clear") { ai.clearSelection() }
            }
            KitButton("Move to Trash", icon: "trash", kind: .primary) { confirming = true }
                .disabled(ai.trashing || ai.diskScanning)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: Running now

    private var runningRows: [AIProcessGroup] {
        switch filter {
        case .all: return ai.groups
        case .tools: return ai.groups.filter { $0.role == .tool }
        case .mcp: return ai.groups.filter { $0.role == .mcp }
        }
    }

    private var runningPanel: some View {
        let mcp = ai.groups.filter { $0.role == .mcp }.count
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                SectionLabel("Running now", icon: "cpu")
                Spacer(minLength: 8)
                Segmented(selection: $filter, options: [
                    .init(.all, "All", count: ai.groups.count),
                    .init(.tools, "Tools", count: ai.groups.count - mcp),
                    .init(.mcp, "MCP", count: mcp),
                ])
            }
            .padding(.leading, 18)
            .padding(.trailing, 9)
            .frame(height: 48)
            Rule()

            if runningRows.isEmpty {
                PanelMessage(busy: !ai.liveSampled,
                             text: !ai.liveSampled ? "Reading processes…"
                                 : filter == .mcp ? "No MCP servers are running."
                                 : "No AI tools are running.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(runningRows) { group in
                            RunningRow(group: group)
                            Rule()
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }

    // MARK: Local servers

    private var serverRows: [AIServer] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return ai.servers }
        return ai.servers.filter {
            ":\($0.port) \($0.process) \($0.label)".lowercased().contains(needle)
        }
    }

    private var serversPanel: some View {
        let aiCount = ai.servers.filter(\.isAI).count
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                SectionLabel("Local servers", icon: "dot.radiowaves.left.and.right")
                Spacer(minLength: 8)
                if ai.liveSampled {
                    Text("\(aiCount) AI · \(ai.servers.count - aiCount) other")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            Rule()
            SearchField(text: $query, prompt: "Search port or process")
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            Rule()

            if serverRows.isEmpty {
                PanelMessage(busy: !ai.liveSampled,
                             text: !ai.liveSampled ? "Reading ports…"
                                 : ai.servers.isEmpty ? "Nothing is listening on a local port."
                                 : "No server matches the search.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(serverRows) { server in
                            ServerRow(server: server)
                            Rule()
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }

    // MARK: Wording

    /// "1 item", "3 items".
    static func count(_ value: Int, _ noun: String) -> String {
        "\(Format.count(value)) \(noun)\(value == 1 ? "" : "s")"
    }

    /// "today", "9 days ago", "8 months ago": a download date, coarser than `Format.ago`.
    static func age(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case ..<60: return "\(days) days ago"
        case ..<730: return "\(days / 30) months ago"
        default: return "\(days / 365) years ago"
        }
    }

    static func color(of kind: AIKind) -> Color {
        switch kind {
        case .models: return Theme.violet
        case .cache: return Theme.blue
        case .appData: return Theme.amber
        }
    }
}

// MARK: - Rows

/// A detected tool: tick box, icon, what it holds, size. Tapping opens its items.
private struct ToolRow: View {
    @EnvironmentObject var ai: AIStore
    let usage: AIToolUsage
    let isOpen: Bool
    /// nil toggles; true or false forces.
    let setOpen: (Bool?) -> Void

    @State private var hovering = false

    /// "3 items · 14.17 GB models", and shorter forms for a narrow row.
    private var summaries: [String] {
        let items = AIView.count(usage.items.count, "item")
        let kinds = AIKind.allCases.filter { usage.bytes(of: $0) > 0 }
            .map { "\(Format.bytes(usage.bytes(of: $0))) \($0.label)" }
        return [([items] + kinds).joined(separator: " · "), kinds.joined(separator: " · "), items]
    }

    var body: some View {
        // A tool's tick covers its models and caches. With only app data there
        // is nothing to tick in bulk, so the box opens the rows instead.
        let tickable = !ai.bulkItems(of: usage).isEmpty
        let mark = ai.mark(of: usage)
        HStack(spacing: 12) {
            Button {
                if tickable || mark != .off { ai.toggle(usage) } else { setOpen(true) }
            } label: {
                CheckBox(mark).opacity(tickable || mark != .off ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .help(tickable ? "Ticks this tool's models and caches. App data is ticked on its own row."
                : "This tool only has app data. Tick it on its own row.")

            ToolIcon(tool: usage.tool)
            Text(usage.tool.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            ViewThatFits(in: .horizontal) {
                ForEach(summaries, id: \.self) { Text($0).lineLimit(1) }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            if ai.isRunning(usage.tool) { Badge("Running", color: Theme.green) }
            Text(Format.bytes(usage.bytes))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .frame(width: 10)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(hovering ? Color.white.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { setOpen(nil) }
        .onHover { hovering = $0 }
    }
}

/// One model, cache or app-data folder under a tool.
private struct ItemRow: View {
    @EnvironmentObject var ai: AIStore
    let item: AIItem

    private var symbol: String {
        switch item.kind {
        case .models: return "cube"
        case .cache: return "arrow.triangle.2.circlepath"
        case .appData: return "text.bubble"
        }
    }

    /// "4 files · downloaded 9 days ago · "
    private var facts: String {
        var parts = [item.files >= AICatalog.fileCountCap
            ? "\(Format.count(item.files))+ files" : AIView.count(item.files, "file")]
        if let date = item.date { parts.append("downloaded \(AIView.age(date))") }
        return parts.joined(separator: " · ") + " · "
    }

    private var place: String {
        Engine.abbreviate(item.location) + (item.paths.count > 1 ? " and \(item.paths.count - 1) more" : "")
    }

    var body: some View {
        Button { ai.toggle(item) } label: {
            HStack(spacing: 12) {
                CheckBox(isOn: ai.isSelected(item))
                IconTile(symbol, color: AIView.color(of: item.kind), size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    // Only the path gives way when the row is narrow.
                    HStack(spacing: 0) {
                        Text(facts).fixedSize()
                        Text(place).lineLimit(1).truncationMode(.middle)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                Badge(item.kind.label, color: AIView.color(of: item.kind))
                Text(Format.bytes(item.bytes))
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize()
            }
            // The tick box lines up under the tool's icon, the size under the tool's size.
            .padding(.leading, 48)
            .padding(.trailing, 40)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.location)])
            }
        }
    }
}

/// A running tool, or an MCP server one of them started.
private struct RunningRow: View {
    let group: AIProcessGroup

    var body: some View {
        HStack(spacing: 12) {
            ToolIcon(tool: AICatalog.tool(group.toolID))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(group.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if group.count > 1 {
                        Text("×\(group.count)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize()
                    }
                    if group.role == .mcp { Badge("MCP", color: Theme.accent) }
                }
                Text(group.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text("\(Int(group.cpu.rounded()))%")
                .font(.system(size: 13.5))
                .monospacedDigit()
                .foregroundStyle(group.cpu >= 100 ? Theme.amber : Theme.textSecondary)
                .frame(width: 46, alignment: .trailing)
            Text(Format.bytes(group.memory))
                .font(.system(size: 13.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
    }
}

/// ":11434  ollama  Ollama" and how far the port is reachable.
private struct ServerRow: View {
    let server: AIServer

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: ":\(server.port)")
                .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(server.isAI ? Theme.violet : Theme.textSecondary)
                .frame(width: 58, alignment: .leading)
            Text(server.process)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(server.label)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            switch server.bind {
            case .local: Badge("Local", color: Theme.gray, icon: "lock")
            case .network: Badge("Network", color: Theme.amber, icon: "network")
            case .all: Badge("All interfaces", color: Theme.amber, icon: "globe")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

// MARK: - Pieces the kit does not have

private struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.textTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .panel(radius: 8, fill: Theme.raised)
    }
}

/// One quiet line filling an empty panel body.
private struct PanelMessage: View {
    let busy: Bool
    let text: String

    var body: some View {
        Group {
            if busy {
                BusyLabel(text: text)
            } else {
                Text(text).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
    }
}

/// The tool's real app icon when the app is installed, a symbol tile otherwise.
private struct ToolIcon: View {
    let tool: AITool?
    var size: CGFloat = 30

    private static var icons: [String: NSImage?] = [:]

    private var image: NSImage? {
        guard let tool else { return nil }
        if let known = Self.icons[tool.id] { return known }
        let icon = AICatalog.appPath(for: tool).map { NSWorkspace.shared.icon(forFile: $0) }
        Self.icons[tool.id] = icon
        return icon
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            IconTile(tool?.symbol ?? "server.rack", size: size)
        }
    }
}
