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
        // `TidyDisk --measure [folder]`: print where the space goes, no UI.
        if CommandLine.arguments.contains("--measure") {
            DiskReport.printAndExit()
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
