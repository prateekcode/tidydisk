import AppKit

/// An application bundle found in /Applications or ~/Applications.
struct InstalledApp: Sendable {
    let path: String
    /// File name without ".app": what Finder shows.
    let name: String
    /// Every name the app goes by (file name, CFBundleName, CFBundleDisplayName).
    let names: [String]
    let bundleID: String
    let version: String
    let updated: Date?
}

/// One line of `apps-seen.json`: an app that was installed at `lastSeen`.
struct SeenApp: Codable, Sendable {
    var bundleID: String
    var name: String
    var lastSeen: Date
}

/// Library files with no installed app behind them, before sizing.
struct LeftoverCandidate: Sendable {
    let name: String
    let bundleID: String
    let paths: [String]
    /// Set when the app is known from the history; nil for an orphan.
    let lastSeen: Date?
}

/// What one pass over the disk found, before any sizing.
struct AppSurvey: Sendable {
    var apps: [(app: InstalledApp, files: [String])] = []
    var leftovers: [LeftoverCandidate] = []
    /// Reverse-DNS entries that were left out, with the rule that kept them (`--apps-report`).
    var skipped: [String] = []
}

/// One thing to move to the Trash: an app with its Library files, or leftovers alone.
struct RemovalTarget: Sendable {
    let name: String
    /// Nil for leftovers.
    let bundlePath: String?
    let files: [String]
    let bytes: Int64
}

struct RemovalOutcome: Sendable {
    let name: String
    var lines: [String] = []
    /// "path — reason" for everything that stayed where it was.
    var failures: [String] = []
    var movedCount = 0
    var freed: Int64 = 0
    /// False when the bundle could not be moved (its Library files are then left alone).
    var bundleMoved = true
}

/// Finds applications, the files they keep in ~/Library, and what uninstalled apps left behind.
enum AppScanner {
    static let ownBundleID = "com.riekapps.tidydisk"

    // MARK: - Installed apps

    /// Every `.app` in /Applications and ~/Applications, and one level of subfolders.
    static func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        var apps: [InstalledApp] = []
        var seen = Set<String>()

        func add(_ path: String) {
            guard seen.insert(path).inserted else { return }
            let url = URL(fileURLWithPath: path)
            // Safari and a few utilities are links into /System: part of macOS, not listed.
            guard !url.resolvingSymlinksInPath().path.hasPrefix("/System/") else { return }
            let info = Bundle(url: url)?.infoDictionary ?? [:]
            let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let names = [fileName, info["CFBundleName"] as? String, info["CFBundleDisplayName"] as? String]
                .compactMap { $0 }.filter { !$0.isEmpty }
            apps.append(InstalledApp(
                path: path,
                name: fileName,
                names: names,
                bundleID: info["CFBundleIdentifier"] as? String ?? "",
                version: info["CFBundleShortVersionString"] as? String
                    ?? info["CFBundleVersion"] as? String ?? "",
                updated: lastChanged(url)
            ))
        }

