import Foundation
import ServiceManagement

/// UserDefaults keys shared by Settings and the views that obey them.
enum Preferences {
    static let menuBarShowsFreeSpace = "menuBarShowsFreeSpace"
}

/// Links shown in Settings and used by the update check.
enum Project {
    static let repository = "https://github.com/prateekcode/tidydisk"
    static let issues = repository + "/issues/new/choose"
    static let releases = repository + "/releases/latest"
    static let license = repository + "/blob/main/LICENSE"
    static let usageStatsSource = repository + "/blob/main/Sources/TidyDisk/Engine/UsageStats.swift"
    static let website = "https://tidydisk.riekapps.com"
    static let brewUpgrade = "brew upgrade --cask tidydisk"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

enum UpdateCheck: Equatable {
    case idle, checking, current
    case available(String)
    case failed

    /// Asks GitHub for the newest release. Runs only when the user presses the button.
    static func run() async -> UpdateCheck {
        guard let url = URL(string: "https://api.github.com/repos/prateekcode/tidydisk/releases/latest") else {
            return .failed
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return .failed }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return latest.compare(Project.version, options: .numeric) == .orderedDescending
            ? .available(latest) : .current
    }
}

/// "Open at login", through the system's own login-items list.
@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns the state after the change (macOS can refuse, e.g. for a build outside Applications).
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            ActivityLog.shared.add("[fail] open at login: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
