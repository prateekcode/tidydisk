import SwiftUI
import AppKit

struct DuplicatesView: View {
    @EnvironmentObject var state: AppState

    private var wastedTotal: Int64 { state.dupGroups.reduce(0) { $0 + $1.wastedBytes } }

    private var subtitle: String {
        state.dupScanned && !state.dupGroups.isEmpty
            ? "\(Format.bytes(wastedTotal)) taken by copies in Downloads and Desktop"
            : "Identical files in Downloads and Desktop: keep one, trash the rest"
    }

    var body: some View {
        Page(icon: AppTab.duplicates.icon, title: "Duplicates", subtitle: subtitle) {
            if state.dupScanning { BusyLabel(text: "Comparing files…") }
            KitButton(state.dupScanned ? "Scan again" : "Find duplicates", icon: "arrow.clockwise",
                      kind: state.dupScanned ? .secondary : .primary) { state.scanDuplicates() }
                .disabled(state.dupScanning)
        } content: {
            if state.dupGroups.isEmpty {
                EmptyState(icon: state.dupScanned ? "checkmark.seal" : AppTab.duplicates.icon,
                           title: state.dupScanning ? "Comparing files…"
                               : state.dupScanned ? "No duplicates" : "Not scanned yet",
                           message: "Files are matched by content, not by name. The newest copy is kept by default.")
                    .panel()
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(state.dupGroups) { group in
                                DuplicateGroupCard(group: group)
                                Rule()
                            }
                        }
                    }
                    Rule()
                    HStack(spacing: 14) {
                        Text(state.selectedDups.isEmpty ? "Tick the copies to remove"
                             : "\(state.selectedDups.count) selected · \(Format.bytes(state.selectedDupBytes))")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        KitButton("Move to Trash", icon: "trash", kind: .primary) { state.trashSelectedDups() }
                            .disabled(state.selectedDups.isEmpty)
                    }
                    .padding(14)
                }
                .panel()
            }
        }
    }
}

struct DuplicateGroupCard: View {
    @EnvironmentObject var state: AppState
    let group: DuplicateGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundStyle(Theme.accent)
                Text(group.files.first?.name ?? "")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(group.files.count) copies · \(Format.bytes(group.wastedBytes)) wasted")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.tierColor(.aggressive))
            }
            ForEach(Array(group.files.enumerated()), id: \.element.path) { index, file in
                DuplicateFileRow(file: file, isKeeper: index == 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}

struct DuplicateFileRow: View {
    @EnvironmentObject var state: AppState
    let file: LargeFile
    let isKeeper: Bool

    private var isOn: Bool { state.selectedDups.contains(file.path) }

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                if isOn { state.selectedDups.remove(file.path) } else { state.selectedDups.insert(file.path) }
            }
        } label: {
            HStack(spacing: 10) {
                CheckBox(isOn: isOn)
                Text(Engine.abbreviate(file.path))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if isKeeper {
                    Badge("newest", color: Theme.green)
                }
                Spacer()
                Text(file.modified, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(Format.bytes(file.bytes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }
}
