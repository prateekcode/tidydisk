import Foundation

/// What AI tools cost this Mac: disk, memory, local servers.
@MainActor
final class AIStore: ObservableObject {
    /// Models + caches + app data of every detected AI tool.
    @Published var diskBytes: Int64 = 0
    /// Names of the tools with data on disk, largest first.
    @Published var diskToolNames: [String] = []
    @Published var diskScanned = false
    @Published var diskScanning = false
    /// Memory held by running AI apps right now.
    @Published var memoryBytes: Int64 = 0
    @Published var runningNames: [String] = []
    /// "Ollama :11434" style labels of local AI servers that are listening.
    @Published var serverLabels: [String] = []

    func scanDisk() {}
    func refreshLive() {}
}
