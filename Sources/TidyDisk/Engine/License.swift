import Foundation

/// Lemon Squeezy store settings. Fill in after creating the store —
/// until `storeID` is set, activation refuses every key (fail closed).
enum ProConfig {
    /// Master switch: while false, every feature is free and no Pro UI appears.
    /// To launch paid: set true, fill storeID + checkoutURL, rebuild.
    static let paywallEnabled = false

    static let storeID = 0                                    // LS dashboard → Settings → Stores
    static let checkoutURL = "https://tidydisk.riekapps.com"  // LS "Share" link for the Pro product
    static let price = "$4.99"

    static var isConfigured: Bool { storeID != 0 }
}

/// A license activated on this Mac, persisted in UserDefaults.
struct LicenseInfo: Codable {
    let key: String
    let instanceID: String
}

/// One-time-purchase licensing via Lemon Squeezy's public license API.
/// No account, no server of ours: activate/validate are unauthenticated
/// endpoints keyed by the license itself.
enum License {
    private static let defaultsKey = "pro.license"
    private static let api = "https://api.lemonsqueezy.com/v1/licenses/"

    static var stored: LicenseInfo? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(LicenseInfo.self, from: data)
    }

    private static func store(_ info: LicenseInfo?) {
        if let info, let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    /// Activates a key for this Mac. On success the license is persisted.
    static func activate(key: String) async -> Result<LicenseInfo, ActivationError> {
        guard ProConfig.isConfigured else { return .failure(.notConfigured) }
        let instanceName = Host.current().localizedName ?? "Mac"
        guard let json = await post("activate", form: [
            "license_key": key, "instance_name": instanceName,
        ]) else { return .failure(.network) }

        guard json["activated"] as? Bool == true,
              let instance = json["instance"] as? [String: Any],
              let instanceID = instance["id"] as? String else {
            let message = json["error"] as? String ?? "This key could not be activated."
            return .failure(.rejected(message))
        }
        // A valid key from someone else's Lemon Squeezy store must not unlock us.
        guard let meta = json["meta"] as? [String: Any],
              meta["store_id"] as? Int == ProConfig.storeID else {
            return .failure(.rejected("This key is not a TidyDisk Pro key."))
        }
        let info = LicenseInfo(key: key, instanceID: instanceID)
        store(info)
        return .success(info)
    }

    /// Re-checks the stored license. Returns false only when the store says the
    /// key is gone/revoked; network failures keep the cached activation (offline OK).
    static func revalidate() async -> Bool {
        guard let info = stored else { return false }
        guard let json = await post("validate", form: [
            "license_key": info.key, "instance_id": info.instanceID,
        ]) else { return true }
        if json["valid"] as? Bool == false {
            store(nil)
            return false
        }
        return true
    }

    static func deactivate() async {
        guard let info = stored else { return }
        _ = await post("deactivate", form: [
            "license_key": info.key, "instance_id": info.instanceID,
        ])
        store(nil)
    }

    enum ActivationError: Error {
        case notConfigured
        case network
        case rejected(String)

        var message: String {
            switch self {
            case .notConfigured: return "Purchases aren't live yet — check back soon."
            case .network: return "Couldn't reach the license server. Check your connection and try again."
            case .rejected(let reason): return reason
            }
        }
    }

    private static func post(_ endpoint: String, form: [String: String]) async -> [String: Any]? {
        var request = URLRequest(url: URL(string: api + endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        request.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
