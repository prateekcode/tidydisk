import Foundation

/// Measures the disk in one parallel pass.
///
/// Every directory is read with `getattrlistbulk`, which returns name, type and
/// allocated size for a whole batch of entries in one system call (no `stat`
/// per file), and the top levels of the tree fan out across all cores.
/// This is the part of TidyDisk that a Rust core would replace one-to-one.
struct DiskWalker {
    /// Smallest file kept in the large-files list (the UI filters upward from here).
    static let largeFileFloor: Int64 = 100 * 1_000_000
    /// Levels of the tree stored in the index; deeper levels are measured on demand.
    static let treeDepth = 2
    /// Levels read breadth-first before the walk splits into per-folder jobs.
    private static let parallelDepth = 4
    /// Files smaller than this are not listed as their own row in the tree.
    private static let nodeFloor: Int64 = 1_000_000

    private let home = NSHomeDirectory()
    private let rules: [String: DiskKind]
    private let skip: Set<String>
    private let seenLinks = LinkSet()

    init(fullDiskAccess: Bool = Engine.hasFullDiskAccess()) {
        let home = NSHomeDirectory()
        var rules: [String: DiskKind] = [
            "/Library/Caches": .caches, "/Library/Developer": .developer,
        ]
        func add(_ kind: DiskKind, _ names: String...) {
            names.forEach { rules[home + "/" + $0] = kind }
        }
        add(.media, "Pictures", "Movies", "Music")
        add(.documents, "Documents", "Desktop")
        add(.downloads, "Downloads")
        add(.apps, "Applications")
        add(.caches, "Library/Caches", ".cache")
        rules["/private/var/folders"] = .caches
        rules["/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime"] = .developer
        add(.mail, "Library/Mail", "Library/Containers/com.apple.mail")
        add(.developer, "Library/Developer", "Library/Android", "Library/Containers/com.docker.docker",
            ".gradle", ".npm", ".pnpm-store", ".yarn", ".bun", ".pub-cache", ".cargo", ".rustup",
            ".cocoapods", ".m2", ".nvm", ".android", ".swiftpm", ".pyenv", ".rbenv", ".docker",
            ".local", ".dartServer", ".flutter", "go", "fvm", "flutter", "development")
        self.rules = rules

        // Reading other apps' containers without Full Disk Access makes macOS ask
        // the user on every launch; cloud folders would download their listings.
        var skip: Set<String> = [home + "/Library/CloudStorage"]
        if !fullDiskAccess {
            ["Library/Containers", "Library/Group Containers", "Library/Mobile Documents"]
                .forEach { skip.insert(home + "/" + $0) }
        }
        self.skip = skip
    }

    /// What gets measured: the home folder plus the shared locations apps write to.
    private var seeds: [Folder] {
        [(home, DiskKind.other, true), ("/Applications", .apps, false), ("/Library", .other, false),
         ("/opt/homebrew", .developer, false), ("/usr/local", .developer, false),
         ("/private/var", .other, false), ("/System/Library/AssetsV2", .other, false)]
            .filter { FileManager.default.fileExists(atPath: $0.0) }
            .map { Folder(path: $0.0, name: Engine.abbreviate($0.0), kind: $0.1, large: $0.2,
                          depth: 0, parent: -1, device: device(of: $0.0)) }
    }

    // MARK: - Public

    func measure() -> DiskIndex {
        let started = Date()
        var index = DiskIndex()
        let (roots, total) = run(seeds, treeDepth: Self.treeDepth)
        index.roots = roots.sorted { $0.bytes > $1.bytes }
        for kind in DiskKind.allCases {
            index.kinds[kind.rawValue] = .init(bytes: total.kindBytes[kind.rawValue],
                                               files: total.kindFiles[kind.rawValue])
        }
        for (ext, stat) in total.extensions {
            let group = (FileGroup.byExtension[ext] ?? .other).rawValue
            index.groups[group].bytes += stat.bytes
            index.groups[group].files += stat.files
        }
        index.extensions = Dictionary(uniqueKeysWithValues:
            total.extensions.sorted { $0.value.bytes > $1.value.bytes }.prefix(400).map { ($0.key, $0.value) })
        index.largeFiles = total.large.sorted { $0.bytes > $1.bytes }
        index.denied = total.denied.sorted()
        index.skipped = skip.filter { FileManager.default.fileExists(atPath: $0) }.sorted()
        index.date = Date()
        index.duration = index.date.timeIntervalSince(started)
        return index
    }

