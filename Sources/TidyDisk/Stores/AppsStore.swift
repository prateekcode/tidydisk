import Foundation

struct AppInfo: Identifiable {
    let path: String
    let name: String
    let bundleID: String
    let version: String
    let bytes: Int64
    var id: String { path }
}

/// Installed applications, their leftovers, and uninstalling.
@MainActor
final class AppsStore: ObservableObject {
    /// Largest first.
    @Published var apps: [AppInfo] = []
    @Published var scanned = false
    @Published var scanning = false

    func scan() {}
}
