import Foundation

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
