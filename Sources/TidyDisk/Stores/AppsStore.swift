import Foundation

struct AppInfo: Identifiable, Sendable {
    let path: String
    let name: String
    let bundleID: String
    let version: String
    /// Bundle + its files in ~/Library.
    let bytes: Int64
    var bundleBytes: Int64 = 0
    var libraryBytes: Int64 = 0
    /// What uninstalling removes besides the bundle.
    var libraryPaths: [String] = []
    /// When the bundle last changed on this Mac.
    var updated: Date?
    var id: String { path }

    var isApple: Bool { bundleID.lowercased().hasPrefix("com.apple.") }
    var isTidyDisk: Bool { AppScanner.isSelf(bundleID: bundleID, path: path) }
    /// Apple apps and TidyDisk itself are listed but never removed.
    var isProtected: Bool { isApple || isTidyDisk }
}

/// Files in ~/Library whose app is no longer installed.
struct AppLeftover: Identifiable, Sendable {
    let name: String
    let bundleID: String
    let paths: [String]
    let bytes: Int64
    /// When a scan last saw the app installed; nil when it is only known from its files.
    var lastSeen: Date?
    var id: String { bundleID.isEmpty ? name : bundleID.lowercased() }
}

/// A removal waiting for the user's yes.
struct AppRemovalRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let targets: [RemovalTarget]
}

struct AppsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Installed applications, their leftovers, and uninstalling.
@MainActor
final class AppsStore: ObservableObject {
    /// Largest first.
    @Published var apps: [AppInfo] = []
    @Published var scanned = false
    @Published var scanning = false

    /// Largest first. Files of apps that are gone (history) or were never seen (orphans).
    @Published var leftovers: [AppLeftover] = []
    /// `AppInfo.id`s ticked for uninstalling. Nothing is ever ticked for the user.
    @Published var selectedApps: Set<String> = []
    /// `AppLeftover.id`s ticked for the Trash.
    @Published var selectedLeftovers: Set<String> = []
    @Published var lastScanned: Date?
    /// Apps sized so far in the running scan, and how many there are.
    @Published var sized = 0
    @Published var found = 0
    /// False when sandboxed data (Containers) had to be left out of the sizes.
    @Published var fullDiskAccess = true
    @Published var removing = false
    @Published var confirmation: AppRemovalRequest?
    @Published var notice: AppsNotice?

    private static let parallelScans = 4

    var totalBytes: Int64 { apps.reduce(0) { $0 + $1.bytes } }
    var leftoverBytes: Int64 { leftovers.reduce(0) { $0 + $1.bytes } }
    var selectedAppBytes: Int64 { apps.filter { selectedApps.contains($0.id) }.reduce(0) { $0 + $1.bytes } }

    // MARK: - Scanning

    func scan() {
        guard !scanning, !removing else { return }
        scanning = true
        sized = 0
        found = 0
        let access = Engine.hasFullDiskAccess()
        fullDiskAccess = access

        Task {
            let survey = await Task.detached(priority: .userInitiated) {
                AppScanner.survey(fullDiskAccess: access)
            }.value

            // Rows of apps that are gone leave now; the rest update in place as they are sized.
            let paths = Set(survey.apps.map(\.app.path))
            apps.removeAll { !paths.contains($0.id) }
            found = survey.apps.count

            await Self.inParallel(survey.apps, limit: Self.parallelScans) { entry in
                AppScanner.measure(entry.app, files: entry.files)
            } each: { [weak self] info in
                self?.upsert(info)
                self?.sized += 1
            }

            var rows: [AppLeftover] = []
            await Self.inParallel(survey.leftovers, limit: Self.parallelScans) { candidate in
                AppScanner.measure(candidate)
            } each: { row in
                if row.bytes > 0 { rows.append(row) }
            }
            leftovers = rows.sorted { $0.bytes > $1.bytes }

            selectedApps.formIntersection(apps.filter { !$0.isProtected }.map(\.id))
            selectedLeftovers.formIntersection(leftovers.map(\.id))
            lastScanned = Date()
            scanned = true
            scanning = false

            if CommandLine.arguments.contains("--apps-report") { printReport(skipped: survey.skipped) }
        }
    }

