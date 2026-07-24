import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        // Menu bar renders this as template image + text
        Image(systemName: "bubbles.and.sparkles.fill")
        Text(Format.wholeGB(state.freeSpace))
            .monospacedDigit()
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    private var usedFraction: Double {
        guard state.totalSpace > 0 else { return 0 }
        return 1 - Double(state.freeSpace) / Double(state.totalSpace)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bubbles.and.sparkles.fill")
                    .foregroundStyle(.purple)
                Text("TidyDisk")
                    .font(.headline)
                Spacer()
                Text("\(Format.bytes(state.freeSpace)) free")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: usedFraction)
                .tint(usedFraction > 0.9 ? .red : .purple)
            Text("\(Format.bytes(state.totalSpace - state.freeSpace)) used of \(Format.bytes(state.totalSpace))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button {
                openMainWindow()
            } label: {
                Label("Open TidyDisk", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                openMainWindow()
                state.startScan()
            } label: {
                Label("Scan Now", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(state.isBusy)

            Divider()

            Toggle(isOn: Binding(
                get: { state.weeklyScanEnabled },
                set: { enabled in
                    // Pro gate: the paywall sheet lives on the main window,
                    // so bring it forward instead of toggling silently.
                    if ProConfig.paywallEnabled && enabled && !state.isPro {
                        openMainWindow()
                        state.showProSheet = true
                    } else {
                        state.setWeeklyScan(enabled)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("Weekly scan")
                        if ProConfig.paywallEnabled && !state.isPro {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text("Mondays 10:00, with notification")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Divider()

            Button {
                AppDelegate.allowTermination = true
                NSApp.terminate(nil)
            } label: {
                Label("Quit TidyDisk", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.borderless)
        .padding(14)
        .frame(width: 270)
        .onAppear { state.refreshFreeSpace() }
    }

    private func openMainWindow() {
        NSApp.setActivationPolicy(.regular) // restore Dock icon if hidden to menu bar
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
