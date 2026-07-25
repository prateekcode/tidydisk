import Foundation

struct CloudDestination: Identifiable, Hashable {
    let name: String
    let path: String
    var id: String { path }
}

extension Engine {
    // MARK: - Cloud destinations

    /// iCloud Drive plus any synced provider under ~/Library/CloudStorage (Google Drive, Dropbox…).
    static func cloudDestinations() -> [CloudDestination] {
        let fm = FileManager.default
        var result: [CloudDestination] = []
        let icloud = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"
        if fm.fileExists(atPath: icloud) {
            result.append(CloudDestination(name: "iCloud Drive", path: icloud))
        }
        let cloudStorage = NSHomeDirectory() + "/Library/CloudStorage"
        for provider in (try? fm.contentsOfDirectory(atPath: cloudStorage)) ?? [] {
            let name = provider.split(separator: "-").first.map(String.init) ?? provider
            result.append(CloudDestination(name: name, path: cloudStorage + "/" + provider))
        }
        for path in customDestinationPaths where !result.contains(where: { $0.path == path }) {
            result.append(CloudDestination(name: (path as NSString).lastPathComponent, path: path))
        }
        return result
    }

    private static let customDestinationsKey = "customDestinations"

    static var customDestinationPaths: [String] {
        UserDefaults.standard.stringArray(forKey: customDestinationsKey) ?? []
    }

    static func addCustomDestination(_ path: String) {
        var paths = customDestinationPaths
        guard !paths.contains(path) else { return }
        paths.append(path)
        UserDefaults.standard.set(paths, forKey: customDestinationsKey)
    }

    static func removeCustomDestination(_ path: String) {
        UserDefaults.standard.set(customDestinationPaths.filter { $0 != path },
                                  forKey: customDestinationsKey)
    }

    /// Actually writes (and removes) a probe file — this is what triggers macOS's
    /// permission prompt for iCloud/CloudStorage folders. Returns nil on success.
    static func probeDestination(_ destination: CloudDestination) -> String? {
        let dir = destination.path + "/TidyDisk Backups"
        let probe = dir + "/.tidydisk-access-probe"
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try "ok".write(toFile: probe, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: probe)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Zips the project into "<destination>/TidyDisk Backups/<name> <date>.zip".
    static func archiveProject(_ project: ProjectInfo, to destination: CloudDestination) -> (zipPath: String?, log: [String]) {
        let backupDir = destination.path + "/TidyDisk Backups"
        try? FileManager.default.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let zipPath = "\(backupDir)/\(project.name)-\(stamp).zip"
        let (status, output) = run(["ditto", "-c", "-k", "--keepParent", project.path, zipPath])
        if status == 0 {
            let zipSize = size(of: [zipPath])
            return (zipPath, ["[done] archived \(project.name) → \(abbreviate(zipPath)) (\(Format.bytes(zipSize)))"])
        }
        try? FileManager.default.removeItem(atPath: zipPath)
        return (nil, ["[fail] archive \(project.name): \(output.split(separator: "\n").last.map(String.init) ?? "ditto error \(status)")"])
    }

    // MARK: - GitHub push

    private static func git(_ project: ProjectInfo, _ args: [String]) -> (status: Int32, output: String) {
        run(["git", "-C", project.path] + args)
    }

    static let defaultGitignore = """
    node_modules/
    build/
    .dart_tool/
    Pods/
    .gradle/
    .build/
    DerivedData/
    .DS_Store
    """

    /// Inserts the token into a github.com https URL so a push needs no credential helper.
    private static func tokenized(_ url: String, token: String) -> String? {
        guard url.hasPrefix("https://github.com/") else { return nil }
        return url.replacingOccurrences(of: "https://github.com/",
                                        with: "https://x-access-token:\(token)@github.com/")
    }

    /// Init repo if needed, commit everything, create a private GitHub repo if there's no remote, push.
    /// Auth: token from Settings first, gh CLI as fallback.
    static func pushProjectToGitHub(_ project: ProjectInfo) -> (ok: Bool, log: [String]) {
        var log: [String] = []

        guard let account = githubAccount() else {
            return (false, ["[fail] GitHub isn't connected — add a token in Settings → GitHub"])
        }
        let token = githubToken

        if git(project, ["rev-parse", "--git-dir"]).status != 0 {
            log.append(git(project, ["init"]).status == 0
                       ? "[done] git init"
                       : "[fail] git init")
        }

        // Repo-local identity from the connected account (never the global config).
        _ = git(project, ["config", "user.name", account.login])
        _ = git(project, ["config", "user.email", account.noreplyEmail])
        log.append("[done] repo-local identity: \(account.login)")

        let gitignorePath = project.path + "/.gitignore"
        if !FileManager.default.fileExists(atPath: gitignorePath) {
            try? defaultGitignore.write(toFile: gitignorePath, atomically: true, encoding: .utf8)
            log.append("[done] wrote default .gitignore (excludes node_modules, build…)")
        }

        _ = git(project, ["add", "-A"])
        let commit = git(project, ["commit", "-m", "Backup via TidyDisk"])
        log.append(commit.status == 0
                   ? "[done] committed changes"
                   : "[skip] nothing new to commit")

        // Work out where to push: existing origin, or a fresh private repo.
        var remoteURL = git(project, ["remote", "get-url", "origin"]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if remoteURL.isEmpty {
            if let token {
                let (url, error) = createGitHubRepo(token: token, account: account, name: project.name)
                guard let url else { return (false, log + ["[fail] create repo: \(error ?? "unknown error")"]) }
                _ = git(project, ["remote", "add", "origin", url])
                remoteURL = url
                log.append("[done] created private repo \(account.login)/\(project.name)")
            } else {
                let create = run(["gh", "repo", "create", project.name, "--private",
                                  "--source", project.path, "--remote", "origin", "--push"])
                log.append(create.status == 0
                           ? "[done] created private repo \(account.login)/\(project.name) and pushed"
                           : "[fail] gh repo create: \(create.output.suffix(160))")
                return (create.status == 0, log)
            }
        }

        let pushURL = token.flatMap { tokenized(remoteURL, token: $0) } ?? "origin"
        let push = git(project, ["push", pushURL, "HEAD"])
        log.append(push.status == 0
                   ? "[done] pushed to \(account.login)/\(project.name)"
                   : "[fail] push: \(push.output.suffix(160))")
        return (push.status == 0, log)
    }
}
