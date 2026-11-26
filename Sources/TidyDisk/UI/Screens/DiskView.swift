import SwiftUI
import AppKit

/// Where the space goes: by location, as a map, folder by folder, and by file type.
struct DiskView: View {
    enum Mode: String, Hashable { case overview, map, folders, types }

    @EnvironmentObject var state: AppState
    @EnvironmentObject var disk: DiskStore
    @State private var mode: Mode = Snapshot.value(after: "--disk-mode").flatMap(Mode.init) ?? .overview
    /// Folders opened so far in Map / Folders (empty = the measured top level).
    @State private var trail: [FolderNode] = []

    private var used: Int64 { max(0, state.totalSpace - state.freeSpace) }

    private var subtitle: String {
        guard let index = disk.index else { return "See what is taking the space on this Mac" }
        return "\(Format.bytes(used)) used of \(Format.bytes(state.totalSpace)) · "
            + "\(Format.count(index.totalFiles)) files · measured \(Format.ago(index.date)) "
            + "in \(String(format: "%.1f", index.duration)) s"
    }

    var body: some View {
        Page(icon: AppTab.disk.icon, title: "Disk", subtitle: subtitle) {
            if disk.index != nil {
                Segmented(selection: $mode, options: [
                    .init(.overview, "Overview", icon: "square.grid.2x2"),
                    .init(.map, "Map", icon: "rectangle.split.2x2"),
                    .init(.folders, "Folders", icon: "folder"),
                    .init(.types, "File types", icon: "doc"),
                ])
            }
            if disk.measuring { BusyLabel(text: "Measuring…") }
            KitButton(disk.index == nil ? "Measure this disk" : "Measure again", icon: "arrow.triangle.2.circlepath",
                      kind: disk.index == nil ? .primary : .secondary) { disk.measure() }
                .disabled(disk.measuring)
        } content: {
            if let index = disk.index {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    switch mode {
                    case .overview: DiskOverview(index: index, shares: shares(of: index))
                    case .map: FolderBrowser(index: index, trail: $trail, asMap: true)
                    case .folders: FolderBrowser(index: index, trail: $trail, asMap: false)
                    case .types: FileTypes(index: index)
                    }
                    AccessNote(index: index)
                }
            } else {
                EmptyState(icon: AppTab.disk.icon,
                           title: disk.measuring ? "Measuring the disk…" : "Not measured yet",
                           message: "One pass over your home folder, apps and shared folders. It reads sizes only and takes a few seconds.",
                           actionTitle: disk.measuring ? nil : "Measure this disk") { disk.measure() }
                    .panel()
            }
        }
        .onChange(of: disk.index?.date) { trail = [] }
    }

    /// The measured kinds plus what the pass could not see, plus free space.
    private func shares(of index: DiskIndex) -> [DiskShare] {
        var list = DiskKind.allCases.map { kind in
            DiskShare(id: kind.title, title: kind.title, color: kind.color, bytes: index.stat(kind).bytes,
                      detail: "\(kind.detail) · \(Format.count(index.stat(kind).files)) files")
        }
        list.append(DiskShare(id: "system", title: "System & not scanned",
                              color: Color.white.opacity(0.28), bytes: max(0, used - index.measuredBytes),
                              detail: "macOS, snapshots, other users and folders not measured"))
        list.append(DiskShare(id: "free", title: "Free", color: Theme.track, bytes: state.freeSpace,
                              detail: "Available space"))
        return list
    }
}

/// One slice of the disk on the Overview mode.
private struct DiskShare: Identifiable {
    let id: String
    let title: String
    let color: Color
    let bytes: Int64
    let detail: String
}

extension DiskKind {
    var color: Color {
        switch self {
        case .media: return Theme.blue
        case .apps: return Theme.pink
        case .documents: return Theme.green
        case .downloads: return Theme.teal
        case .caches: return Theme.amber
        case .developer: return Theme.accent
        case .mail: return Theme.gold
        case .other: return Theme.gray
        }
    }
}

extension FileGroup {
    var color: Color {
        switch self {
        case .video: return Theme.blue
        case .images: return Theme.teal
        case .audio: return Theme.pink
        case .archives: return Theme.amber
        case .diskImages: return Theme.gold
        case .documents: return Theme.green
        case .code: return Theme.accent
        case .binaries: return Theme.violet
        case .data: return Theme.red
        case .models: return Theme.magenta
        case .other: return Theme.gray
        }
    }
}

// MARK: - Overview mode

private struct DiskOverview: View {
    @EnvironmentObject var state: AppState
    let index: DiskIndex
    let shares: [DiskShare]

