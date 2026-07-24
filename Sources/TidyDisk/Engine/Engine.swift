import Foundation

enum Engine {
    // MARK: - Shell

    /// PATH that includes Homebrew and common tool locations for npm/docker etc.
    private static let toolPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    @discardableResult
    static func run(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = toolPATH
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (127, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    // MARK: - Sizing

    /// Total size in bytes of the given paths (missing paths count as 0), via `du -sk`.
    static func size(of paths: [String]) -> Int64 {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return 0 }
        let (_, output) = run(["du", "-sk"] + existing)
        var totalKB: Int64 = 0
        for line in output.split(separator: "\n") {
            if let kb = Int64(line.split(separator: "\t").first ?? "") {
                totalKB += kb
            }
        }
        return totalKB * 1024
    }

    /// Directories named `dirNames` under `root`, pruned (no descent into matches).
    static func findDirectories(root: String, dirNames: [String]) -> [String] {
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        var args = ["find", root, "-type", "d", "("]
        for (i, name) in dirNames.enumerated() {
            if i > 0 { args.append("-o") }
            args.append(contentsOf: ["-name", name])
        }
        args.append(contentsOf: [")", "-prune", "-print"])
        let (_, output) = run(args)
        return output.split(separator: "\n").map(String.init)
            .filter { $0 != NSHomeDirectory() + "/.gradle" } // never the global gradle dir
    }

    /// All version-named children of `parent` except the newest (numeric-aware sort).
    static func allButNewestDirs(parent: String) -> [String] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(atPath: parent), children.count > 1 else { return [] }
        let sorted = children.sorted {
            $0.compare($1, options: [.numeric]) == .orderedAscending
        }
        return sorted.dropLast().map { (parent as NSString).appendingPathComponent($0) }
    }

    /// Existing cache subdirectories per app under `root`, e.g. "…/Trae/Cache".
    static func sweepTargets(root: String, subpaths: [String], exclude: [String]) -> [String] {
        let fm = FileManager.default
        guard let apps = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var targets: [String] = []
        for app in apps where !exclude.contains(app) {
            for sub in subpaths {
                let path = root + "/" + app + "/" + sub
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    targets.append(path)
                }
            }
        }
        return targets
    }

    static func scanSize(of task: CleanupTask) -> Int64 {
        switch task.kind {
        case .directoryContents(let dirs):
            return size(of: dirs)
        case .findAndRemove(let root, let dirNames):
            return size(of: findDirectories(root: root, dirNames: dirNames))
        case .commands(let scanPaths, _):
            return size(of: scanPaths)
        case .allButNewest(let parent):
            return size(of: allButNewestDirs(parent: parent))
        case .appCacheSweep(let root, let subpaths, let exclude):
            return size(of: sweepTargets(root: root, subpaths: subpaths, exclude: exclude))
        case .projectSweep(let dirNames):
            let dirs = discoverProjectRoots().flatMap { findDirectories(root: $0, dirNames: dirNames) }
            return size(of: dirs)
        }
    }

    // MARK: - Cleaning

    /// Executes the task. Returns log lines describing what happened.
    static func clean(_ task: CleanupTask) -> [String] {
        var log: [String] = []
        switch task.kind {
        case .directoryContents(let dirs):
            for dir in dirs {
                log.append(contentsOf: removeContents(of: dir))
            }
        case .findAndRemove(let root, let dirNames):
            for dir in findDirectories(root: root, dirNames: dirNames) {
                log.append(remove(path: dir))
            }
        case .allButNewest(let parent):
            let dirs = allButNewestDirs(parent: parent)
            if dirs.isEmpty { log.append("[skip] nothing older than the newest version") }
            for dir in dirs { log.append(remove(path: dir)) }
        case .appCacheSweep(let root, let subpaths, let exclude):
            for target in sweepTargets(root: root, subpaths: subpaths, exclude: exclude) {
                log.append(contentsOf: removeContents(of: target))
            }
        case .projectSweep(let dirNames):
            for root in discoverProjectRoots() {
                for dir in findDirectories(root: root, dirNames: dirNames) {
                    log.append(remove(path: dir))
                }
            }
        case .commands(_, let commands):
            for command in commands {
                let tool = command[0]
                if run(["which", tool]).status != 0 {
                    log.append("[skip] \(tool) not installed")
                    continue
                }
                // Docker needs its daemon up; `docker info` mirrors the script's check.
                if tool == "docker", run(["docker", "info"]).status != 0 {
                    log.append("[skip] docker not running")
                    continue
                }
                let (status, output) = run(command)
                let summary = output.split(separator: "\n").suffix(2).joined(separator: " · ")
                log.append("[\(status == 0 ? "done" : "fail")] \(command.joined(separator: " ")) \(summary)")
            }
        }
        return log
    }

    static func removeContents(of directory: String) -> [String] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(atPath: directory), !children.isEmpty else {
            return ["[skip] \(abbreviate(directory)) (nothing to remove)"]
        }
        var removed = 0
        var failed = 0
        for child in children {
            let path = (directory as NSString).appendingPathComponent(child)
            do {
                try fm.removeItem(atPath: path)
                removed += 1
            } catch {
                failed += 1
            }
        }
        var line = "[done] \(abbreviate(directory)) — removed \(removed) items"
        if failed > 0 { line += " (\(failed) locked/failed)" }
        return [line]
    }

    static func remove(path: String) -> String {
        do {
            try FileManager.default.removeItem(atPath: path)
            return "[done] \(abbreviate(path))"
        } catch {
            return "[fail] \(abbreviate(path)) — \(error.localizedDescription)"
        }
    }

    static func abbreviate(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: - Disk space

    static func freeDiskSpace() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    static func totalDiskSpace() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return Int64(values?.volumeTotalCapacity ?? 0)
    }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        if value <= 0 { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }

    /// Stable-width whole-GB string for the menu bar (no decimal jitter).
    static func wholeGB(_ value: Int64) -> String {
        "\(Int((Double(value) / 1_000_000_000).rounded())) GB"
    }
}