        for root in ["/Applications", NSHomeDirectory() + "/Applications"] {
            for entry in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where !entry.hasPrefix(".") {
                let path = root + "/" + entry
                if entry.hasSuffix(".app") {
                    add(path)
                } else if isDirectory(path) {
                    for child in (try? fm.contentsOfDirectory(atPath: path)) ?? []
                    where child.hasSuffix(".app") {
                        add(path + "/" + child)
                    }
                }
            }
        }
        return apps
    }

    /// When the bundle's contents last changed. Updaters swap `Contents` without touching the
    /// bundle folder, and unzipped apps carry a 1980 date, so the newest sane date of the three wins.
    private static func lastChanged(_ bundle: URL) -> Date? {
        let sane = Date(timeIntervalSinceReferenceDate: 0)
        return [bundle, bundle.appendingPathComponent("Contents"),
                bundle.appendingPathComponent("Contents/Info.plist")]
            .compactMap { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
            .filter { $0 > sane }
            .max()
    }

    /// TidyDisk itself: never offered for removal.
    static func isSelf(bundleID: String, path: String) -> Bool {
        bundleID.lowercased() == ownBundleID || path == Bundle.main.bundlePath
    }

    static func isRunning(bundleID: String) -> Bool {
        !bundleID.isEmpty && !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Library index

    /// ~/Library folders where an app keeps files named after its bundle id or its name.
    static let libraryFolders = [
        "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Logs",
        "Saved Application State", "HTTPStorages", "WebKit", "Cookies", "LaunchAgents",
    ]
    /// Sandboxed data. Reading these without Full Disk Access makes macOS prompt, so they are skipped then.
    static let protectedFolders = ["Containers", "Group Containers"]
    /// Folders where apps nest their data one level down ("Google/Chrome", "JetBrains/DataGrip2025.2").
    private static let vendorFolders: Set<String> = ["Application Support", "Caches", "Logs"]
    /// Folders searched for files of apps that are gone.
    private static let orphanFolders: Set<String> = [
        "Application Support", "Caches", "Preferences", "Saved Application State", "HTTPStorages",
    ]

    private struct Item {
        let path: String
        let folder: String
        /// File name as written on disk, without a `.plist` / `.savedState` / `.binarycookies`
        /// ending; for Group Containers also without the team or "group." prefix.
        let stem: String
        /// Lowercased stem.
        let key: String
    }

    /// Who a Library entry can belong to: an installed app, or one from the history.
    private struct Identity {
        /// As the app spells it.
        let exactID: String
        /// Lowercased.
        let bundleID: String
        let names: Set<String>
        /// Folder names its data may be nested under: the vendor part of the id, the first word of the name.
        let vendors: Set<String>
        let canOwnHelpers: Bool

        init(bundleID: String, names: [String]) {
            let id = bundleID.lowercased()
            let parts = id.split(separator: ".")
            exactID = bundleID
            self.bundleID = id
            self.names = Set(names.map { $0.lowercased() }.filter { $0.count >= 2 })
            canOwnHelpers = parts.count >= 3
            var vendors = Set<String>()
            if parts.count >= 3 { vendors.insert(String(parts[1])) }
            for name in self.names {
                let words = name.split(separator: " ")
                if words.count >= 2 { vendors.insert(String(words[0])) }
            }
            self.vendors = vendors
        }

        /// 0 when the entry is not ours; a longer bundle id wins over a shorter one, an id over a name.
        /// Helper ids must match the case too: "com.google.chrome.for.testing" is not Google Chrome's.
        func score(_ item: Item) -> Int {
            if !bundleID.isEmpty {
                if item.key == bundleID { return 2000 + bundleID.count }
                if canOwnHelpers, item.stem.hasPrefix(exactID + ".") { return 1000 + bundleID.count }
            }
            if !protectedFolders.contains(item.folder), names.contains(item.key) { return 500 }
            return 0
        }

        /// "Chrome" under "Google" for Google Chrome, "AndroidStudio2025.1" under "Google" for Android Studio.
        func ownsNested(_ child: String, under vendor: String) -> Bool {
            let entry = child.lowercased().replacingOccurrences(of: " ", with: "")
            for name in names {
                let full = name.replacingOccurrences(of: " ", with: "")
                if entry == full { return true }
                if entry.hasPrefix(full), entry.count > full.count,
                   entry.dropFirst(full.count).allSatisfy({ $0.isNumber || $0 == "." }) { return true }
                let words = name.split(separator: " ")
                if words.count >= 2, words[0] == vendor, entry == words.dropFirst().joined() { return true }
            }
            return false
        }
    }

    private static let strippedEndings = [".plist", ".savedstate", ".binarycookies"]

    private static func listLibrary(fullDiskAccess: Bool) -> [Item] {
        let fm = FileManager.default
        let library = NSHomeDirectory() + "/Library/"
        var items: [Item] = []
        for folder in libraryFolders + (fullDiskAccess ? protectedFolders : []) {
            for entry in (try? fm.contentsOfDirectory(atPath: library + folder)) ?? []
            where !entry.hasPrefix(".") {
                var stem = entry
                if let ending = strippedEndings.first(where: { entry.lowercased().hasSuffix($0) }) {
                    stem = String(entry.dropLast(ending.count))
                }
                if folder == "Group Containers" { stem = withoutGroupPrefix(stem) }
                items.append(Item(path: library + folder + "/" + entry, folder: folder,
                                  stem: stem, key: stem.lowercased()))
            }
        }
        return items
    }

    /// "group.com.vendor.app" and "ABCDE12345.com.vendor.app" → "com.vendor.app".
    private static func withoutGroupPrefix(_ name: String) -> String {
        if name.lowercased().hasPrefix("group.") { return String(name.dropFirst(6)) }
        let parts = name.split(separator: ".", maxSplits: 1)
        if parts.count == 2, parts[0].count == 10, parts[0].allSatisfy({ $0.isLetter || $0.isNumber }) {
            return String(parts[1])
        }
        return name
    }

    /// Hands every still-free entry to the identity that matches it best. Returns paths per identity.
    private static func claim(_ identities: [Identity], from free: inout [Item]) -> [[String]] {
        var paths = Array(repeating: [String](), count: identities.count)
        var remaining: [Item] = []
        for item in free {
            var best = (index: -1, score: 0)
            for (index, identity) in identities.enumerated() {
                let score = identity.score(item)
                if score > best.score { best = (index, score) }
            }
            if best.index >= 0 { paths[best.index].append(item.path) } else { remaining.append(item) }
        }
        free = remaining

        // Data nested under a vendor folder that nobody owns as a whole.
        let fm = FileManager.default
        var taken = Set<String>()
        var listings: [String: [String]] = [:]
        for (index, identity) in identities.enumerated() where !identity.vendors.isEmpty {
            for item in free where vendorFolders.contains(item.folder) && identity.vendors.contains(item.key) {
                if listings[item.path] == nil {
                    listings[item.path] = isDirectory(item.path)
                        ? ((try? fm.contentsOfDirectory(atPath: item.path)) ?? []) : []
                }
                for child in listings[item.path] ?? []
                where !child.hasPrefix(".") && identity.ownsNested(child, under: item.key) {
                    let path = item.path + "/" + child
                    if taken.insert(path).inserted { paths[index].append(path) }
                }
            }
        }
        return paths
    }

    // MARK: - Survey

    /// One pass over the disk: installed apps with their Library files, then what uninstalled
    /// apps left behind. Also records the installed apps in the history. No sizing here.
    static func survey(fullDiskAccess: Bool) -> AppSurvey {
        var survey = AppSurvey()
        let apps = installedApps()
        var free = listLibrary(fullDiskAccess: fullDiskAccess)

        let owned = claim(apps.map { Identity(bundleID: $0.bundleID, names: $0.names) }, from: &free)
        survey.apps = zip(apps, owned).map { (app: $0, files: $1.sorted()) }

        // History: what was installed on an earlier scan and is gone now.
        var history = loadHistory()
        let installedIDs = Set(apps.map { $0.bundleID.lowercased() })
        let gone = history.filter {
            !installedIDs.contains($0.bundleID.lowercased()) && !isInstalledAnywhere($0.bundleID)
        }
        let goneFiles = claim(gone.map { Identity(bundleID: $0.bundleID, names: [$0.name]) }, from: &free)
        for (seen, files) in zip(gone, goneFiles) where !files.isEmpty {
            survey.leftovers.append(LeftoverCandidate(name: seen.name, bundleID: seen.bundleID,
                                                      paths: files.sorted(), lastSeen: seen.lastSeen))
        }

        let orphans = findOrphans(in: free, installed: apps)
        survey.leftovers.append(contentsOf: orphans.found)
        survey.skipped = orphans.skipped

        let now = Date()
        for app in apps where !app.bundleID.isEmpty {
            let entry = SeenApp(bundleID: app.bundleID, name: app.name, lastSeen: now)
            if let index = history.firstIndex(where: { $0.bundleID.lowercased() == app.bundleID.lowercased() }) {
                history[index] = entry
            } else {
                history.append(entry)
            }
        }
        saveHistory(history)
        return survey
    }

    /// True when LaunchServices knows the app somewhere outside the Trash, or it is running.
    private static func isInstalledAnywhere(_ bundleID: String) -> Bool {
        guard !bundleID.isEmpty else { return false }
        if isRunning(bundleID: bundleID) { return true }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        return !url.path.contains("/.Trash/")
    }

    // MARK: - Orphans

    /// First labels a bundle id can start with. Anything else ("main.kts.compiled.cache") is not an app id.
    private static let topLevelLabels: Set<String> = [
        "com", "org", "net", "io", "dev", "app", "co", "me", "ai", "us", "uk", "de", "fr", "jp", "ch",
        "se", "nl", "it", "es", "at", "au", "ca", "cc", "tv", "edu", "info", "xyz", "sh", "so", "is",
        "im", "pl", "ru", "cn", "in", "br", "eu", "be", "dk", "fi", "no", "nz", "cz", "tech", "studio",
    ]
    /// Never offered: macOS itself, shared containers, and command-line tools, runtimes and SDKs
    /// that write a reverse-DNS folder without ever being an app bundle.
    private static let neverOrphans = [
        "com.apple.", "group.", "systemgroup.",
        "org.swift.", "org.llvm.", "org.python.", "org.cups.", "org.carthage.", "org.cocoapods.",
        "org.gradle.", "org.jetbrains.", "org.kotlinlang.", "org.nodejs.", "org.rust-lang.",
        "org.golang.", "org.openjdk.", "net.java.", "com.oracle.", "com.android.", "com.vercel.",
        "dev.biomejs.", "dev.flutter.", "com.firebase.", "com.crashlytics.", "io.fabric.",
        "com.plausiblelabs.", "com.segment.", "com.onevcat.", "com.github.", "com.electron.",
        "com.docker.", "io.sentry.", "com.facebook.", "com.microsoft.appcenter.",
    ]
    /// Id parts that mark a tool or a library cache rather than an app.
    private static let toolParts: Set<String> = ["cli", "sdk", "framework", "imagecache", "crashreporter"]
    /// Something still writes to it: leave it out.
    private static let recentlyUsed: TimeInterval = 3 * 86_400

    private static func isReverseDNS(_ key: String) -> Bool {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, topLevelLabels.contains(String(parts[0])) else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    private static func vendor(of id: String) -> String {
        id.split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// Reverse-DNS entries that no installed or running app can account for, grouped per app id.
    private static func findOrphans(in free: [Item], installed: [InstalledApp])
        -> (found: [LeftoverCandidate], skipped: [String]) {
        var groups: [String: (id: String, paths: [String])] = [:]
        for item in free where orphanFolders.contains(item.folder) && isReverseDNS(item.key) {
            groups[item.key, default: (item.stem, [])].paths.append(item.path)
        }
        // Helpers join their app: "com.vendor.app.ShipIt" goes under "com.vendor.app".
        for key in groups.keys.sorted(by: { $0.count > $1.count }) {
            let parent = groups.keys.filter { key.hasPrefix($0 + ".") }.min { $0.count < $1.count }
            if let parent, let child = groups.removeValue(forKey: key) {
                groups[parent]?.paths.append(contentsOf: child.paths)
            }
        }

        var knownIDs = installed.map { $0.bundleID.lowercased() }
        knownIDs += NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() }
        knownIDs = knownIDs.filter { !$0.isEmpty }
        let knownVendors = Set(knownIDs.map(vendor))

        var found: [LeftoverCandidate] = []
        var skipped: [String] = []
        for (key, group) in groups.sorted(by: { $0.key < $1.key }) {
            if let reason = orphanExclusion(key: key, id: group.id, paths: group.paths,
                                            knownIDs: knownIDs, knownVendors: knownVendors) {
                skipped.append("\(group.id): \(reason)")
            } else {
                found.append(LeftoverCandidate(name: group.id, bundleID: group.id,
                                               paths: group.paths.sorted(), lastSeen: nil))
            }
        }
        return (found, skipped)
    }

    /// Why an entry is not offered as a leftover; nil when every check says its app is gone.
    private static func orphanExclusion(key: String, id: String, paths: [String],
                                        knownIDs: [String], knownVendors: Set<String>) -> String? {
        if neverOrphans.contains(where: { key.hasPrefix($0) }) { return "system or developer tool" }
        let parts = key.split(separator: ".").map(String.init)
        if parts.contains(where: { toolParts.contains($0) }) { return "looks like a tool or a library cache" }
        if knownVendors.contains(vendor(of: key)) { return "same vendor as an installed app" }
        if knownIDs.contains(where: { key == $0 || key.hasPrefix($0 + ".") }) { return "helper of an installed app" }
        // The id itself and every shorter form of it, in case the app lives outside /Applications.
        let original = id.split(separator: ".").map(String.init)
        for length in stride(from: original.count, through: 3, by: -1) {
            if isInstalledAnywhere(original.prefix(length).joined(separator: ".")) {
                return "app found by LaunchServices"
            }
        }
        let fm = FileManager.default
        let newest = paths.compactMap { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }.max()
        if let newest, Date().timeIntervalSince(newest) < recentlyUsed { return "changed in the last 3 days" }
        return nil
    }

    // MARK: - Sizing

    /// Bundle and Library sizes of one app. Blocking (`du`); call off the main thread.
    static func measure(_ app: InstalledApp, files: [String]) -> AppInfo {
        let bundleBytes = Engine.size(of: [app.path])
        let libraryBytes = Engine.size(of: files)
        return AppInfo(path: app.path, name: app.name, bundleID: app.bundleID, version: app.version,
                       bytes: bundleBytes + libraryBytes, bundleBytes: bundleBytes,
                       libraryBytes: libraryBytes, libraryPaths: files, updated: app.updated)
    }

    static func measure(_ candidate: LeftoverCandidate) -> AppLeftover {
        AppLeftover(name: candidate.name, bundleID: candidate.bundleID, paths: candidate.paths,
                    bytes: Engine.size(of: candidate.paths), lastSeen: candidate.lastSeen)
    }

    // MARK: - History

    /// `~/Library/Application Support/TidyDisk/apps-seen.json` (TIDYDISK_APPS_SEEN overrides it for tests).
    static var historyURL: URL {
        if let override = ProcessInfo.processInfo.environment["TIDYDISK_APPS_SEEN"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/TidyDisk/apps-seen.json")
    }

    static func loadHistory() -> [SeenApp] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SeenApp].self, from: data)) ?? []
    }

    static func saveHistory(_ history: [SeenApp]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(history.sorted { $0.name.lowercased() < $1.name.lowercased() })
        else { return }
        try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: historyURL, options: .atomic)
    }

    // MARK: - Removing

    /// Only app bundles in the two Applications folders and entries at least two levels
    /// inside ~/Library may ever be moved ("~/Library/Caches" itself may not).
    static func isRemovable(_ path: String) -> Bool {
        let clean = (path as NSString).standardizingPath
        let home = NSHomeDirectory()
        let library = home + "/Library/"
        if clean.hasPrefix(library) {
            return clean.dropFirst(library.count).split(separator: "/").count >= 2
        }
        return clean.hasSuffix(".app")
            && (clean.hasPrefix("/Applications/") || clean.hasPrefix(home + "/Applications/"))
    }

    /// Moves the target to the Trash: the bundle first, its Library files only once the bundle
    /// is gone. With `dryRun` nothing is touched and the lines say what would be moved.
    static func remove(_ target: RemovalTarget, dryRun: Bool) -> RemovalOutcome {
        var outcome = RemovalOutcome(name: target.name)
        var stuck: [String] = []

        func move(_ path: String) -> Bool {
            guard isRemovable(path) else {
                outcome.lines.append("[skip] \(Engine.abbreviate(path)) is outside Applications and ~/Library")
                outcome.failures.append("\(Engine.abbreviate(path)): not a place TidyDisk removes from")
                stuck.append(path)
                return false
            }
            if dryRun {
                outcome.lines.append("[dry run] would move to Trash: \(Engine.abbreviate(path))")
                outcome.movedCount += 1
                return true
            }
            let line = Engine.trashFile(path)
            outcome.lines.append(line)
            if line.hasPrefix("[fail]") {
                outcome.failures.append(String(line.dropFirst("[fail] ".count)))
                stuck.append(path)
                return false
            }
            outcome.movedCount += 1
            return true
        }

        if let bundle = target.bundlePath, !move(bundle) {
            outcome.bundleMoved = false
            return outcome
        }
        for file in target.files where FileManager.default.fileExists(atPath: file) {
            _ = move(file)
        }
        outcome.freed = stuck.isEmpty ? target.bytes : max(0, target.bytes - Engine.size(of: stuck))
        return outcome
    }
}
