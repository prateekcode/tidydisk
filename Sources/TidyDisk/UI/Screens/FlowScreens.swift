import SwiftUI

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HeroDisc(symbol: "bubbles.and.sparkles.fill",
                     colors: [Theme.magenta, Theme.purple, Theme.deepPurple])
            Spacer().frame(height: 44)
            Text("Welcome to TidyDisk")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Start with a quick scan of your dev junk — caches, DerivedData, build artifacts and more.")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)
            Text("\(Format.bytes(state.freeSpace)) free of \(Format.bytes(state.totalSpace))")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassCard(cornerRadius: 20)
                .padding(.top, 18)
            Spacer()
            GlowButton(title: "Scan") { state.startScan() }
                .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Scanning

struct ScanningView: View {
    @EnvironmentObject var state: AppState
    @State private var spinning = false

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 10)
                    .frame(width: 170, height: 170)
                Circle()
                    .trim(from: 0, to: max(0.04, CGFloat(state.scannedCount) / CGFloat(state.tasks.count)))
                    .stroke(
                        AngularGradient(colors: [Theme.magenta, Theme.accent, Theme.magenta],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 170, height: 170)
                    .rotationEffect(.degrees(-90))
                Text("\(state.scannedCount)/\(state.tasks.count)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Scanning your Mac…")
                .font(.title.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(state.scanningTaskName)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
                .animation(.none, value: state.scanningTaskName)
            Text(Format.bytes(state.totalJunk()) + " found so far")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.magenta)
                .contentTransition(.numericText())
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Review

struct ReviewView: View {
    @EnvironmentObject var state: AppState

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    state.reset()
                } label: {
                    Label("Start Over", systemImage: "chevron.left")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Text("Look what we found: \(Format.bytes(state.totalJunk())) of junk")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 10)
            Text("Safe items are pre-selected. Aggressive and Nuclear are opt-in.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(state.tasks) { task in
                        TaskCardView(task: task)
                    }
                }
                .padding(20)
            }

            VStack(spacing: 10) {
                Text("\(Format.bytes(state.selectedJunk)) selected")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
                GlowButton(title: "Run") { state.startClean() }
                    .opacity(state.selected.isEmpty ? 0.4 : 1)
                    .disabled(state.selected.isEmpty)
            }
            .padding(.bottom, 26)
        }
    }
}

struct TaskCardView: View {
    @EnvironmentObject var state: AppState
    let task: CleanupTask
    @State private var hovering = false

    private var isOn: Bool { state.selected.contains(task.id) }

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.25)) {
                if isOn { state.selected.remove(task.id) } else { state.selected.insert(task.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TaskIcon(task: task)
                    Spacer()
                    CheckCircle(isOn: isOn)
                }
                Text(task.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(task.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2, reservesSpace: true)
                HStack {
                    Text(Format.bytes(state.size(of: task)))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(state.size(of: task) > 0 ? Theme.textPrimary : Theme.textSecondary)
                    Spacer()
                    TierBadge(tier: task.tier)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isOn ? Theme.accent.opacity(0.7) : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(hovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.spring(duration: 0.25)) { hovering = inside }
        }
    }
}

// MARK: - Cleaning

struct CleaningView: View {
    @EnvironmentObject var state: AppState

    private var runTasks: [CleanupTask] {
        state.tasks.filter { state.selected.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Cleaning up…")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 40)
            Text("\(Format.bytes(state.freedTotal)) freed so far")
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(runTasks) { task in
                        CleaningRow(task: task, status: state.runStatus[task.id] ?? .pending)
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: 560)
            .glassCard()
            .padding(.horizontal, 40)
            .padding(.bottom, 34)
        }
    }
}

struct CleaningRow: View {
    let task: CleanupTask
    let status: TaskRunStatus

    var body: some View {
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 28)
            Text(task.name)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            switch status {
            case .pending:
                Circle().fill(Color.white.opacity(0.2)).frame(width: 10, height: 10)
            case .running:
                ProgressView().controlSize(.small).tint(.white)
            case .done(let freed):
                Text(Format.bytes(freed))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.tierColor(.safe))
                    .transition(.scale.combined(with: .opacity))
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.tierColor(.nuclear))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
    }
}

// MARK: - Done

struct DoneView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 50) {
                HeroDisc(symbol: "checkmark.seal.fill",
                         colors: [Theme.tierColor(.safe), Theme.green, Theme.deepGreen])
                VStack(alignment: .leading, spacing: 14) {
                    Text("Cleanup complete!")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 12) {
                        Image(systemName: "xmark.bin.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.tierColor(.safe))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Format.bytes(state.freedTotal)) of junk")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("successfully cleaned")
                                .font(.callout)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Text("\(Format.bytes(state.freeSpace)) now free of \(Format.bytes(state.totalSpace))")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            HStack {
                Button("View Log") {
                    state.sidebar = .log
                    state.phase = .welcome
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                Spacer()
                PillButton(title: "Done", prominent: true) { state.reset() }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
    }
}
