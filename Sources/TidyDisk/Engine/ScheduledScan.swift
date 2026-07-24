import Foundation
import UserNotifications

extension Engine {
    static let agentLabel = "com.riekapps.tidydisk.weeklyscan"
    static var agentPlistPath: String { NSHomeDirectory() + "/Library/LaunchAgents/\(agentLabel).plist" }

    static func isAgentInstalled() -> Bool {
        FileManager.default.fileExists(atPath: agentPlistPath)
    }

    /// Installs a LaunchAgent that runs this binary with --scan-notify every Monday 10:00.
    static func installAgent() -> [String] {
        guard let executable = Bundle.main.executablePath else {
            return ["[fail] cannot resolve app executable path"]
        }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(agentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executable)</string>
                <string>--scan-notify</string>
            </array>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Weekday</key><integer>1</integer>
                <key>Hour</key><integer>10</integer>
                <key>Minute</key><integer>0</integer>
            </dict>
        </dict>
        </plist>
        """
        let agentsDir = (agentPlistPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
        do {
            try plist.write(toFile: agentPlistPath, atomically: true, encoding: .utf8)
        } catch {
            return ["[fail] write LaunchAgent: \(error.localizedDescription)"]
        }
        let uid = getuid()
        _ = run(["launchctl", "bootout", "gui/\(uid)/\(agentLabel)"]) // clear any stale copy
        let (status, output) = run(["launchctl", "bootstrap", "gui/\(uid)", agentPlistPath])
        return status == 0
            ? ["[done] weekly scan scheduled — Mondays 10:00"]
            : ["[fail] launchctl bootstrap: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"]
    }

    static func removeAgent() -> [String] {
        _ = run(["launchctl", "bootout", "gui/\(getuid())/\(agentLabel)"])
        try? FileManager.default.removeItem(atPath: agentPlistPath)
        return ["[done] weekly scan disabled"]
    }
}

/// Runs when launched with --scan-notify (from the LaunchAgent): size all tasks,
/// notify the user how much junk accumulated, and exit without showing any UI.
enum HeadlessScan {
    static func runAndExit() -> Never {
        let total = Catalog.build().reduce(Int64(0)) { $0 + Engine.scanSize(of: $1) }
        let free = Format.bytes(Engine.freeDiskSpace())
        let body = total > 0
            ? "\(Format.bytes(total)) of junk piled up · \(free) free. Time to clean!"
            : "All clean — \(free) free."
        notify(body: body)
        exit(0)
    }

    private static func notify(body: String) {
        let semaphore = DispatchSemaphore(value: 0)
        var delivered = false
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                semaphore.signal()
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "TidyDisk weekly scan"
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request) { error in
                delivered = (error == nil)
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + 5)
        if !delivered {
            _ = Engine.run(["osascript", "-e",
                            "display notification \"\(body)\" with title \"TidyDisk weekly scan\""])
        }
    }
}
