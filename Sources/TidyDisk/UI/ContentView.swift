import SwiftUI
import AppKit

/// The window: top tab bar, then the selected screen.
struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.backdrop)
        .ignoresSafeArea()
        .frame(minWidth: 1040, minHeight: 700)
        .preferredColorScheme(.dark)
        .background(WindowChrome())
        .environmentObject(state.disk)
        .environmentObject(state.apps)
        .environmentObject(state.ai)
        .environmentObject(state.monitor)
        .environmentObject(ActivityLog.shared)
        .sheet(isPresented: $state.showProSheet) { ProSheet() }
        .task {
            state.revalidateLicense()
            await Snapshot.runIfRequested(state: state)
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch state.tab {
        case .overview: OverviewView()
        case .disk: DiskView()
        case .clean: CleanView()
        case .largeFiles: LargeFilesView()
        case .apps: AppsView()
        case .projects: ProjectsView()
        case .ai: AIView()
        case .monitor: MonitorView()
        case .duplicates: DuplicatesView()
        case .settings: SettingsView()
        case .log: LogView()
        }
    }
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            // Room for the traffic lights, then the app mark.
            Spacer().frame(width: 78)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "bubbles.and.sparkles.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                )
                .padding(.trailing, 10)

            ForEach(Array(AppTab.barGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Rectangle().fill(Theme.line).frame(width: 1, height: 20).padding(.horizontal, 8)
                }
                ForEach(group, id: \.self) { TabButton(tab: $0) }
            }

            Spacer(minLength: 8)

            if state.cleanedAllTime > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 12, weight: .semibold))
                    Text(Format.bytes(state.cleanedAllTime)).fontWeight(.bold)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.green)
                Text("cleaned")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.trailing, 6)
            }
            if ProConfig.paywallEnabled {
                Button { state.showProSheet = true } label: {
                    Badge(state.isPro ? "Pro" : "Get Pro", color: Theme.gold, icon: "crown")
                }
                .buttonStyle(.plain)
            }
            BarIconButton(tab: .log)
            BarIconButton(tab: .settings)
        }
        .padding(.trailing, 14)
        .frame(height: Theme.barHeight)
        .background(Theme.bar)
        .overlay(alignment: .bottom) { Rule() }
    }
}

private struct TabButton: View {
    @EnvironmentObject var state: AppState
    let tab: AppTab
    @State private var hovering = false

    private var isOn: Bool { state.tab.barTab == tab }

    var body: some View {
        Button { state.tab = tab } label: {
            HStack(spacing: 7) {
                Image(systemName: tab.icon).font(.system(size: 13, weight: .medium))
                Text(tab.title).font(.system(size: 13.5, weight: .semibold)).fixedSize()
            }
            .foregroundStyle(isOn ? Theme.accent : hovering ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? Theme.accent.opacity(0.16) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct BarIconButton: View {
    @EnvironmentObject var state: AppState
    let tab: AppTab

    var body: some View {
        Button { state.tab = tab } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(state.tab == tab ? Theme.accent : Theme.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.title)
    }
}

// MARK: - Window chrome

/// Gives the window a tall unified title bar so the traffic lights sit centred
/// in our own top bar, and paints the window in the app background.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            if window.toolbar == nil {
                let toolbar = NSToolbar()
                toolbar.showsBaselineSeparator = false
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unified
            window.backgroundColor = NSColor(Theme.bg)
            window.isMovableByWindowBackground = false
        }
    }
}

// MARK: - Snapshot mode

/// `TidyDisk --shot <tab> <out.png> [seconds] [--scan] [--size WxH]` opens the app on that tab,
/// waits for it to settle, writes the window to a PNG and quits. Used to check
/// screens without Screen Recording permission.
enum Snapshot {
    /// The argument following `flag`, for options that pick what a snapshot shows.
    static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), args.count > index + 1 else { return nil }
        return args[index + 1]
    }

    @MainActor
    static func runIfRequested(state: AppState) async {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--shot"), args.count > flag + 2,
              let tab = AppTab(rawValue: args[flag + 1]) else { return }
        let delay = args.count > flag + 3 ? Double(args[flag + 3]) ?? 3 : 3
        state.tab = tab
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            // `--size 1444x846` checks a layout at another window size.
            let size = (value(after: "--size") ?? "").split(separator: "x").compactMap { Double($0) }
            window.setContentSize(size.count == 2 ? NSSize(width: size[0], height: size[1])
                                                  : NSSize(width: 1180, height: 780))
        }
        // `--scan` fills the screens with a real scan first (and waits for it).
        if args.contains("--scan") {
            state.scanEverything()
            state.apps.scan()
            state.ai.scanDisk()
            for _ in 0..<600 where state.isBusy || state.disk.measuring {
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
        try? await Task.sleep(for: .seconds(delay))
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }),
              let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { exit(1) }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: args[flag + 2]))
        // Report what sits under the first tab, to prove the bar takes clicks.
        let probe = frame.hitTest(NSPoint(x: 150, y: frame.bounds.height - 26))
        print("hit-test in top bar:", probe.map { String(describing: type(of: $0)) } ?? "nil")
        AppDelegate.allowTermination = true
        exit(0)
    }
}
