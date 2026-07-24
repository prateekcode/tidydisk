import SwiftUI

// MARK: - Category detail

struct CategoryView: View {
    @EnvironmentObject var state: AppState
    let category: TaskCategory

    private var tasks: [CleanupTask] { state.tasks(in: category) }

    private var categorySize: Int64 {
        tasks.reduce(0) { $0 + state.size(of: $1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Theme.magenta)
                Text(category.rawValue)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(state.hasScanned
                     ? "\(Format.bytes(categorySize)) reclaimable"
                     : "Run a scan to size these items")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 44)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(tasks) { task in
                        HStack(spacing: 12) {
                            TaskIcon(task: task, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(task.detail)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            TierBadge(tier: task.tier)
                            Text(state.hasScanned ? Format.bytes(state.size(of: task)) : "—")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                        .padding(12)
                        .glassCard(cornerRadius: 14)
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: 620)

            Group {
                if state.hasScanned {
                    PillButton(title: "Clean \(category.rawValue)", prominent: true) {
                        state.startClean(taskIDs: Set(tasks.filter { state.size(of: $0) > 0 }.map(\.id)))
                    }
                    .disabled(categorySize == 0)
                    .opacity(categorySize == 0 ? 0.4 : 1)
                } else {
                    PillButton(title: "Scan First", prominent: true) {
                        state.sidebar = .smartScan
                        state.startScan()
                    }
                }
            }
            .padding(.bottom, 30)
        }
    }
}

// MARK: - Log

struct LogView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activity Log")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.top, 44)
                .padding(.bottom, 16)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if state.log.isEmpty {
                            Text("Nothing yet — run a scan.")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(Array(state.log.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(line.hasPrefix("—") ? Theme.magenta : Theme.textSecondary)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                }
                .glassCard()
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
                .onChange(of: state.log.count) {
                    proxy.scrollTo(state.log.count - 1, anchor: .bottom)
                }
            }
        }
    }
}
