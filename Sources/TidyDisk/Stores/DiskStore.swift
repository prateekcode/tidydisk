import Foundation
import SwiftUI

/// The disk breakdown behind the Disk, Large Files and Overview screens.
/// One measurement feeds all three and is kept between launches.
@MainActor
final class DiskStore: ObservableObject {
    @Published private(set) var index: DiskIndex?
    @Published private(set) var measuring = false

    /// Smallest file the Large Files tab lists.
    @Published var largeThreshold = DiskStore.savedThreshold {
        didSet {
            UserDefaults.standard.set(Double(largeThreshold), forKey: Self.thresholdKey)
            selectedFiles = selectedFiles.filter { path in largeFiles.contains { $0.path == path } }
        }
    }
    @Published var selectedFiles: Set<String> = []

    /// Folder listings measured on demand, deeper than the saved tree goes.
    @Published private(set) var listings: [String: [FolderNode]] = [:]
    @Published private(set) var loadingListings: Set<String> = []

    static let thresholdSteps: [Int64] = [100, 200, 300, 500, 750, 1000, 2000, 5000].map { $0 * 1_000_000 }
    private static let thresholdKey = "largeFileThreshold"
    private static var savedThreshold: Int64 {
        let saved = Int64(UserDefaults.standard.double(forKey: thresholdKey))
        return thresholdSteps.contains(saved) ? saved : 500_000_000
    }

    nonisolated private static let cacheURL: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TidyDisk", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("disk-index.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let saved = try? JSONDecoder().decode(DiskIndex.self, from: data) {
            index = saved
        }
    }

    // MARK: - Measuring

    func measure() {
        guard !measuring else { return }
        measuring = true
        ActivityLog.shared.add("— Measuring the disk —")
        Task {
            let result = await Task.detached(priority: .userInitiated) { DiskWalker().measure() }.value
            withAnimation(.easeOut(duration: 0.3)) {
                index = result
                listings = [:]
                selectedFiles = []
                measuring = false
            }
            ActivityLog.shared.add("[disk] \(Format.bytes(result.measuredBytes)) in "
                + "\(Format.count(result.totalFiles)) files, \(String(format: "%.1f", result.duration)) s")
            save()
        }
    }

    /// Settings: drop the saved measurement (TidyDisk's own cache file only).
    func forget() {
        guard !measuring else { return }
        index = nil
        listings = [:]
        selectedFiles = []
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    private func save() {
        guard let index else { return }
        Task.detached(priority: .utility) {
            try? JSONEncoder().encode(index).write(to: Self.cacheURL, options: .atomic)
        }
    }

    // MARK: - Folders

    /// Children of a folder: from the saved tree, or measured now and cached.
    func children(of node: FolderNode) -> [FolderNode]? {
        node.children ?? listings[node.path]
    }

    func loadChildren(of node: FolderNode) {
        guard node.isDirectory, node.children == nil, listings[node.path] == nil,
              !loadingListings.contains(node.path) else { return }
        loadingListings.insert(node.path)
        Task {
            let nodes = await Task.detached(priority: .userInitiated) {
                DiskWalker().listing(of: node.path)
            }.value
            listings[node.path] = nodes
            loadingListings.remove(node.path)
        }
    }

    // MARK: - Large files

    var largeFiles: [LargeFile] {
        index?.largeFiles.filter { $0.bytes >= largeThreshold } ?? []
    }

    var largeFilesBytes: Int64 { largeFiles.reduce(0) { $0 + $1.bytes } }

    var selectedBytes: Int64 {
        largeFiles.filter { selectedFiles.contains($0.path) }.reduce(0) { $0 + $1.bytes }
    }

    /// Moves the ticked files to the Trash (recoverable) and drops them from the list.
    func trashSelected() {
        let picked = largeFiles.filter { selectedFiles.contains($0.path) }
        guard !picked.isEmpty else { return }
        ActivityLog.shared.add("— Moving \(picked.count) large files to Trash —")
        Task {
            var trashed: Set<String> = []
            var freed: Int64 = 0
            for file in picked {
                let line = await Task.detached { Engine.trashFile(file.path) }.value
                ActivityLog.shared.add("    " + line)
                if line.hasPrefix("[trash]") {
                    trashed.insert(file.path)
                    freed += file.bytes
                }
            }
            withAnimation(.easeOut(duration: 0.25)) {
                index?.largeFiles.removeAll { trashed.contains($0.path) }
                selectedFiles.subtract(trashed)
            }
            // In the Trash the space is still taken: nothing is "cleaned" until it is emptied.
            Engine.reportFreed(0)
            ActivityLog.shared.add("— \(Format.bytes(freed)) moved to Trash; empty it to get the space back —")
            save()
        }
    }
}
