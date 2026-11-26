import SwiftUI
import AppKit

// MARK: - Applications

struct AppsView: View {
    @EnvironmentObject var store: AppsStore
    @State private var query = ""
    @State private var sort = AppSort.size

    var body: some View {
        // Keeps "scanned 4 min ago" honest while the tab stays open.
        TimelineView(.periodic(from: .now, by: 60)) { _ in page }
            .alert(store.confirmation?.title ?? "", isPresented: Binding(
                get: { store.confirmation != nil },
                set: { if !$0 { store.confirmation = nil } }
            ), presenting: store.confirmation) { request in
                Button("Move to Trash", role: .destructive) { store.perform(request) }
                Button("Cancel", role: .cancel) {}
            } message: { request in
                Text(request.message)
            }
            .alert(store.notice?.title ?? "", isPresented: Binding(
                get: { store.notice != nil },
                set: { if !$0 { store.notice = nil } }
            ), presenting: store.notice) { _ in
                Button("OK", role: .cancel) {}
            } message: { notice in
                Text(notice.message)
            }
            .task {
                // Snapshots cannot click "Scan apps".
                if CommandLine.arguments.contains("--shot"), !store.scanned { store.scan() }
            }
    }

    private var subtitle: String {
        guard !store.apps.isEmpty else {
            return "What every app really takes, counting its files in ~/Library"
        }
        var parts = ["\(AppsStore.plural(store.apps.count, "app"))",
                     "\(Format.bytes(store.totalBytes)) including their files in ~/Library"]
        if let scanned = store.lastScanned, !store.scanning { parts.append("scanned \(Format.ago(scanned))") }
        return parts.joined(separator: " · ")
    }

    private var page: some View {
        Page(icon: AppTab.apps.icon, title: "Applications", subtitle: subtitle) {
            if store.scanning {
                BusyLabel(text: store.found == 0 ? "Looking for apps…"
                          : "Sizing \(min(store.sized + 1, store.found)) of \(store.found)…")
            }
            KitButton(store.scanned ? "Scan again" : "Scan apps", icon: "arrow.clockwise",
                      kind: store.scanned ? .secondary : .primary) { store.scan() }
                .disabled(store.scanning || store.removing)
        } content: {
            if store.apps.isEmpty {
                EmptyState(icon: store.scanned ? "checkmark.seal" : AppTab.apps.icon,
                           title: store.scanning ? "Looking for apps…"
                               : store.scanned ? "No apps found" : "No apps scanned yet",
                           message: "TidyDisk sizes every app in Applications together with the files it keeps in ~/Library, and finds what uninstalled apps left behind.")
                    .panel()
            } else {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    if !store.leftovers.isEmpty { LeftoversPanel() }
                    AppListPanel(query: $query, sort: $sort)
                    if !store.fullDiskAccess { FullDiskAccessHint() }
                }
            }
        }
    }
}

private enum AppSort: Hashable {
    case size, name, updated
}

/// Shared column widths so the header row and the rows line up.
private enum AppColumns {
    static let inset: CGFloat = 18
    static let gap: CGFloat = 12
    static let icon: CGFloat = 30
    static let updated: CGFloat = 120
    static let size: CGFloat = 96
}

// MARK: - Leftovers

private struct LeftoversPanel: View {
    @EnvironmentObject var store: AppsStore

    private static let rowHeight: CGFloat = 38
    /// Three rows show; the rest scroll, so the app list keeps most of the window.
    private var listHeight: CGFloat { CGFloat(min(store.leftovers.count, 3)) * Self.rowHeight - 1 }

    private var allSelected: Bool { store.selectedLeftovers.count == store.leftovers.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                SectionLabel("Leftovers from uninstalled apps", icon: "shippingbox")
                Spacer(minLength: 12)
                Text("\(AppsStore.plural(store.leftovers.count, "app")) · \(Format.bytes(store.leftoverBytes))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Button { store.toggleAllLeftovers() } label: {
                    Text(allSelected ? "None" : "All")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(minWidth: 34, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(allSelected ? "Untick every leftover" : "Tick every leftover")
                KitButton("Trash", icon: "trash", kind: .primary) { store.requestTrashLeftovers() }
                    .disabled(store.selectedLeftovers.isEmpty || store.removing || store.scanning)
            }
            .padding(.horizontal, AppColumns.inset)
            .frame(height: 50)
            Rule()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.leftovers) { leftover in
                        LeftoverRow(leftover: leftover).frame(height: Self.rowHeight - 1)
                        Rule()
                    }
                }
            }
            .scrollIndicators(.visible)
            .frame(height: listHeight)
        }
        .panel()
    }
}

private struct LeftoverRow: View {
    @EnvironmentObject var store: AppsStore
    let leftover: AppLeftover
    @State private var hovering = false