    private var total: Double { Double(max(state.totalSpace, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StackedBar(segments: shares.map { .init(id: $0.id, color: $0.color, value: Double($0.bytes)) },
                       height: 18)
            Flow {
                ForEach(shares.filter { $0.bytes > 0 }) { share in
                    LegendItem(color: share.color, label: share.title, value: Format.bytes(share.bytes))
                }
            }
        }
        .padding(20)
        .panel()

        HStack(alignment: .top, spacing: Theme.gap) {
            VStack(spacing: 12) {
                SectionLabel("By kind")
                Spacer(minLength: 0)
                Donut(slices: shares.filter { $0.id != "free" }.map { ($0.color, Double($0.bytes)) },
                      total: total) {
                    VStack(spacing: 4) {
                        Text(Format.bytes(state.totalSpace - state.freeSpace)).font(.display(20))
                            .foregroundStyle(Theme.textPrimary)
                        Text("used · \(Format.percent(1 - Double(state.freeSpace) / total))")
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: 250, maxHeight: 250)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(width: 330)
            .frame(maxHeight: .infinity)
            .panel()

            VStack(spacing: 0) {
                HStack { SectionLabel("Categories"); Spacer() }
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                Rule()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shares.filter { $0.bytes > 0 }) { share in
                            ShareRow(color: share.color, title: share.title, detail: share.detail,
                                     bytes: share.bytes, fraction: Double(share.bytes) / total)
                            Rule()
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .panel()
        }
    }
}

/// Colour, name, detail, share bar, size and percent: one line of a breakdown.
private struct ShareRow: View {
    let color: Color
    let title: String
    let detail: String
    let bytes: Int64
    let fraction: Double

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Meter(value: fraction, color: color).frame(width: 150)
            Text(Format.bytes(bytes)).font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 92, alignment: .trailing)
            Text(fraction > 0 && fraction < 0.005 ? "<1%" : Format.percent(fraction))
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
    }
}

/// Ring chart with something in the middle.
private struct Donut<Center: View>: View {
    let slices: [(color: Color, value: Double)]
    let total: Double
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: 34)
            ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.start, to: max(arc.start, arc.end - 0.003))
                    .stroke(arc.color, style: StrokeStyle(lineWidth: 34, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            center()
        }
        .padding(17)
        .aspectRatio(1, contentMode: .fit)
    }

    private var arcs: [(color: Color, start: Double, end: Double)] {
        var cursor = 0.0
        return slices.filter { $0.value > 0 }.map { slice in
            let start = cursor
            cursor += slice.value / max(total, 1)
            return (slice.color, start, min(cursor, 1))
        }
    }
}

// MARK: - Map and Folders modes

/// Drill-down through folders, drawn as a list or as a treemap.
private struct FolderBrowser: View {
    @EnvironmentObject var disk: DiskStore
    let index: DiskIndex
    @Binding var trail: [FolderNode]
    let asMap: Bool

