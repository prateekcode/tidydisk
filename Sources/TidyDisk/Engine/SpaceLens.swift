import Foundation

struct ProjectInfo: Identifiable {
    let path: String
    let name: String
    let totalBytes: Int64
    /// Reclaimable artifact dirs inside the project (node_modules, build, …) with sizes.
    let artifacts: [(path: String, bytes: Int64)]

    var id: String { path }
    var artifactBytes: Int64 { artifacts.reduce(0) { $0 + $1.bytes } }
}

struct LargeFile: Identifiable {
    let path: String
    let bytes: Int64
    let modified: Date

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
}

extension Engine {
    static let projectArtifactNames = ["node_modules", "build", ".dart_tool", "Pods", ".gradle"]

    // MARK: - Project discovery (Mac-wide)

    /// Files/dirs whose presence marks a directory as a dev project (.git is handled separately).
    private static let projectMarkers = [
        "package.json", "pubspec.yaml", "Podfile", "go.mod", "Cargo.toml",
        "build.gradle", "build.gradle.kts", "settings.gradle", "*.xcodeproj",
    ]
    /// Directories never descended into. All other hidden dirs are pruned wholesale
    /// (IDE state like ~/.antigravity contains package.json files that aren't projects).
    private static let discoveryPrunes = [
        "Library", "Applications", "Music", "Movies", "Pictures", "Public",
        "node_modules", "Pods",
    ]

    private static var projectRootsCache: [String]?

    /// Top-most directories under ~ (depth ≤ 4) containing a project marker.
    static func discoverProjectRoots(refresh: Bool = false) -> [String] {
        if !refresh, let cached = projectRootsCache { return cached }
        let home = NSHomeDirectory()
        // .git: mark as project, never descend. Then prune every other dotdir + heavy dirs.
        var args = ["find", home, "-maxdepth", "4",
                    "(", "-name", ".git", "-print", "-prune", ")", "-o",
                    "(", "-name", ".*"]
        for name in discoveryPrunes {
            args.append(contentsOf: ["-o", "-name", name])
        }
        args.append(contentsOf: [")", "-prune", "-o", "("])
        for (i, marker) in projectMarkers.enumerated() {
            if i > 0 { args.append("-o") }
            args.append(contentsOf: ["-name", marker])
        }
        args.append(contentsOf: [")", "-print"])

        let (_, output) = run(args)
        let candidates = Set(output.split(separator: "\n").map {
            (String($0) as NSString).deletingLastPathComponent
        }).filter { $0 != home }

        // Keep only top-most roots (a repo's sub-packages belong to the repo).
        var roots: [String] = []
        for path in candidates.sorted() {
            if let last = roots.last, path.hasPrefix(last + "/") { continue }
            roots.append(path)
        }
        projectRootsCache = roots
        return roots
    }

    // MARK: - Projects (Space Lens)

    static func scanProject(at path: String) -> ProjectInfo {
        let artifactPaths = findDirectories(root: path, dirNames: projectArtifactNames)
        var artifacts: [(String, Int64)] = artifactPaths.map { ($0, size(of: [$0])) }
        artifacts.sort { $0.1 > $1.1 }
        return ProjectInfo(
            path: path,
            name: (path as NSString).lastPathComponent,
            totalBytes: size(of: [path]),
            artifacts: artifacts
        )
    }

    /// Deletes a project's artifact dirs; returns log lines.
    static func cleanProjectArtifacts(_ project: ProjectInfo) -> [String] {
        project.artifacts.map { remove(path: $0.path) }
    }

    // MARK: - Large files

    static func findLargeFiles(minMB: Int = 200) -> [LargeFile] {
        let home = NSHomeDirectory()
        let (_, output) = run([
            "find", home,
            "(", "-path", home + "/Library", "-o", "-path", home + "/.Trash", ")", "-prune",
            "-o", "-type", "f", "-size", "+\(minMB)M", "-print",
        ])
        let fm = FileManager.default
        var files: [LargeFile] = []
        for line in output.split(separator: "\n") {
            let path = String(line)
            guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
            files.append(LargeFile(
                path: path,
                bytes: (attrs[.size] as? Int64) ?? 0,
                modified: (attrs[.modificationDate] as? Date) ?? .distantPast
            ))
        }
        return files.sorted { $0.bytes > $1.bytes }
    }

    /// Moves a file to Trash (recoverable, unlike the cache cleaners).
    static func trashFile(_ path: String) -> String {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            return "[trash] \(abbreviate(path))"
        } catch {
            return "[fail] \(abbreviate(path)) — \(error.localizedDescription)"
        }
    }
}