    private func upsert(_ info: AppInfo) {
        apps.removeAll { $0.id == info.id }
        let index = apps.firstIndex { $0.bytes < info.bytes } ?? apps.endIndex
        apps.insert(info, at: index)
    }

    /// Runs `work` for every input off the main thread, at most `limit` at a time,
    /// and hands each result to `each` on the caller's actor as soon as it is ready.
    private static func inParallel<Input: Sendable, Output: Sendable>(
        _ inputs: [Input], limit: Int,
        work: @escaping @Sendable (Input) -> Output,
        each: @MainActor (Output) -> Void
    ) async {
        await withTaskGroup(of: Output.self) { group in
            var next = 0
            func startOne() {
                guard next < inputs.count else { return }
                let input = inputs[next]
                next += 1
                group.addTask { work(input) }
            }
            for _ in 0..<limit { startOne() }
            for await output in group {
                each(output)
                startOne()
            }
        }
    }

    // MARK: - Selection

    func toggleApp(_ app: AppInfo) {
        guard !app.isProtected else { return }
        if selectedApps.contains(app.id) { selectedApps.remove(app.id) } else { selectedApps.insert(app.id) }
    }

    func toggleLeftover(_ leftover: AppLeftover) {
        if selectedLeftovers.contains(leftover.id) {
            selectedLeftovers.remove(leftover.id)
        } else {
            selectedLeftovers.insert(leftover.id)
        }
    }

    func toggleAllLeftovers() {
        selectedLeftovers = selectedLeftovers.count == leftovers.count ? [] : Set(leftovers.map(\.id))
    }

    // MARK: - Removing

    /// Why this app stays; nil when it may be uninstalled right now.
    func refusal(for app: AppInfo) -> String? {
        if app.isTidyDisk { return "TidyDisk cannot uninstall itself." }
        if app.isApple { return "\(app.name) is made by Apple and stays." }
        if AppScanner.isRunning(bundleID: app.bundleID) { return "Quit \(app.name) first." }
        return nil
    }

    /// Checks the ticked apps and asks for confirmation; apps that must stay are named, not touched.
    func requestUninstall() {
        let chosen = apps.filter { selectedApps.contains($0.id) }
        guard !chosen.isEmpty, !removing else { return }
        let refusals = chosen.compactMap { refusal(for: $0) }
        let allowed = chosen.filter { refusal(for: $0) == nil }
        guard !allowed.isEmpty else {
            notice = AppsNotice(title: "Nothing was uninstalled", message: refusals.joined(separator: "\n"))
            return
        }
        let files = allowed.reduce(0) { $0 + $1.libraryPaths.count }
        let bytes = allowed.reduce(0) { $0 + $1.bytes }
        var message = "\(Self.list(allowed.map(\.name))) will be moved to the Trash"
        message += files > 0 ? " with \(Self.plural(files, "file")) from ~/Library" : ""
        message += ", \(Format.bytes(bytes)) in total. You can put everything back until you empty the Trash."
        if !refusals.isEmpty { message += "\n\nLeft alone: " + refusals.joined(separator: " ") }
        confirmation = AppRemovalRequest(
            title: "Uninstall \(Self.plural(allowed.count, "app"))?",
            message: message,
            targets: allowed.map {
                RemovalTarget(name: $0.name, bundlePath: $0.path, files: $0.libraryPaths, bytes: $0.bytes)
            }
        )
    }

    func requestTrashLeftovers() {
        let chosen = leftovers.filter { selectedLeftovers.contains($0.id) }
        guard !chosen.isEmpty, !removing else { return }
        let files = chosen.reduce(0) { $0 + $1.paths.count }
        let bytes = chosen.reduce(0) { $0 + $1.bytes }
        confirmation = AppRemovalRequest(
            title: "Move leftovers of \(Self.plural(chosen.count, "app")) to the Trash?",
            message: "\(Self.plural(files, "file")) left in ~/Library by \(Self.list(chosen.map(\.name))), "
                + "\(Format.bytes(bytes)) in total. You can put everything back until you empty the Trash.",
            targets: chosen.map { RemovalTarget(name: $0.name, bundlePath: nil, files: $0.paths, bytes: $0.bytes) }
        )
    }

