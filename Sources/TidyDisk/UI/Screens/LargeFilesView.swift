import SwiftUI
import AppKit

/// The user's own big files, from the last disk measurement.
struct LargeFilesView: View {
    @EnvironmentObject var disk: DiskStore
    @State private var byName = false
    @State private var confirming = false

    private var files: [LargeFile] {
        byName ? disk.largeFiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
               : disk.largeFiles
    }

    private var subtitle: String {
        guard let index = disk.index else { return "Your biggest files, wherever they are in your home folder" }
        return "\(files.count) files over \(Format.bytes(disk.largeThreshold)) · "
            + "\(Format.bytes(disk.largeFilesBytes)) · measured \(Format.ago(index.date))"
    }

    private var stepIndex: Binding<Double> {
        Binding(
            get: { Double(DiskStore.thresholdSteps.firstIndex(of: disk.largeThreshold) ?? 3) },
            set: { disk.largeThreshold = DiskStore.thresholdSteps[Int($0.rounded())] }
        )
    }

    private var allMark: CheckBox.Mark {
        if disk.selectedFiles.isEmpty { return .off }
        return disk.selectedFiles.count == files.count ? .on : .mixed
    }

    var body: some View {
        Page(icon: "doc.text", title: "Large Files", subtitle: subtitle) {
            if disk.index != nil {
                Text("Over").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                Slider(value: stepIndex, in: 0...Double(DiskStore.thresholdSteps.count - 1), step: 1)
                    .tint(Theme.accent)
                    .frame(width: 170)
                Text(Format.bytes(disk.largeThreshold))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 64, alignment: .leading)
            }
            if disk.measuring { BusyLabel(text: "Measuring…") }
            KitButton(disk.index == nil ? "Find large files" : "Scan again", icon: "arrow.counterclockwise",
                      kind: disk.index == nil ? .primary : .secondary) { disk.measure() }
                .disabled(disk.measuring)
        } content: {
            if files.isEmpty {
                EmptyState(icon: disk.index == nil ? "doc.text" : "checkmark.seal",
                           title: disk.measuring ? "Measuring the disk…"
                               : disk.index == nil ? "Not measured yet"
                               : "Nothing over \(Format.bytes(disk.largeThreshold))",
                           message: "Files inside apps, ~/Library and tool folders are left out: this list is only files you put there yourself.")
                    .panel()
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button(action: toggleAll) { CheckBox(allMark) }.buttonStyle(.plain)
                        SectionLabel("Name")
                        Spacer()
                        SectionLabel("Modified").frame(width: 110, alignment: .trailing)
                        SectionLabel("Size").frame(width: 90, alignment: .trailing)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .background(Theme.raised)
                    Rule()
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(files) { file in
                                LargeFileRow(file: file)
                                Rule()
                            }
                        }
                    }
                    Rule()
                    HStack(spacing: 14) {
                        Segmented(selection: $byName, options: [.init(false, "By size"), .init(true, "By name")])
                        Text(disk.selectedFiles.isEmpty ? "Tick files to move them to the Trash"
                             : "\(disk.selectedFiles.count) ticked · \(Format.bytes(disk.selectedBytes))")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        KitButton("Move to Trash", icon: "trash", kind: .primary) { confirming = true }
                            .disabled(disk.selectedFiles.isEmpty)
                    }
                    .padding(14)
                }
                .panel()
            }
        }
        .alert("Move \(disk.selectedFiles.count) files to the Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive) { disk.trashSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(Format.bytes(disk.selectedBytes)) goes to the Trash. You can put files back from there until you empty it.")
        }
    }

    private func toggleAll() {
        disk.selectedFiles = disk.selectedFiles.count == files.count ? [] : Set(files.map(\.path))
    }
}

private struct LargeFileRow: View {
    @EnvironmentObject var disk: DiskStore
    let file: LargeFile
    @State private var hovering = false

    private var isOn: Bool { disk.selectedFiles.contains(file.path) }

    var body: some View {
        Button {
            if isOn { disk.selectedFiles.remove(file.path) } else { disk.selectedFiles.insert(file.path) }
        } label: {
            HStack(spacing: 12) {
                CheckBox(isOn: isOn)
                Text(file.name).font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(Engine.abbreviate((file.path as NSString).deletingLastPathComponent))
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                if hovering {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                    } label: {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }
                Text(file.modified, format: .dateTime.day().month().year())
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .frame(width: 110, alignment: .trailing)
                Text(Format.bytes(file.bytes)).font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 90, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .frame(height: 50)
            .background(hovering ? Color.white.opacity(0.03) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
