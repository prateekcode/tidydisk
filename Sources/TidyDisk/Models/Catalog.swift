import Foundation

/// Builds the task list for *this* Mac: every task is included only if the tool,
/// app, or directory it targets actually exists here. Tiers mirror ~/cleanup.sh:
/// safe = default run, aggressive = --aggressive, nuclear = --nuclear.
enum Catalog {
    static let home = NSHomeDirectory()

    static func build() -> [CleanupTask] {
        let fm = FileManager.default
        func exists(_ path: String) -> Bool { fm.fileExists(atPath: path) }
        func existing(_ paths: [String]) -> [String] { paths.filter(exists) }
        func hasTool(_ name: String) -> Bool { Engine.run(["which", name]).status == 0 }

        var tasks: [CleanupTask] = []
        func add(_ id: String, _ name: String, _ detail: String, _ icon: String,
                 _ category: TaskCategory, _ tier: RiskTier, _ kind: TaskKind) {
            tasks.append(CleanupTask(id: id, name: name, detail: detail, icon: icon,
                                     category: category, tier: tier, kind: kind))
        }

        // ---- Safe ----

        let gradleDirs = existing([home + "/.gradle/caches", home + "/.gradle/daemon",
                                   home + "/.gradle/wrapper/dists"])
        if !gradleDirs.isEmpty {
            add("gradle", "Gradle caches", "~/.gradle caches, daemons & wrapper dists",
                "gearshape.2.fill", .devCaches, .safe, .directoryContents(gradleDirs))
        }

        if exists(home + "/Library/Developer/Xcode/DerivedData") {
            add("derived-data", "Xcode DerivedData", "Build intermediates — Xcode rebuilds them",
                "hammer.fill", .xcode, .safe,
                .directoryContents([home + "/Library/Developer/Xcode/DerivedData"]))
        }
        if exists(home + "/Library/Caches/com.apple.dt.Xcode") {
            add("xcode-caches", "Xcode caches", "Module cache & other Xcode leftovers",
                "wrench.and.screwdriver.fill", .xcode, .safe,
                .directoryContents([home + "/Library/Caches/com.apple.dt.Xcode"]))
        }
        if exists(home + "/Library/Caches/CocoaPods") {
            add("cocoapods", "CocoaPods cache", "Downloaded pod archives",
                "shippingbox.fill", .devCaches, .safe,
                .directoryContents([home + "/Library/Caches/CocoaPods"]))
        }

        // Build artifacts inside any discovered project on this Mac
        add("project-artifacts", "Project build artifacts",
            ".dart_tool, build, Pods, .gradle in your projects",
            "folder.fill.badge.gearshape", .devCaches, .safe,
            .projectSweep(dirNames: [".dart_tool", "build", "Pods", ".gradle"]))

        var pkgCommands: [[String]] = []
        if hasTool("npm") { pkgCommands.append(["npm", "cache", "clean", "--force"]) }
        if hasTool("pnpm") { pkgCommands.append(["pnpm", "store", "prune"]) }
        if hasTool("yarn") { pkgCommands.append(["yarn", "cache", "clean"]) }
        if !pkgCommands.isEmpty {
            add("pkg-managers", "npm / pnpm / yarn caches", "Package manager download caches",
                "cube.box.fill", .devCaches, .safe,
                .commands(scanPaths: existing([home + "/.npm/_cacache",
                                               home + "/Library/pnpm/store",
                                               home + "/Library/Caches/Yarn"]),
                          commands: pkgCommands))
        }

        if hasTool("brew") {
            add("homebrew", "Homebrew cleanup", "Old formula versions & download cache",
                "mug.fill", .devCaches, .safe,
                .commands(scanPaths: existing([home + "/Library/Caches/Homebrew"]),
                          commands: [["brew", "cleanup", "--prune=all"]]))
        }
        if exists(home + "/Library/Caches/org.swift.swiftpm") {
            add("swiftpm-cache", "SwiftPM cache", "Swift package manager download cache",
                "swift", .devCaches, .safe,
                .directoryContents([home + "/Library/Caches/org.swift.swiftpm"]))
        }

        // Any app-updater leftovers in ~/Library/Caches (VS Code ShipIt, *-updater…)
        let cachesDir = home + "/Library/Caches"
        let updaterDirs = ((try? fm.contentsOfDirectory(atPath: cachesDir)) ?? [])
            .filter { $0.hasSuffix("-updater") || $0.hasSuffix(".ShipIt") }
            .map { cachesDir + "/" + $0 }
        if !updaterDirs.isEmpty {
            add("updater-leftovers", "App updater leftovers", "Downloaded update archives",
                "arrow.down.circle.fill", .appCaches, .safe, .directoryContents(updaterDirs))
        }

        add("trash", "Trash", "Empty ~/.Trash",
            "trash.fill", .system, .safe, .directoryContents([home + "/.Trash"]))
        if exists(home + "/Library/Logs/DiagnosticReports") {
            add("diagnostics", "Diagnostic reports", "Old crash & spin reports",
                "waveform.path.ecg", .system, .safe,
                .directoryContents([home + "/Library/Logs/DiagnosticReports"]))
        }

        // ---- Aggressive ----

        if exists(home + "/Library/Caches/Google/Chrome") {
            add("chrome", "Chrome caches", "Chrome re-downloads what it needs",
                "globe", .appCaches, .aggressive,
                .directoryContents([home + "/Library/Caches/Google/Chrome"]))
        }
        let slackDirs = existing([
            home + "/Library/Application Support/Slack/Cache",
            home + "/Library/Application Support/Slack/Service Worker/CacheStorage",
            home + "/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Caches",
        ])
        if !slackDirs.isEmpty {
            add("slack", "Slack caches", "Slack app & service worker caches",
                "bubble.left.and.bubble.right.fill", .appCaches, .aggressive,
                .directoryContents(slackDirs))
        }
        let vscodeDirs = existing([
            home + "/Library/Caches/com.microsoft.VSCode",
            home + "/Library/Application Support/Code/Cache",
            home + "/Library/Application Support/Code/CachedData",
            home + "/Library/Application Support/Code/Code Cache",
        ])
        if !vscodeDirs.isEmpty {
            add("vscode", "VS Code caches", "Editor caches & cached data",
                "chevron.left.forwardslash.chevron.right", .appCaches, .aggressive,
                .directoryContents(vscodeDirs))
        }
        if exists(home + "/Library/Caches/JetBrains") {
            add("jetbrains", "JetBrains caches", "IDE indexes — rebuilt on next launch",
                "brain.head.profile", .appCaches, .aggressive,
                .directoryContents([home + "/Library/Caches/JetBrains"]))
        }
        add("electron-caches", "Electron app caches", "Cache dirs of chromium-based apps",
            "atom", .appCaches, .aggressive,
            .appCacheSweep(root: home + "/Library/Application Support",
                           subpaths: ["Cache", "Code Cache", "GPUCache", "CachedData",
                                      "Service Worker/CacheStorage"],
                           exclude: ["Slack", "Code"]))

        if exists(home + "/Library/Developer/Xcode/iOS DeviceSupport") {
            add("device-support", "iOS DeviceSupport", "Re-created when you plug a device in",
                "iphone.gen3", .xcode, .aggressive,
                .directoryContents([home + "/Library/Developer/Xcode/iOS DeviceSupport"]))
        }
        if exists(home + "/Library/Developer/Xcode/Archives") {
            add("xcode-archives", "Xcode Archives", "Old app archives — keep if you need to symbolicate",
                "archivebox.fill", .xcode, .aggressive,
                .directoryContents([home + "/Library/Developer/Xcode/Archives"]))
        }
        if exists(home + "/Library/Developer/CoreSimulator/Devices") {
            add("simulators", "Unused simulators", "Unavailable devices + runtimes untouched for 60 days",
                "iphone.slash", .xcode, .aggressive,
                .commands(scanPaths: [home + "/Library/Developer/CoreSimulator/Devices"],
                          commands: [["xcrun", "simctl", "delete", "unavailable"],
                                     ["xcrun", "simctl", "runtime", "delete", "--notUsedSinceDays", "60"]]))
        }

        if exists(home + "/.cache/codex-runtimes") {
            add("codex-runtimes", "Codex CLI runtimes", "Re-downloaded on next codex run",
                "terminal.fill", .devCaches, .aggressive,
                .directoryContents([home + "/.cache/codex-runtimes"]))
        }
        if exists(home + "/.pub-cache") && hasTool("dart") {
            add("pub-cache", "Dart pub cache", "Re-fetched on next flutter pub get",
                "bird.fill", .devCaches, .aggressive,
                .commands(scanPaths: [home + "/.pub-cache"],
                          commands: [["dart", "pub", "cache", "clean", "-f"]]))
        }
        if hasTool("docker") || exists(home + "/Library/Containers/com.docker.docker") {
            add("docker", "Docker prune", "docker system prune -af --volumes",
                "cube.transparent.fill", .docker, .aggressive,
                .commands(scanPaths: existing([home + "/Library/Containers/com.docker.docker/Data/vms"]),
                          commands: [["docker", "system", "prune", "-af", "--volumes"]]))
        }
        let ndkParent = home + "/Library/Android/sdk/ndk"
        if !Engine.allButNewestDirs(parent: ndkParent).isEmpty {
            add("old-ndks", "Old Android NDKs", "Keeps only the newest NDK version",
                "cpu.fill", .devCaches, .aggressive, .allButNewest(parent: ndkParent))
        }

        // ---- Nuclear ----

        add("node-modules", "node_modules", "node_modules in all your projects — reinstall needed after",
            "exclamationmark.triangle.fill", .nuclear, .nuclear,
            .projectSweep(dirNames: ["node_modules"]))

        return tasks
    }
}