    private var detail: String {
        var parts = ["\(AppsStore.plural(leftover.paths.count, "file")) left"]
        parts.append(leftover.lastSeen.map { "last seen installed \(Format.ago($0))" }
                     ?? "no matching app installed")
        if let first = leftover.paths.first {
            parts.append(Engine.abbreviate(first) + (leftover.paths.count > 1 ? ", …" : ""))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button { store.toggleLeftover(leftover) } label: {
            HStack(spacing: AppColumns.gap) {
                CheckBox(isOn: store.selectedLeftovers.contains(leftover.id))
                Text(leftover.name)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Text(Format.bytes(leftover.bytes))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize()
            }
            .padding(.horizontal, AppColumns.inset)
            .frame(maxHeight: .infinity)
            .background(hovering ? Color.white.opacity(0.03) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Show in Finder") { revealInFinder(leftover.paths) }
        }
    }
}

// MARK: - App list

private struct AppListPanel: View {
    @EnvironmentObject var store: AppsStore
    @Binding var query: String
    @Binding var sort: AppSort

    private var rows: [AppInfo] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = needle.isEmpty ? store.apps : store.apps.filter {
            $0.name.lowercased().contains(needle) || $0.bundleID.lowercased().contains(needle)
        }
        switch sort {
        case .size: return matches
        case .name: return matches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .updated: return matches.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
        }
    }

    var body: some View {
        let rows = rows
        let selectable = rows.filter { !$0.isProtected }.map(\.id)
        let ticked = selectable.filter { store.selectedApps.contains($0) }.count

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SearchField(text: $query, prompt: "Search apps").frame(width: 300)
                Spacer(minLength: 12)
                Segmented(selection: $sort, options: [
                    .init(.size, "Size"), .init(.name, "Name"), .init(.updated, "Updated"),
                ])
            }
            .padding(.horizontal, AppColumns.inset)
            .frame(height: 54)
            Rule()

            HStack(spacing: AppColumns.gap) {
                Button {
                    if ticked == selectable.count {
                        store.selectedApps.subtract(selectable)
                    } else {
                        store.selectedApps.formUnion(selectable)
                    }
                } label: {
                    CheckBox(ticked == 0 ? .off : ticked == selectable.count ? .on : .mixed)
                }
                .buttonStyle(.plain)
                .disabled(selectable.isEmpty)
                .help("Tick every app in the list")
                ColumnLabel("Application").padding(.leading, AppColumns.icon + AppColumns.gap)
                Spacer(minLength: 12)
                ColumnLabel("Updated").frame(width: AppColumns.updated, alignment: .trailing)
                ColumnLabel("Size").frame(width: AppColumns.size, alignment: .trailing)
            }
            .padding(.horizontal, AppColumns.inset)
            .frame(height: 34)
            Rule()

            if rows.isEmpty {
                Text("No app matches “\(query)”")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { app in
                            AppRow(app: app)
                            Rule()
                        }
                    }
                }
            }

            Rule()
            HStack(spacing: 14) {
                Text(store.selectedApps.isEmpty ? "Select apps to uninstall them with their files"
                     : "\(store.selectedApps.count) selected · \(Format.bytes(store.selectedAppBytes))")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 12)
                if store.removing { BusyLabel(text: "Moving to Trash…") }
                KitButton("Uninstall", icon: "trash", kind: .danger) { store.requestUninstall() }
                    .disabled(store.selectedApps.isEmpty || store.removing || store.scanning)
            }
            .padding(.horizontal, AppColumns.inset)
            .frame(height: 56)
        }
        .panel()
    }
}

private struct ColumnLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.label)
            .tracking(0.9)
            .foregroundStyle(Theme.textTertiary)
    }
}

private struct AppRow: View {
    @EnvironmentObject var store: AppsStore
    let app: AppInfo
    @State private var hovering = false

    private var detail: String {
        var parts: [String] = []
        if !app.version.isEmpty { parts.append("v\(app.version)") }
        if !app.bundleID.isEmpty { parts.append(app.bundleID) }
        if app.libraryBytes > 0 { parts.append("\(Format.bytes(app.libraryBytes)) in ~/Library") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button { store.toggleApp(app) } label: {
            HStack(spacing: AppColumns.gap) {
                if app.isProtected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 18, height: 18)
                        .help(app.isTidyDisk ? "TidyDisk cannot uninstall itself"
                              : "Made by Apple. TidyDisk leaves it alone.")
                } else {
                    CheckBox(isOn: store.selectedApps.contains(app.id))
                }
                AppIcon(path: app.path)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 12)
                Group {
                    if let updated = app.updated {
                        Text(updated, format: .dateTime.day().month().year())
                    } else {
                        Text("")
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: AppColumns.updated, alignment: .trailing)
                Text(Format.bytes(app.bytes))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: AppColumns.size, alignment: .trailing)
            }
            .padding(.horizontal, AppColumns.inset)
            .frame(height: 50)
            .background(hovering ? Color.white.opacity(0.03) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Show in Finder") { revealInFinder([app.path]) }
            if !app.libraryPaths.isEmpty {
                Button("Show its files in ~/Library") { revealInFinder(app.libraryPaths) }
            }
        }
    }
}

/// The app's real icon, fetched once per bundle.
private struct AppIcon: View {
    let path: String

    private static let cache = NSCache<NSString, NSImage>()

    private var image: NSImage {
        if let cached = Self.cache.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        Self.cache.setObject(icon, forKey: path as NSString)
        return icon
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: AppColumns.icon, height: AppColumns.icon)
    }
}

// MARK: - Pieces the kit does not have

/// Plain search box on a raised surface.
private struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.textTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .panel(radius: 8, fill: Theme.raised)
    }
}

/// One quiet line when sandboxed app data had to be left out.
private struct FullDiskAccessHint: View {
    private static let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text("Sizes leave out sandboxed app data in ~/Library/Containers.")
                .foregroundStyle(Theme.textTertiary)
            Button {
                if let url = Self.settings { NSWorkspace.shared.open(url) }
            } label: {
                Text("Grant Full Disk Access to include sandboxed app data")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 4)
    }
}

private func revealInFinder(_ paths: [String]) {
    NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
}
