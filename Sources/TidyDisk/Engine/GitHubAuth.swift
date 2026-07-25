import Foundation
import Security

/// GitHub identity resolved from a stored token (or the gh CLI fallback).
struct GitHubAccount {
    let login: String
    let userID: String
    var noreplyEmail: String { "\(userID)+\(login)@users.noreply.github.com" }
}

/// Personal-access-token storage in the macOS Keychain + GitHub REST helpers.
/// curl keeps Engine's synchronous, Process-based style (called from detached tasks).
extension Engine {
    private static let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.riekapps.tidydisk",
        kSecAttrAccount as String: "github-token",
    ]

    static var githubToken: String? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func storeGitHubToken(_ token: String) {
        SecItemDelete(keychainQuery as CFDictionary)
        var query = keychainQuery
        query[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteGitHubToken() {
        SecItemDelete(keychainQuery as CFDictionary)
    }

    /// GET/POST to the GitHub API with a token. Returns parsed JSON object (or nil).
    private static func githubAPI(_ token: String, _ path: String, post body: String? = nil) -> [String: Any]? {
        var args = ["curl", "-s", "--max-time", "15",
                    "-H", "Authorization: Bearer \(token)",
                    "-H", "Accept: application/vnd.github+json"]
        if let body {
            args += ["-X", "POST", "-d", body]
        }
        args.append("https://api.github.com" + path)
        let (status, output) = run(args)
        guard status == 0, let data = output.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Checks a token against the API; returns the account it belongs to, nil if invalid/offline.
    static func validateGitHubToken(_ token: String) -> GitHubAccount? {
        guard let json = githubAPI(token, "/user"),
              let login = json["login"] as? String,
              let id = json["id"] as? Int else { return nil }
        return GitHubAccount(login: login, userID: String(id))
    }

    /// The account pushes will use: stored token first, gh CLI second, nil if neither.
    static func githubAccount() -> GitHubAccount? {
        if let token = githubToken, let account = validateGitHubToken(token) { return account }
        guard run(["gh", "auth", "status"]).status == 0 else { return nil }
        let login = run(["gh", "api", "user", "--jq", ".login"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = run(["gh", "api", "user", "--jq", ".id"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        return login.isEmpty ? nil : GitHubAccount(login: login, userID: id)
    }

    /// Creates a private repo for the token's account. Succeeds if it already exists.
    /// Returns the repo's https URL, or nil with the API's error message.
    static func createGitHubRepo(token: String, account: GitHubAccount, name: String) -> (url: String?, error: String?) {
        let cleanURL = "https://github.com/\(account.login)/\(name).git"
        guard let json = githubAPI(token, "/user/repos",
                                   post: #"{"name":"\#(name)","private":true}"#) else {
            return (nil, "couldn't reach api.github.com")
        }
        if json["id"] as? Int != nil { return (cleanURL, nil) }
        // 422 "name already exists" → reuse the existing repo.
        let detail = ((json["errors"] as? [[String: Any]])?.first?["message"] as? String)
            ?? (json["message"] as? String) ?? "unknown API error"
        if detail.lowercased().contains("already exists") { return (cleanURL, nil) }
        return (nil, detail)
    }
}
