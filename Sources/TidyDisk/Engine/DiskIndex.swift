import Foundation

/// Where space goes, by location. Order is the order shown on the Disk tab.
enum DiskKind: Int, CaseIterable, Codable, Identifiable {
    case media, apps, documents, downloads, caches, developer, mail, other

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .media: return "Photos & media"
        case .apps: return "Apps"
        case .documents: return "Documents"
        case .downloads: return "Downloads"
        case .caches: return "Caches"
        case .developer: return "Developer"
        case .mail: return "Mail"
        case .other: return "Other"
        }
    }

    var detail: String {
        switch self {
        case .media: return "Pictures, Movies and Music"
        case .apps: return "Applications and their bundles"
        case .documents: return "Documents and Desktop"
        case .downloads: return "The Downloads folder"
        case .caches: return "App and system caches"
        case .developer: return "Projects, build output, package caches, SDKs"
        case .mail: return "Mail messages and attachments"
        case .other: return "Everything else in your home folder and /Library"
        }
    }
}

/// What files are, by extension. Order is the order shown on the File types tab.
enum FileGroup: Int, CaseIterable, Codable, Identifiable {
    case video, images, audio, archives, diskImages, documents, code, binaries, data, models, other

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .video: return "Video"
        case .images: return "Images"
        case .audio: return "Audio"
        case .archives: return "Archives"
        case .diskImages: return "Disk images & installers"
        case .documents: return "Documents"
        case .code: return "Code & text"
        case .binaries: return "Libraries & binaries"
        case .data: return "Databases & data"
        case .models: return "AI models"
        case .other: return "Other"
        }
    }

    private static let table: [FileGroup: [String]] = [
        .video: ["mov", "mp4", "m4v", "mkv", "avi", "webm", "wmv", "flv", "mts", "prores", "braw"],
        .images: ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp", "raw",
                  "cr2", "cr3", "nef", "arw", "dng", "psd", "svg", "ico", "icns", "ai", "sketch", "fig"],
        .audio: ["mp3", "m4a", "wav", "aiff", "aif", "flac", "aac", "ogg", "opus", "caf", "m4b"],
        .archives: ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst", "aar", "xip"],
        .diskImages: ["dmg", "iso", "pkg", "img", "sparseimage", "sparsebundle", "ipa", "apk", "aab",
                      "ipsw", "vmdk", "qcow2", "vdi"],
        .documents: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key",
                     "rtf", "epub", "odt", "ods"],
        .code: ["swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "rs", "go", "py", "rb", "php", "js",
                "mjs", "cjs", "ts", "tsx", "jsx", "dart", "kt", "kts", "java", "scala", "cs", "sh",
                "json", "yaml", "yml", "xml", "html", "htm", "css", "scss", "md", "txt", "toml",
                "plist", "gradle", "sql", "lock", "map", "storyboard", "xib", "strings"],
        .binaries: ["dylib", "so", "a", "o", "jar", "class", "dex", "wasm", "node", "dll", "exe",
                    "pyc", "tbd", "swiftmodule", "pcm", "dsym", "bc", "rlib", "car", "nib"],
        .data: ["db", "sqlite", "sqlite3", "realm", "csv", "tsv", "parquet", "log", "bin", "dat",
                "pack", "idx", "blob", "ldb", "sst", "wal", "store", "cache", "data"],
        .models: ["gguf", "ggml", "safetensors", "ckpt", "pt", "pth", "onnx", "mlmodel",
                  "mlmodelc", "mlpackage", "tflite", "npz", "h5"],
    ]

    /// Extension (lowercase, no dot) → group.
    static let byExtension: [String: FileGroup] = {
        var map: [String: FileGroup] = [:]
        for (group, extensions) in table { extensions.forEach { map[$0] = group } }
        return map
    }()
}

/// One row of the Folders view: a directory with everything under it, or a file.
struct FolderNode: Codable, Identifiable {
    let path: String
    let name: String
    let bytes: Int64
    let files: Int
    let isDirectory: Bool
    /// nil = not listed yet (the Folders view measures it when opened).
    var children: [FolderNode]?

    var id: String { path }
}

/// The result of one pass over the disk. Saved between launches.
struct DiskIndex: Codable {
    struct Stat: Codable {
        var bytes: Int64 = 0
        var files = 0
    }

    var date = Date()
    /// Seconds the pass took.
    var duration: Double = 0
    /// Indexed by `DiskKind.rawValue`.
    var kinds = [Stat](repeating: Stat(), count: DiskKind.allCases.count)
    /// Indexed by `FileGroup.rawValue`.
    var groups = [Stat](repeating: Stat(), count: FileGroup.allCases.count)
    /// The largest extensions by bytes ("" = no extension).
    var extensions: [String: Stat] = [:]
    /// Files of at least `DiskWalker.largeFileFloor`, largest first.
    var largeFiles: [LargeFile] = []
    /// The measured top-level locations, each listed two levels deep.
    var roots: [FolderNode] = []
    /// Folders macOS would not let us open.
    var denied: [String] = []
    /// Folders left out on purpose (need Full Disk Access).
    var skipped: [String] = []

    var measuredBytes: Int64 { kinds.reduce(0) { $0 + $1.bytes } }
    var totalFiles: Int { kinds.reduce(0) { $0 + $1.files } }

    func stat(_ kind: DiskKind) -> Stat { kinds[kind.rawValue] }
    func stat(_ group: FileGroup) -> Stat { groups[group.rawValue] }

    /// The biggest extensions inside one group.
    func topExtensions(in group: FileGroup, limit: Int = 4) -> [(name: String, stat: Stat)] {
        extensions
            .filter { (FileGroup.byExtension[$0.key] ?? .other) == group && !$0.key.isEmpty }
            .sorted { $0.value.bytes > $1.value.bytes }
            .prefix(limit)
            .map { (name: $0.key, stat: $0.value) }
    }
}