    /// Runs a confirmed removal. Only ever called from the confirmation alert.
    func perform(_ request: AppRemovalRequest) {
        guard !removing else { return }
        // An app may have been opened while the alert was up.
        var quitFirst: [String] = []
        let targets = request.targets.filter { target in
            guard let bundle = target.bundlePath, let app = apps.first(where: { $0.id == bundle }),
                  AppScanner.isRunning(bundleID: app.bundleID) else { return true }
            quitFirst.append("Quit \(app.name) first.")
            return false
        }
        removing = true
        Task {
            let outcomes = await Task.detached(priority: .userInitiated) {
                targets.map { AppScanner.remove($0, dryRun: false) }
            }.value

            var problems = quitFirst
            var freed: Int64 = 0
            for (target, outcome) in zip(targets, outcomes) {
                outcome.lines.forEach { ActivityLog.shared.add($0) }
                freed += outcome.freed
                if let bundle = target.bundlePath {
                    if outcome.bundleMoved {
                        apps.removeAll { $0.id == bundle }
                        selectedApps.remove(bundle)
                        ActivityLog.shared.add("[apps] Uninstalled \(target.name): \(Self.plural(outcome.movedCount, "item")) moved to Trash, \(Format.bytes(outcome.freed))")
                    } else {
                        problems.append("\(target.name) could not be moved to the Trash. Apps installed by the App Store or an installer can belong to the system. Its files in ~/Library were left in place.")
                    }
                } else {
                    ActivityLog.shared.add("[apps] Leftovers of \(target.name): \(Self.plural(outcome.movedCount, "item")) moved to Trash, \(Format.bytes(outcome.freed))")
                    if outcome.failures.isEmpty {
                        leftovers.removeAll { $0.name == target.name && $0.paths == target.files }
                    }
                }
                problems.append(contentsOf: outcome.failures)
            }
            selectedLeftovers.formIntersection(leftovers.map(\.id))
            if freed > 0 { Engine.reportFreed(freed) }
            removing = false
            if !problems.isEmpty {
                notice = AppsNotice(title: "Some things stayed where they were",
                                    message: problems.joined(separator: "\n"))
                scan()
            }
        }
    }

    // MARK: - Wording

    static func plural(_ count: Int, _ noun: String) -> String {
        "\(Format.count(count)) \(noun)\(count == 1 ? "" : "s")"
    }

    /// "Slack", "Slack and Muse", "Slack, Muse, Figma and 4 more".
    static func list(_ names: [String]) -> String {
        var shown = Array(names.prefix(4))
        if names.count > shown.count { shown.append("\(names.count - shown.count) more") }
        guard let last = shown.popLast() else { return "" }
        return shown.isEmpty ? last : shown.joined(separator: ", ") + " and " + last
    }

    // MARK: - Dry run

    /// `--apps-report`: prints what the scan found and what every removal would move, touching nothing.
    private func printReport(skipped: [String]) {
        print("== Applications: \(apps.count), \(Format.bytes(totalBytes)) (Full Disk Access: \(fullDiskAccess))")
        for app in apps {
            print("\(app.name) | \(app.bundleID) | v\(app.version) | bundle \(Format.bytes(app.bundleBytes)) + library \(Format.bytes(app.libraryBytes))")
            if let refusal = refusal(for: app) {
                print("    refused: \(refusal)")
                app.libraryPaths.forEach { print("    library: \(Engine.abbreviate($0))") }
            } else {
                let target = RemovalTarget(name: app.name, bundlePath: app.path, files: app.libraryPaths, bytes: app.bytes)
                AppScanner.remove(target, dryRun: true).lines.forEach { print("    \($0)") }
            }
        }
        print("== Leftovers: \(leftovers.count), \(Format.bytes(leftoverBytes))")
        for leftover in leftovers {
            let source = leftover.lastSeen.map { "last seen installed \(Format.ago($0))" } ?? "no matching app installed"
            print("\(leftover.name) | \(source) | \(Format.bytes(leftover.bytes))")
            let target = RemovalTarget(name: leftover.name, bundlePath: nil, files: leftover.paths, bytes: leftover.bytes)
            AppScanner.remove(target, dryRun: true).lines.forEach { print("    \($0)") }
        }
        print("== Left out of leftovers: \(skipped.count)")
        skipped.forEach { print("    \($0)") }
    }
}
