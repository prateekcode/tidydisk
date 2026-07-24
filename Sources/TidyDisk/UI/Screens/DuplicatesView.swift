import SwiftUI
import AppKit

struct DuplicatesView: View {
    @EnvironmentObject var state: AppState

    private var wastedTotal: Int64 { state.dupGroups.reduce(0) { $0 + $1.wastedBytes } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Duplicates")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(state.dupScanned && !state.dupGroups.isEmpty
                     ? "\(Format.bytes(wastedTotal)) wasted on copies in Downloads & Desktop"
                     : "Identical files in Downloads & Desktop — keep one, trash the rest")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 16)

            if state.dupScanning {
                Spacer()
                ProgressView().controlSize(.large).tint(.white)
                Text("Comparing files…")
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 12)
                Spacer()
            } else if !state.dupScanned {
                Spacer()
                PillButton(title: "Find Duplicates", prominent: true) { state.scanDuplicates() }
                Spacer()
            } else if state.dupGroups.isEmpty {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.tierColor(.safe))
                Text("No duplicates — tidy!")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 10)
                Spacer()
                PillButton(title: "Rescan") { state.scanDuplicates() }
                    .padding(.bottom, 24)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(state.dupGroups) { group in
                            DuplicateGroupCard(group: group)
                        }
                    }
                    .padding(24)
                }
                HStack(spacing: 14) {
                    PillButton(title: "Rescan") { state.scanDuplicates() }
                    Spacer()
                    if !state.selectedDups.isEmpty {
                        Text(Format.bytes(state.selectedDupBytes))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        PillButton(title: "Move \(state.selectedDups.count) to Trash", prominent: true) {
                            state.trashSelectedDups()
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 24)
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
                    .foregroundStyle(Theme.magenta)
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
        .padding(14)
        .glassCard(cornerRadius: 14)
        .frame(maxWidth: 640)
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
                CheckCircle(isOn: isOn)
                Text(Engine.abbreviate(file.path))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                if isKeeper {
                    Text("newest")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.tierColor(.safe))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.tierColor(.safe).opacity(0.16)))
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
