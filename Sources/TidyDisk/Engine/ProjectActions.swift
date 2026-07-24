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
        return result
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

    /// Init repo if needed, commit everything, create a private GitHub repo if there's no remote, push.
    static func pushProjectToGitHub(_ project: ProjectInfo) -> (ok: Bool, log: [String]) {
        var log: [String] = []

        guard run(["gh", "auth", "status"]).status == 0 else {
            return (false, ["[fail] gh CLI not authenticated — run: gh auth login"])
        }

        if git(project, ["rev-parse", "--git-dir"]).status != 0 {
            log.append(git(project, ["init"]).status == 0
                       ? "[done] git init"
                       : "[fail] git init")
        }

        // Repo-local identity from the active gh account (never the global config).
        let login = run(["gh", "api", "user", "--jq", ".login"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let userID = run(["gh", "api", "user", "--jq", ".id"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !login.isEmpty {
            _ = git(project, ["config", "user.name", login])
            _ = git(project, ["config", "user.email", "\(userID)+\(login)@users.noreply.github.com"])
            log.append("[done] repo-local identity: \(login)")
        }

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

        let hasRemote = git(project, ["remote", "get-url", "origin"]).status == 0
        if hasRemote {
            let push = git(project, ["push", "origin", "HEAD"])
            log.append(push.status == 0 ? "[done] pushed to origin" : "[fail] push: \(push.output.suffix(120))")
            return (push.status == 0, log)
        } else {
            let create = run(["gh", "repo", "create", project.name, "--private",
                              "--source", project.path, "--remote", "origin", "--push"])
            log.append(create.status == 0
                       ? "[done] created private repo \(login)/\(project.name) and pushed"
                       : "[fail] gh repo create: \(create.output.suffix(160))")
            return (create.status == 0, log)
        }
    }
}
