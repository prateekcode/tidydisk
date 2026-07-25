import SwiftUI
import UserNotifications

enum AppPhase: Equatable {
    case welcome
    case scanning
    case review
    case cleaning
    case done
}

enum SidebarItem: Hashable {
    case smartScan
    case projects
    case largeFiles
    case duplicates
    case category(TaskCategory)
    case settings
    case log
}

@MainActor
final class AppState: ObservableObject {
    /// Built for this machine: only tasks whose tools/apps/dirs exist here.
    let tasks = Catalog.build()

    /// Only categories that have at least one detected task on this Mac.
    var categories: [TaskCategory] {
        TaskCategory.allCases.filter { category in tasks.contains { $0.category == category } }
    }

    func tasks(in category: TaskCategory) -> [CleanupTask] {
        tasks.filter { $0.category == category }
    }

    @Published var phase: AppPhase = .welcome
    @Published var sidebar: SidebarItem = .smartScan

    @Published var sizes: [String: Int64] = [:]
    @Published var scannedCount = 0
    @Published var scanningTaskName = ""
    @Published var hasScanned = false

    @Published var selected: Set<String> = []
    @Published var runStatus: [String: TaskRunStatus] = [:]
    @Published var freedTotal: Int64 = 0
    @Published var log: [String] = []

    @Published var freeSpace: Int64 = Engine.freeDiskSpace()
    let totalSpace: Int64 = Engine.totalDiskSpace()

    var isBusy: Bool { phase == .scanning || phase == .cleaning }

    func size(of task: CleanupTask) -> Int64 { sizes[task.id] ?? 0 }

    func totalJunk(tier: RiskTier? = nil) -> Int64 {
        tasks.filter { tier == nil || $0.tier == tier }
            .reduce(0) { $0 + size(of: $1) }
    }

    var selectedJunk: Int64 {
        tasks.filter { selected.contains($0.id) }.reduce(0) { $0 + size(of: $1) }
    }

    // MARK: - Scan

    func startScan() {
        guard !isBusy else { return }
        withAnimation(.spring(duration: 0.5)) {
            sidebar = .smartScan
            phase = .scanning
        }
        sizes = [:]
        scannedCount = 0
        appendLog("— Scan started —")

        Task {
            // Re-discover projects first so projectSweep tasks see the current Mac.
            scanningTaskName = "Finding projects…"
            let roots = await Task.detached(priority: .userInitiated) {
                Engine.discoverProjectRoots(refresh: true)
            }.value
            appendLog("[scan] discovered \(roots.count) projects")
            for task in tasks {
                scanningTaskName = task.name
                let size = await Task.detached(priority: .userInitiated) {
                    Engine.scanSize(of: task)
                }.value
                withAnimation(.spring(duration: 0.35)) {
                    sizes[task.id] = size
                    scannedCount += 1
                }
                appendLog("[scan] \(task.name): \(Format.bytes(size))")
            }
            hasScanned = true
            // Pre-select the safe tier, like running cleanup.sh with no flags.
            selected = Set(tasks.filter { $0.tier == .safe && size(of: $0) > 0 }.map(\.id))
            appendLog("— Scan finished: \(Format.bytes(totalJunk())) of junk found —")
            withAnimation(.spring(duration: 0.5)) { phase = .review }
        }
    }

    // MARK: - Clean

    func startClean(taskIDs: Set<String>? = nil) {
        guard !isBusy else { return }
        if let taskIDs { selected = taskIDs }
        guard !selected.isEmpty else { return }

        sidebar = .smartScan
        runStatus = tasks.reduce(into: [:]) { result, task in
            if selected.contains(task.id) { result[task.id] = .pending }
        }
        freedTotal = 0
        appendLog("— Cleanup started —")
        withAnimation(.spring(duration: 0.5)) { phase = .cleaning }

        Task {
            for task in tasks where selected.contains(task.id) {
                withAnimation { runStatus[task.id] = .running }
                let before = size(of: task)
                let lines = await Task.detached(priority: .userInitiated) {
                    Engine.clean(task)
                }.value
                let after = await Task.detached { Engine.scanSize(of: task) }.value
                let freed = max(0, before - after)
                appendLog("[clean] \(task.name):")
                lines.forEach { appendLog("    " + $0) }
                withAnimation(.spring(duration: 0.35)) {
                    sizes[task.id] = after
                    runStatus[task.id] = .done(freed: freed)
                    freedTotal += freed
                }
            }
            freeSpace = Engine.freeDiskSpace()
            appendLog("— Cleanup finished: \(Format.bytes(freedTotal)) freed · \(Format.bytes(freeSpace)) now free —")
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(.spring(duration: 0.6)) { phase = .done }
        }
    }

