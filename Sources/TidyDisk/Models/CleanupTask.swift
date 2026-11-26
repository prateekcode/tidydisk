import Foundation

enum RiskTier: Int, Comparable, CaseIterable {
    case safe
    case aggressive
    case nuclear

    static func < (lhs: RiskTier, rhs: RiskTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .safe: return "Safe to clean"
        case .aggressive: return "Review before cleaning"
        case .nuclear: return "Handle with care"
        }
    }

    /// Short form for legends ("Review first 58.99 GB").
    var shortTitle: String {
        switch self {
        case .safe: return "Safe to clean"
        case .aggressive: return "Review first"
        case .nuclear: return "Handle with care"
        }
    }

    var blurb: String {
        switch self {
        case .safe: return "Rebuilt by the system or app when needed"
        case .aggressive: return "Comes back on demand, but re-downloading or re-indexing takes time"
        case .nuclear: return "Needs a reinstall before the project runs again"
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield"
        case .aggressive: return "eye"
        case .nuclear: return "exclamationmark.triangle"
        }
    }
}

enum TaskCategory: String, CaseIterable, Identifiable {
    case devCaches = "Dev Caches"
    case xcode = "Xcode"
    case system = "System"
    case appCaches = "App Caches"
    case docker = "Docker"
    case nuclear = "Nuclear"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .devCaches: return "shippingbox.fill"
        case .xcode: return "hammer.fill"
        case .system: return "internaldrive.fill"
        case .appCaches: return "app.badge.fill"
        case .docker: return "cube.transparent.fill"
        case .nuclear: return "exclamationmark.triangle.fill"
        }
    }
}

/// What the task actually does when scanned / cleaned.
enum TaskKind {
    /// Delete the *contents* of these directories, keeping the directory itself (mirrors `remove_glob dir/*`).
    case directoryContents([String])
    /// Find directories with these names under `root`, prune, and delete them.
    case findAndRemove(root: String, dirNames: [String])
    /// Run shell commands to clean; `scanPaths` are only used to estimate size.
    case commands(scanPaths: [String], commands: [[String]])
    /// Versioned sibling directories (e.g. NDKs): delete all but the newest version.
    case allButNewest(parent: String)
    /// Delete directories with these names inside every discovered project on this Mac.
    case projectSweep(dirNames: [String])
    /// For every app dir under `root` (minus `exclude`), delete the contents of any of `subpaths` it has.
    case appCacheSweep(root: String, subpaths: [String], exclude: [String])
}

struct CleanupTask: Identifiable {
    let id: String
    let name: String
    let detail: String
    let icon: String
    let category: TaskCategory
    let tier: RiskTier
    let kind: TaskKind
}

enum TaskRunStatus: Equatable {
    case pending
    case running
    case done(freed: Int64)
    case failed(String)
}
