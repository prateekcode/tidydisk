import Foundation
import AppKit

extension Notification.Name {
    /// Posted by `Engine.reportFreed`; AppState adds it to the lifetime counter.
    static let tidyDiskFreed = Notification.Name("tidyDiskFreed")
}

extension Engine {
    /// Call after deleting or trashing anything: updates the free-space readout
    /// everywhere and the "cleaned all time" counter.
    static func reportFreed(_ bytes: Int64) {
        NotificationCenter.default.post(name: .tidyDiskFreed, object: nil, userInfo: ["bytes": bytes])
    }

    /// "Prateek's MacBook Air"
    static func machineName() -> String {
        // `--machine-name` lets a `--shot` for the README show a neutral name.
        Snapshot.value(after: "--machine-name") ?? Host.current().localizedName ?? "This Mac"
    }

    /// "Macintosh HD"
    static func volumeName() -> String {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey])
        return values?.volumeLocalizedName ?? "Startup disk"
    }

    /// Opens System Settings on the Full Disk Access list.
    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// True when the app has Full Disk Access (reads protected folders without prompts).
    static func hasFullDiskAccess() -> Bool {
        let probe = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        let fd = open(probe, O_RDONLY)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }
}

/// The activity log every screen writes to and the Log screen shows.
@MainActor
final class ActivityLog: ObservableObject {
    static let shared = ActivityLog()

    @Published private(set) var lines: [String] = []

    func add(_ line: String) {
        lines.append(line)
        if lines.count > 2000 { lines.removeFirst(lines.count - 2000) }
    }
}

extension Format {
    /// RAM sizes count in 1024s ("16 GB", not "17.18 GB").
    static func memory(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return value <= 0 ? "0 KB" : formatter.string(fromByteCount: value)
    }

    /// "251,337"
    static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// "41%" from a 0…1 fraction.
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// "19 min ago", "just now", "3 d ago".
    static func ago(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60) min ago"
        case ..<86_400: return "\(seconds / 3600) h ago"
        default: return "\(seconds / 86_400) d ago"
        }
    }

    /// Transfer rate: "7.44 MB/s", "411 KB/s".
    static func rate(_ bytesPerSecond: Double) -> String {
        bytesPerSecond < 1 ? "0 KB/s" : bytes(Int64(bytesPerSecond)) + "/s"
    }
}
