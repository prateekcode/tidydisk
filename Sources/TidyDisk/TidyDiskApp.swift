import SwiftUI

@main
struct TidyDiskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    init() {
        // LaunchAgent mode: size everything, notify, exit — no UI.
        if CommandLine.arguments.contains("--scan-notify") {
            HeadlessScan.runAndExit()
        }
    }

    var body: some Scene {
        Window("TidyDisk", id: "main") {
            ContentView()
                .environmentObject(state)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(state)
        } label: {
            MenuBarLabel()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}