    private var nodes: [FolderNode]? {
        guard let current = trail.last else { return index.roots }
        return disk.children(of: current)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                crumb("This Mac", depth: 0)
                ForEach(Array(trail.enumerated()), id: \.element.id) { offset, node in
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                    crumb(node.name, depth: offset + 1)
                }
                Spacer()
                if let current = trail.last {
                    Text("\(Format.bytes(current.bytes)) · \(Format.count(current.files)) files")
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            Rule()
            if let nodes {
                if nodes.isEmpty {
                    EmptyState(icon: "folder", title: "Nothing to show",
                               message: "This folder is empty or macOS would not let TidyDisk read it.")
                } else if asMap {
                    Treemap(nodes: nodes, open: open).padding(10)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(nodes) { node in
                                FolderRow(node: node, largest: nodes.first?.bytes ?? 1) { open(node) }
                                Rule()
                            }
                        }
                    }
                }
            } else {
                BusyLabel(text: "Measuring this folder…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
        .panel()
    }

    private func crumb(_ title: String, depth: Int) -> some View {
        Button { trail = Array(trail.prefix(depth)) } label: {
            Text(title).font(.system(size: 13.5, weight: depth == trail.count ? .semibold : .regular))
                .foregroundStyle(depth == trail.count ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private func open(_ node: FolderNode) {
        guard node.isDirectory else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
            return
        }
        disk.loadChildren(of: node)
        trail.append(node)
    }
}

private struct FolderRow: View {
    let node: FolderNode
    let largest: Int64
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                    .font(.system(size: 15))
                    .foregroundStyle(node.isDirectory ? Theme.accent : Theme.textSecondary)
                    .frame(width: 22)
                Text(node.name).font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                if hovering {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)])
                    } label: {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }
                if node.isDirectory {
                    Text("\(Format.count(node.files)) files").font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 110, alignment: .trailing)
                }
                Meter(value: Double(node.bytes) / Double(max(largest, 1))).frame(width: 150)
                Text(Format.bytes(node.bytes)).font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 92, alignment: .trailing)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .opacity(node.isDirectory ? 1 : 0)
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(hovering ? Color.white.opacity(0.03) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Squarified treemap: every child is a tile whose area is its size.
private struct Treemap: View {
    let nodes: [FolderNode]
    let open: (FolderNode) -> Void

    private static let palette = [Theme.accent, Theme.blue, Theme.teal, Theme.green, Theme.amber,
                                  Theme.pink, Theme.violet, Theme.gold]

    /// The biggest children; a sliver too thin to click is not worth a tile.
    private var shown: [FolderNode] {
        let total = Double(max(nodes.reduce(0) { $0 + $1.bytes }, 1))
        return Array(nodes.filter { Double($0.bytes) / total > 0.002 }.prefix(60))
    }

    var body: some View {
        GeometryReader { geo in
            let items = shown
            let rects = Self.layout(items.map { Double($0.bytes) }, in: CGRect(origin: .zero, size: geo.size))
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, node in
                let rect = rects[offset].insetBy(dx: 1.5, dy: 1.5)
                Button { open(node) } label: {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Self.palette[offset % Self.palette.count].opacity(node.isDirectory ? 0.78 : 0.4))
                        .overlay(alignment: .topLeading) {
                            if rect.width > 70, rect.height > 38 {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(node.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                                    Text(Format.bytes(node.bytes)).font(.system(size: 11.5)).opacity(0.8)
                                }
                                .foregroundStyle(.black.opacity(0.85))
                                .padding(7)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("\(node.name) · \(Format.bytes(node.bytes))")
                .frame(width: max(rect.width, 0), height: max(rect.height, 0))
                .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    /// `values` sorted largest first; returns one rectangle per value.
    static func layout(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return values.map { _ in .zero } }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = values.map { $0 * scale }
        var rects = [CGRect](repeating: .zero, count: values.count)
        var free = bounds
        var start = 0

        while start < areas.count {
            let side = Double(min(free.width, free.height))
            // Worst aspect ratio of a strip holding areas[start..<end] (sorted, so ends are max/min).
            func worst(_ sum: Double, _ end: Int) -> Double {
                let s2 = side * side, sum2 = sum * sum
                return max(s2 * areas[start] / sum2, sum2 / (s2 * max(areas[end - 1], 0.0001)))
            }
            var end = start + 1
            var sum = areas[start]
            while end < areas.count, worst(sum + areas[end], end + 1) <= worst(sum, end) {
                sum += areas[end]
                end += 1
            }
            let thickness = CGFloat(sum / max(side, 0.0001))
            var offset: CGFloat = 0
            let vertical = free.width >= free.height
            for i in start..<end {
                let length = CGFloat(areas[i]) / max(thickness, 0.0001)
                rects[i] = vertical
                    ? CGRect(x: free.minX, y: free.minY + offset, width: thickness, height: length)
                    : CGRect(x: free.minX + offset, y: free.minY, width: length, height: thickness)
                offset += length
            }
            free = vertical
                ? CGRect(x: free.minX + thickness, y: free.minY, width: free.width - thickness, height: free.height)
                : CGRect(x: free.minX, y: free.minY + thickness, width: free.width, height: free.height - thickness)
            start = end
        }
        return rects
    }
}

// MARK: - File types mode

private struct FileTypes: View {
    let index: DiskIndex

    private var groups: [FileGroup] {
        FileGroup.allCases.filter { index.stat($0).bytes > 0 }
            .sorted { index.stat($0).bytes > index.stat($1).bytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { SectionLabel("By file type"); Spacer() }
                .padding(.horizontal, 18)
                .frame(height: 44)
            Rule()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groups) { group in
                        ShareRow(color: group.color, title: group.title, detail: detail(of: group),
                                 bytes: index.stat(group).bytes,
                                 fraction: Double(index.stat(group).bytes) / Double(max(index.measuredBytes, 1)))
                        Rule()
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .panel()
    }

    private func detail(of group: FileGroup) -> String {
        let top = index.topExtensions(in: group)
            .map { ".\($0.name) \(Format.bytes($0.stat.bytes))" }
            .joined(separator: " · ")
        let files = "\(Format.count(index.stat(group).files)) files"
        return top.isEmpty ? files : "\(files) · \(top)"
    }
}

// MARK: - Footnote

/// Says what was left out and how to include it.
private struct AccessNote: View {
    let index: DiskIndex

    var body: some View {
        if !index.skipped.isEmpty || !index.denied.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(Theme.textTertiary)
                Text(text).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
                if !Engine.hasFullDiskAccess() {
                    Button("Grant Full Disk Access") { Engine.openFullDiskAccessSettings() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .fontWeight(.semibold)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
        }
    }

    private var text: String {
        let folders = (index.skipped + index.denied).map(Engine.abbreviate)
        let shown = folders.prefix(2).joined(separator: ", ")
        let more = folders.count > 2 ? " and \(folders.count - 2) more protected folders" : ""
        return "Not measured: \(shown)\(more). Their space is in “System & not scanned”."
    }
}
