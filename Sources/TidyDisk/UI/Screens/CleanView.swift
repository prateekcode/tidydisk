import SwiftUI

/// Everything the cleaners found, in three risk groups, with tick boxes.
struct CleanView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var disk: DiskStore
    @State private var confirming = false

    private var found: [CleanupTask] { state.tasks.filter { state.size(of: $0) > 0 } }

    private var subtitle: String {
        switch state.phase {
        case .idle:
            return "Caches, logs, build output and old SDKs that can go"
        case .scanning:
            return "Scanning \(state.scannedCount) of \(state.tasks.count): \(state.scanningTaskName)"
        default:
            let scan = state.lastScan.map { " · from your last scan, \(Format.ago($0))" } ?? ""
            return "\(Format.bytes(state.clearable)) in \(found.count) places\(scan)"
        }
    }

    private var needsCare: Bool {
        state.tasks.contains { state.selected.contains($0.id) && $0.tier != .safe }
    }

    var body: some View {
        Page(icon: AppTab.clean.icon, title: "Clean", subtitle: subtitle) {
            if state.hasScanned {
                KitButton("Select the safe part", icon: "bolt", kind: .gold) { state.selectTier(.safe) }
                    .disabled(state.isBusy || state.totalJunk(tier: .safe) == 0)
            }
            KitButton(state.hasScanned ? "Scan again" : "Scan this Mac", icon: "arrow.counterclockwise",
                      kind: state.hasScanned ? .secondary : .primary) { state.startScan() }
                .disabled(state.isBusy)
        } content: {
            if state.phase == .idle {
                EmptyState(icon: AppTab.clean.icon, title: "Nothing scanned yet",
                           message: "A scan only measures. Nothing is removed until you tick it and press Clean.",
                           actionTitle: "Scan this Mac") { state.startScan() }
                    .panel()
            } else {
                VStack(spacing: 0) {
                    if state.phase == .done { DoneBanner() }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(RiskTier.allCases, id: \.self) { tier in
                                TierHeader(tier: tier)
                                Rule()
                                ForEach(sorted(state.tasks(in: tier))) { task in
                                    TaskRow(task: task)
                                    Rule()
                                }
                                if tier == .aggressive { ownFilesRows }
                            }
                        }
                    }
                    Rule()
                    footer
                }
                .panel()
            }
        }
        .alert("Clean the ticked items?", isPresented: $confirming) {
            Button("Clean \(Format.bytes(state.selectedJunk))", role: .destructive) { state.startClean() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Some of these are outside the safe group. They are deleted, not moved to the Trash, and come back only by re-downloading, re-indexing or reinstalling.")
        }
    }

    /// Biggest first once sizes are known; catalog order while scanning.
    private func sorted(_ tasks: [CleanupTask]) -> [CleanupTask] {
        state.phase == .scanning ? tasks : tasks.sorted { state.size(of: $0) > state.size(of: $1) }
    }

    /// The user's own files live on their own tabs; link to them from the review group.
    @ViewBuilder
    private var ownFilesRows: some View {
        NavRow(icon: "doc.text", color: Theme.amber, title: "Large files",
               subtitle: "Your own files over \(Format.bytes(disk.largeThreshold)): look through them first",
               value: disk.index == nil ? "—" : Format.bytes(disk.largeFilesBytes)) { state.tab = .largeFiles }
            .padding(.leading, 36)
        Rule()
        NavRow(icon: AppTab.duplicates.icon, color: Theme.amber, title: "Duplicates",
               subtitle: "Same content saved more than once in Downloads and Desktop",
               value: state.dupScanned
                   ? Format.bytes(state.dupGroups.reduce(0) { $0 + $1.wastedBytes }) : "—") {
            state.tab = .duplicates
        }
        .padding(.leading, 36)
        Rule()
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(state.phase == .cleaning ? "Cleaning…"
                 : state.selected.isEmpty ? "Tick what you want to clean"
                 : "\(state.selected.count) ticked · \(Format.bytes(state.selectedJunk))")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if state.phase == .cleaning { ProgressView().controlSize(.small) }
            KitButton(state.selected.isEmpty ? "Clean" : "Clean \(Format.bytes(state.selectedJunk))",
                      icon: "sparkles", kind: .primary) {
                if needsCare { confirming = true } else { state.startClean() }
            }
            .disabled(state.selected.isEmpty || state.isBusy)
        }
        .padding(14)
    }
}

private struct DoneBanner: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.green)
            Text("Freed \(Format.bytes(state.freedTotal))").fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
            Text("\(Format.bytes(state.freeSpace)) free now").foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { state.dismissDone() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Theme.green.opacity(0.14))
        .overlay(alignment: .bottom) { Rule() }
    }
}

private struct TierHeader: View {
    @EnvironmentObject var state: AppState
    let tier: RiskTier

    private var mark: CheckBox.Mark {
        let ids = Set(state.tasks(in: tier).filter { state.size(of: $0) > 0 }.map(\.id))
        if ids.isEmpty || ids.isDisjoint(with: state.selected) { return .off }
        return ids.isSubset(of: state.selected) ? .on : .mixed
    }

    var body: some View {
        Button { state.toggle(tier) } label: {
            HStack(spacing: 12) {
                CheckBox(mark)
                IconTile(tier.icon, color: Theme.tierColor(tier), size: 30)
                Text(tier.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text(tier.blurb).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer()
                Text(state.hasScanned ? Format.bytes(state.totalJunk(tier: tier)) : "—")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(Theme.raised)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TaskRow: View {
    @EnvironmentObject var state: AppState
    let task: CleanupTask
    @State private var hovering = false

    private var size: Int64 { state.size(of: task) }
    private var isSized: Bool { state.sizes[task.id] != nil }

    var body: some View {
        Button { state.toggle(task) } label: {
            HStack(spacing: 12) {
                CheckBox(isOn: state.selected.contains(task.id))
                    .opacity(size > 0 ? 1 : 0.3)
                IconTile(task.icon, color: Theme.tierColor(task.tier), size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.name).font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(task.detail).font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                status
            }
            .padding(.leading, 54)
            .padding(.trailing, 18)
            .frame(height: 54)
            .opacity(isSized && size == 0 && state.runStatus[task.id] == nil ? 0.5 : 1)
            .background(hovering && size > 0 ? Color.white.opacity(0.03) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var status: some View {
        switch state.runStatus[task.id] {
        case .running:
            ProgressView().controlSize(.small)
        case .pending:
            Text("Waiting").font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
        case .done(let freed):
            Label("Freed \(Format.bytes(freed))", systemImage: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.green)
        case .failed(let message):
            Text(message).font(.system(size: 13)).foregroundStyle(Theme.red).lineLimit(1)
        case nil:
            Text(isSized ? Format.bytes(size) : "—")
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(size > 0 ? Theme.textPrimary : Theme.textTertiary)
        }
    }
}