    // MARK: - Projects (Space Lens)

    @Published var projects: [ProjectInfo] = []
    @Published var projectsScanning = false
    @Published var projectCleaning: Set<String> = []

    func scanProjects() {
        guard !projectsScanning else { return }
        projectsScanning = true
        Task {
            let dirs = await Task.detached(priority: .userInitiated) {
                Engine.discoverProjectRoots(refresh: true)
            }.value
            var result: [ProjectInfo] = []
            for dir in dirs {
                let info = await Task.detached(priority: .userInitiated) {
                    Engine.scanProject(at: dir)
                }.value
                result.append(info)
                withAnimation(.spring(duration: 0.35)) {
                    projects = result.sorted { $0.totalBytes > $1.totalBytes }
                }
            }
            projectsScanning = false
        }
    }

    func cleanProject(_ project: ProjectInfo) {
        guard requirePro() else { return }
        guard !projectCleaning.contains(project.path) else { return }
        projectCleaning.insert(project.path)
        appendLog("— Cleaning project \(project.name) —")
        Task {
            let lines = await Task.detached(priority: .userInitiated) {
                Engine.cleanProjectArtifacts(project)
            }.value
            lines.forEach { appendLog("    " + $0) }
            let rescanned = await Task.detached { Engine.scanProject(at: project.path) }.value
            withAnimation(.spring(duration: 0.35)) {
                if let index = projects.firstIndex(where: { $0.path == project.path }) {
                    projects[index] = rescanned
                }
                projectCleaning.remove(project.path)
            }
            freeSpace = Engine.freeDiskSpace()
        }
    }

    // MARK: - Project actions (GitHub / cloud archive)

    /// path → short label of the running activity ("Cleaning…", "Pushing…", "Archiving…")
    @Published var projectActivity: [String: String] = [:]
    @Published var archivePrompt: ArchivePrompt?

    struct ArchivePrompt: Identifiable {
        let project: ProjectInfo
        let destinationName: String
        let zipPath: String
        var id: String { zipPath }
    }

    @Published var cloudDestinations = Engine.cloudDestinations()

    /// Failure surfaced as an alert (log has the full detail).
    @Published var actionAlert: String?

    func pushProjectToGitHub(_ project: ProjectInfo) {
        guard requirePro() else { return }
        guard projectActivity[project.path] == nil else { return }
        projectActivity[project.path] = "Pushing…"
        appendLog("— Pushing \(project.name) to GitHub —")
        Task {
            let (ok, lines) = await Task.detached(priority: .userInitiated) {
                Engine.pushProjectToGitHub(project)
            }.value
            lines.forEach { appendLog("    " + $0) }
            appendLog(ok ? "— \(project.name) is on GitHub —" : "— Push failed, see log —")
            projectActivity[project.path] = nil
            if !ok {
                actionAlert = lines.last(where: { $0.hasPrefix("[fail]") })
                    .map { String($0.dropFirst("[fail] ".count)) }
                    ?? "Push failed — see the Log for details."
            }
        }
    }

    func archiveProject(_ project: ProjectInfo, to destination: CloudDestination) {
        guard requirePro() else { return }
        guard projectActivity[project.path] == nil else { return }
        projectActivity[project.path] = "Archiving…"
        appendLog("— Archiving \(project.name) to \(destination.name) —")
        Task {
            let (zipPath, lines) = await Task.detached(priority: .userInitiated) {
                Engine.archiveProject(project, to: destination)
            }.value
            lines.forEach { appendLog("    " + $0) }
            projectActivity[project.path] = nil
            if let zipPath {
                archivePrompt = ArchivePrompt(project: project,
                                              destinationName: destination.name,
                                              zipPath: zipPath)
            } else {
                actionAlert = "Archiving to \(destination.name) failed — TidyDisk may not have "
                    + "permission to write there. Grant access in Settings → Backup Destinations."
            }
        }
    }