    /// The direct children of one folder with their full sizes (Folders drill-down).
    func listing(of path: String) -> [FolderNode] {
        let seed = Folder(path: path, name: (path as NSString).lastPathComponent, kind: .other,
                          large: false, depth: 0, parent: -1, device: device(of: path))
        return run([seed], treeDepth: 1).nodes.first?.children ?? []
    }

    // MARK: - Run

    /// A directory waiting to be read, with what it inherits from its parent.
    private struct Folder {
        let path: String
        let name: String
        let kind: DiskKind
        let large: Bool
        let depth: Int
        /// Index of the parent in the run's folder list, -1 for a seed.
        let parent: Int
        let device: Int32
        var totals = Totals()
        var files: [FolderNode] = []
    }

    /// Breadth-first over the top `parallelDepth` levels, one parallel batch per
    /// level, then one serial walk per remaining subtree across all cores.
    /// (Nested `concurrentPerform` calls collapse to one thread, so the fan-out
    /// has to be flat.)
    private func run(_ seeds: [Folder], treeDepth: Int) -> (nodes: [FolderNode], total: Accum) {
        var folders = seeds
        var frontier = Array(folders.indices)
        let total = Accum()

        func batch<T>(_ indices: [Int], _ initial: T, _ work: (Folder, Accum) -> T) -> [T] {
            var results = [T](repeating: initial, count: indices.count)
            let accs = indices.map { _ in Accum() }
            let snapshot = folders
            results.withUnsafeMutableBufferPointer { buffer in
                DispatchQueue.concurrentPerform(iterations: indices.count) { i in
                    buffer[i] = work(snapshot[indices[i]], accs[i])
                }
            }
            accs.forEach(total.merge)
            return results
        }

        for _ in 0..<Self.parallelDepth where !frontier.isEmpty {
            let level = frontier
            let scans = batch(level, Scan()) { folder, acc in
                scan(folder, acc, keepFiles: folder.depth < treeDepth)
            }
            frontier = []
            for (i, result) in scans.enumerated() {
                folders[level[i]].totals = result.own
                folders[level[i]].files = result.files
                for var child in result.children {
                    child = Folder(path: child.path, name: child.name, kind: child.kind, large: child.large,
                                   depth: child.depth, parent: level[i], device: child.device)
                    folders.append(child)
                    frontier.append(folders.count - 1)
                }
            }
        }
        let deepTotals = batch(frontier, Totals()) { folder, acc in deep(folder, acc) }
        for (i, index) in frontier.enumerated() { folders[index].totals = deepTotals[i] }

        // Children always sit after their parent, so one backward pass rolls sizes up.
        var childIndices: [Int: [Int]] = [:]
        for index in folders.indices.reversed() where folders[index].parent >= 0 {
            let parent = folders[index].parent
            folders[parent].totals.bytes += folders[index].totals.bytes
            folders[parent].totals.files += folders[index].totals.files
            if folders[index].depth <= treeDepth { childIndices[parent, default: []].append(index) }
        }

        func node(_ index: Int) -> FolderNode {
            let folder = folders[index]
            var children: [FolderNode]?
            if folder.depth < treeDepth {
                var list = (childIndices[index] ?? []).map(node) + folder.files
                list.sort { $0.bytes > $1.bytes }
                if list.count > 250 { list.removeLast(list.count - 250) }
                children = list
            }
            return FolderNode(path: folder.path, name: folder.name, bytes: folder.totals.bytes,
                              files: folder.totals.files, isDirectory: true, children: children)
        }
        return (seeds.indices.map(node), total)
    }

    // MARK: - Walk

    private struct Totals {
        var bytes: Int64 = 0
        var files = 0
    }

    /// Per-thread running totals; merged into the parent after a parallel fan-out.
    private final class Accum {
        var kindBytes = [Int64](repeating: 0, count: DiskKind.allCases.count)
        var kindFiles = [Int](repeating: 0, count: DiskKind.allCases.count)
        var extensions: [String: DiskIndex.Stat] = [:]
        var large: [LargeFile] = []
        var denied: [String] = []

        func count(extension ext: String, bytes: Int64) {
            var stat = extensions[ext] ?? .init()
            stat.bytes += bytes
            stat.files += 1
            extensions[ext] = stat
        }

        func merge(_ other: Accum) {
            for i in kindBytes.indices {
                kindBytes[i] += other.kindBytes[i]
                kindFiles[i] += other.kindFiles[i]
            }
            for (ext, stat) in other.extensions {
                var sum = extensions[ext] ?? .init()
                sum.bytes += stat.bytes
                sum.files += stat.files
                extensions[ext] = sum
            }
            large.append(contentsOf: other.large)
            denied.append(contentsOf: other.denied)
        }
    }

