import AppKit

/// Makes TidyDisk behave like a proper menu-bar app:
/// - Quit from Dock / Cmd+Q → window closes, app keeps living in the menu bar
/// - Quit from the menu-bar panel → really quits (sets `allowTermination`)
/// - Logout / restart / shutdown → really quits (never blocks the system)
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var allowTermination = false

    private static func fourCC(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { $0 << 8 + UInt32($1) }
    }
    /// kAEQuitReason values for logout / restart / shutdown (incl. dialog variants).
    private static let systemQuitReasons: Set<UInt32> = [
        fourCC("logo"), fourCC("rlgo"), fourCC("rest"), fourCC("rrst"),
        fourCC("shut"), fourCC("rsdn"),
    ]

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.allowTermination { return .terminateNow }
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           Self.systemQuitReasons.contains(
               event.attributeDescriptor(forKeyword: Self.fourCC("why?"))?.enumCodeValue ?? 0
           ) {
            return .terminateNow
        }
        // Plain quit: hide the window, drop the Dock icon, stay in the menu bar.
        for window in sender.windows where window.canBecomeMain {
            window.close()
        }
        sender.setActivationPolicy(.accessory)
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        sender.setActivationPolicy(.regular)
        return true
    }
}