    /// After a successful archive: move the local project to Trash (recoverable).
    func trashProject(_ project: ProjectInfo) {
        appendLog("— Moving \(project.name) to Trash —")
        Task {
            let line = await Task.detached { Engine.trashFile(project.path) }.value
            appendLog("    " + line)
            withAnimation(.spring(duration: 0.35)) {
                projects.removeAll { $0.path == project.path }
            }
            freeSpace = Engine.freeDiskSpace()
        }
    }

    // MARK: - Large files

    @Published var largeFiles: [LargeFile] = []
    @Published var largeFilesScanning = false
    @Published var largeFilesScanned = false
    @Published var selectedFiles: Set<String> = []

    func scanLargeFiles() {
        guard !largeFilesScanning else { return }
        largeFilesScanning = true
        selectedFiles = []
        Task {
            let files = await Task.detached(priority: .userInitiated) {
                Engine.findLargeFiles()
            }.value
            withAnimation(.spring(duration: 0.4)) {
                largeFiles = files
                largeFilesScanning = false
                largeFilesScanned = true
            }
        }
    }

    var selectedFilesBytes: Int64 {
        largeFiles.filter { selectedFiles.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }

    func trashSelectedFiles() {
        let picked = largeFiles.filter { selectedFiles.contains($0.path) }
        guard !picked.isEmpty else { return }
        appendLog("— Moving \(picked.count) large files to Trash —")
        Task {
            for file in picked {
                let line = await Task.detached { Engine.trashFile(file.path) }.value
                appendLog("    " + line)
                if line.hasPrefix("[trash]") {
                    withAnimation(.spring(duration: 0.3)) {
                        largeFiles.removeAll { $0.path == file.path }
                        selectedFiles.remove(file.path)
                    }
                }
            }
            freeSpace = Engine.freeDiskSpace()
        }
    }

    // MARK: - Duplicates

    @Published var dupGroups: [DuplicateGroup] = []
    @Published var dupScanning = false
    @Published var dupScanned = false
    @Published var selectedDups: Set<String> = []

    func scanDuplicates() {
        guard !dupScanning else { return }
        dupScanning = true
        Task {
            let groups = await Task.detached(priority: .userInitiated) {
                Engine.findDuplicateGroups()
            }.value
            withAnimation(.spring(duration: 0.4)) {
                dupGroups = groups
                // Pre-select every copy except the newest in each group.
                selectedDups = Set(groups.flatMap { $0.files.dropFirst().map(\.path) })
                dupScanning = false
                dupScanned = true
            }
        }
    }

    var selectedDupBytes: Int64 {
        dupGroups.flatMap(\.files).filter { selectedDups.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }

    func trashSelectedDups() {
        guard requirePro() else { return }
        let picked = dupGroups.flatMap(\.files).filter { selectedDups.contains($0.path) }
        guard !picked.isEmpty else { return }
        appendLog("— Moving \(picked.count) duplicates to Trash —")
        Task {
            var trashed: Set<String> = []
            for file in picked {
                let line = await Task.detached { Engine.trashFile(file.path) }.value
                appendLog("    " + line)
                if line.hasPrefix("[trash]") { trashed.insert(file.path) }
            }
            withAnimation(.spring(duration: 0.35)) {
                dupGroups = dupGroups.compactMap { group in
                    let remaining = group.files.filter { !trashed.contains($0.path) }
                    return remaining.count > 1 ? DuplicateGroup(id: group.id, files: remaining) : nil
                }
                selectedDups.subtract(trashed)
            }
            freeSpace = Engine.freeDiskSpace()
        }
    }

    // MARK: - Settings (connections & destinations)

    enum ProbeResult: Equatable {
        case ok
        case failed(String)
    }

    /// GitHub login the pushes will use (token or gh CLI), nil = not connected.
    @Published var githubLogin: String?
    @Published var githubUsesToken = false
    @Published var githubChecking = false
    @Published var githubError: String?
    /// destination path → last access-probe result
    @Published var probeResults: [String: ProbeResult] = [:]

    func checkGitHubConnection() {
        guard !githubChecking else { return }
        githubChecking = true
        githubError = nil
        Task {
            let hasToken = Engine.githubToken != nil
            let account = await Task.detached(priority: .userInitiated) {
                Engine.githubAccount()
            }.value
            githubLogin = account?.login
            githubUsesToken = hasToken && account != nil
            githubChecking = false
        }
    }

    func connectGitHub(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !githubChecking else { return }
        githubChecking = true
        githubError = nil
        Task {
            let account = await Task.detached(priority: .userInitiated) {
                Engine.validateGitHubToken(trimmed)
            }.value
            if let account {
                Engine.storeGitHubToken(trimmed)
                githubLogin = account.login
                githubUsesToken = true
                appendLog("— GitHub connected as \(account.login) —")
            } else {
                githubError = "That token didn't work — check it has the \"repo\" scope and try again."
            }
            githubChecking = false
        }
    }

    func disconnectGitHub() {
        Engine.deleteGitHubToken()
        githubUsesToken = false
        checkGitHubConnection() // may fall back to gh CLI
        appendLog("— GitHub token removed —")
    }

    func probeDestination(_ destination: CloudDestination) {
        Task {
            let error = await Task.detached(priority: .userInitiated) {
                Engine.probeDestination(destination)
            }.value
            withAnimation(.spring(duration: 0.3)) {
                probeResults[destination.path] = error.map { .failed($0) } ?? .ok
            }
        }
    }

    func addCustomDestination(path: String) {
        Engine.addCustomDestination(path)
        cloudDestinations = Engine.cloudDestinations()
        if let dest = cloudDestinations.first(where: { $0.path == path }) {
            probeDestination(dest)
        }
    }

    func removeCustomDestination(path: String) {
        Engine.removeCustomDestination(path)
        probeResults[path] = nil
        cloudDestinations = Engine.cloudDestinations()
    }

    // MARK: - Pro license

    @Published var isPro = License.stored != nil
    @Published var showProSheet = false
    @Published var licenseActivating = false
    @Published var licenseError: String?

    /// Gate for Pro features: true if allowed, otherwise shows the paywall.
    func requirePro() -> Bool {
        guard ProConfig.paywallEnabled else { return true }
        if isPro { return true }
        showProSheet = true
        return false
    }

    func activateLicense(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !licenseActivating else { return }
        licenseActivating = true
        licenseError = nil
        Task {
            let result = await License.activate(key: trimmed)
            licenseActivating = false
            switch result {
            case .success:
                withAnimation(.spring(duration: 0.4)) { isPro = true }
                appendLog("— TidyDisk Pro activated —")
            case .failure(let error):
                licenseError = error.message
            }
        }
    }

    func deactivateLicense() {
        Task {
            await License.deactivate()
            withAnimation { isPro = false }
            appendLog("— TidyDisk Pro deactivated on this Mac —")
        }
    }

    /// Called at launch: drops Pro only if the store says the key was revoked.
    func revalidateLicense() {
        guard isPro else { return }
        Task {
            if await !License.revalidate() { withAnimation { isPro = false } }
        }
    }

    // MARK: - Weekly scheduled scan

    @Published var weeklyScanEnabled = Engine.isAgentInstalled()

    func setWeeklyScan(_ enabled: Bool) {
        if enabled && !requirePro() { return }
        Task {
            if enabled {
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
            }
            let lines = await Task.detached {
                enabled ? Engine.installAgent() : Engine.removeAgent()
            }.value
            lines.forEach { appendLog($0) }
            weeklyScanEnabled = Engine.isAgentInstalled()
        }
    }

    func refreshFreeSpace() {
        freeSpace = Engine.freeDiskSpace()
    }

    func reset() {
        withAnimation(.spring(duration: 0.5)) {
            phase = .welcome
            sidebar = .smartScan
        }
        selected = []
        runStatus = [:]
        freeSpace = Engine.freeDiskSpace()
    }

    private func appendLog(_ line: String) {
        log.append(line)
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
    }
}