    /// Hard-linked files (pnpm stores, Time Machine style trees) are counted once.
    private final class LinkSet {
        private var ids = Set<UInt64>()
        private let lock = NSLock()

        /// True the first time an inode is seen.
        func claim(_ id: UInt64) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return ids.insert(id).inserted
        }
    }

    /// A folder holding one of these is a project: everything under it is Developer.
    private static let projectFiles: Set<String> = [
        "package.json", "pubspec.yaml", "Cargo.toml", "go.mod", "Package.swift", "Podfile",
        "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts",
        "pyproject.toml", "Gemfile", "composer.json", "CMakeLists.txt",
    ]
    private static let projectDirSuffixes = [".xcodeproj", ".xcworkspace"]
    /// Developer output wherever it appears.
    private static let developerDirs: Set<String> = [
        "node_modules", ".git", "Pods", "DerivedData", ".dart_tool", ".gradle", ".venv", "venv",
        "__pycache__", ".next", ".turbo",
    ]
    /// Bundles and tool folders whose insides are not "your large files".
    private static let opaqueSuffixes = [
        ".app", ".photoslibrary", ".musiclibrary", ".tvlibrary", ".fcpbundle", ".imovielibrary",
        ".logicx", ".band", ".xcarchive", ".framework", ".sparsebundle",
    ]

    private func device(of path: String) -> Int32 {
        var info = stat()
        return stat(path, &info) == 0 ? info.st_dev : 0
    }

    /// What reading one directory yields.
    private struct Scan {
        var own = Totals()
        var children: [Folder] = []
        /// Files big enough to be their own row (only when asked for).
        var files: [FolderNode] = []
    }

    /// Reads one directory: counts its files and decides what each sub-folder inherits.
    private func scan(_ folder: Folder, _ acc: Accum, keepFiles: Bool) -> Scan {
        let path = folder.path
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else {
            if errno == EPERM || errno == EACCES { acc.denied.append(path) }
            return Scan()
        }
        // Stay on this volume: mounted disk images (simulator runtimes) and
        // network shares are someone else's space.
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_dev == folder.device else {
            close(fd)
            return Scan()
        }
        // A project marker can re-label this folder, but never a whole seed.
        let canBecomeProject = folder.depth > 0
            && (folder.kind == .other || folder.kind == .documents || folder.kind == .downloads)
        var isProject = false
        var result = Scan()
        var subdirs: [String] = []

        Self.readEntries(fd) { entry in
            switch entry.type {
            case Self.typeDirectory:
                // Never force a cloud-only folder to download its listing.
                guard entry.flags & Self.dataless == 0 else { return }
                let name = String(cString: entry.name)
                if canBecomeProject, !isProject,
                   name == ".git" || Self.projectDirSuffixes.contains(where: name.hasSuffix) {
                    isProject = true
                }
                subdirs.append(name)
            case Self.typeFile:
                let bytes = entry.links > 1 && !seenLinks.claim(entry.fileID) ? 0 : entry.allocated
                result.own.bytes += bytes
                result.own.files += 1
                acc.count(extension: Self.fileExtension(entry.name), bytes: bytes)
                if canBecomeProject, !isProject, Self.projectFiles.contains(String(cString: entry.name)) {
                    isProject = true
                }
                let isLarge = folder.large && bytes >= Self.largeFileFloor
                if isLarge || (keepFiles && bytes >= Self.nodeFloor) {
                    let name = String(cString: entry.name)
                    let filePath = path + "/" + name
                    if isLarge {
                        acc.large.append(LargeFile(path: filePath, bytes: bytes,
                                                   modified: Date(timeIntervalSince1970: Double(entry.modified))))
                    }
                    if keepFiles {
                        result.files.append(FolderNode(path: filePath, name: name, bytes: bytes, files: 1,
                                                       isDirectory: false, children: nil))
                    }
                }
            default:
                break
            }
        }
        close(fd)

        let kind = isProject ? DiskKind.developer : folder.kind
        acc.kindBytes[kind.rawValue] += result.own.bytes
        acc.kindFiles[kind.rawValue] += result.own.files

        result.children = subdirs.compactMap { name in
            let childPath = path == "/" ? "/" + name : path + "/" + name
            if skip.contains(childPath) { return nil }
            var childKind = kind
            if let rule = rules[childPath] {
                childKind = rule
            } else if Self.developerDirs.contains(name), kind != .apps, kind != .caches {
                childKind = .developer
            }
            // Large files are the user's own: not app bundles, not tool folders,
            // not ~/Library, not dot-folders at the top of the home folder.
            let childLarge = folder.large
                && !Self.developerDirs.contains(name)
                && !Self.opaqueSuffixes.contains(where: name.hasSuffix)
                && !(path == home && (name == "Library" || name.hasPrefix(".")))
            return Folder(path: childPath, name: name, kind: childKind, large: childLarge,
                          depth: folder.depth + 1, parent: -1, device: folder.device)
        }
        return result
    }

    /// Everything under one folder, on the calling thread.
    private func deep(_ folder: Folder, _ acc: Accum) -> Totals {
        let result = scan(folder, acc, keepFiles: false)
        var total = result.own
        for child in result.children {
            let sub = deep(child, acc)
            total.bytes += sub.bytes
            total.files += sub.files
        }
        return total
    }

    /// Lowercased extension of a C file name; "" when there is none worth grouping.
    private static func fileExtension(_ name: UnsafePointer<CChar>) -> String {
        guard let dot = strrchr(name, 0x2E), dot != UnsafeMutablePointer(mutating: name) else { return "" }
        let length = strlen(dot + 1)
        guard length > 0, length <= 12 else { return "" }
        return String(cString: dot + 1).lowercased()
    }

    // MARK: - getattrlistbulk

    private struct Entry {
        var name: UnsafePointer<CChar>
        var type: UInt32 = 0
        var flags: UInt32 = 0
        var modified: Int = 0
        var fileID: UInt64 = 0
        var links: UInt32 = 1
        var allocated: Int64 = 0
    }

    private static let typeFile: UInt32 = 1       // VREG
    private static let typeDirectory: UInt32 = 2  // VDIR
    private static let dataless: UInt32 = 0x4000_0000 // SF_DATALESS

    // Attribute bits (sys/attr.h). The reply packs the requested attributes in
    // bit order, after the "returned" set and the per-entry error.
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnType: UInt32 = 0x0000_0008
    private static let cmnModified: UInt32 = 0x0000_0400
    private static let cmnFlags: UInt32 = 0x0004_0000
    private static let cmnFileID: UInt32 = 0x0200_0000
    private static let cmnError: UInt32 = 0x2000_0000
    private static let cmnReturned: UInt32 = 0x8000_0000
    private static let fileLinks: UInt32 = 0x0000_0001
    private static let fileAllocated: UInt32 = 0x0000_0004
    private static let bufferSize = 128 * 1024

    private static func readEntries(_ fd: Int32, _ body: (Entry) -> Void) {
        var request = attrlist()
        request.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        request.commonattr = cmnReturned | cmnError | cmnName | cmnType
            | cmnModified | cmnFlags | cmnFileID
        request.fileattr = fileLinks | fileAllocated

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            guard count > 0 else { return }
            var record = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(record.loadUnaligned(as: UInt32.self))
                var field = record + 4
                let returned = field.loadUnaligned(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size

                var failed = false
                if returned.commonattr & cmnError != 0 {
                    failed = field.loadUnaligned(as: UInt32.self) != 0
                    field += 4
                }
                var name: UnsafePointer<CChar>?
                if returned.commonattr & cmnName != 0 {
                    let reference = field.loadUnaligned(as: attrreference_t.self)
                    name = (field + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                    field += MemoryLayout<attrreference_t>.size
                }
                if let name, !failed {
                    var entry = Entry(name: name)
                    if returned.commonattr & cmnType != 0 {
                        entry.type = field.loadUnaligned(as: UInt32.self)
                        field += 4
                    }
                    if returned.commonattr & cmnModified != 0 {
                        entry.modified = field.loadUnaligned(as: Int.self)
                        field += 16
                    }
                    if returned.commonattr & cmnFlags != 0 {
                        entry.flags = field.loadUnaligned(as: UInt32.self)
                        field += 4
                    }
                    if returned.commonattr & cmnFileID != 0 {
                        entry.fileID = field.loadUnaligned(as: UInt64.self)
                        field += 8
                    }
                    if returned.fileattr & fileLinks != 0 {
                        entry.links = field.loadUnaligned(as: UInt32.self)
                        field += 4
                    }
                    if returned.fileattr & fileAllocated != 0 {
                        entry.allocated = field.loadUnaligned(as: Int64.self)
                    }
                    body(entry)
                }
                record += length
            }
        }
    }
}
