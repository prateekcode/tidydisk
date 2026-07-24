import Foundation

struct DuplicateGroup: Identifiable {
    /// Content hash of the duplicated file.
    let id: String
    /// Copies, newest first — the newest is the "keeper".
    let files: [LargeFile]

    var wastedBytes: Int64 { files.dropFirst().reduce(0) { $0 + $1.bytes } }
}

extension Engine {
    /// Duplicate files in ~/Downloads (and ~/Desktop): same size, then same md5.
    static func findDuplicateGroups(minBytes: Int64 = 100_000) -> [DuplicateGroup] {
        let fm = FileManager.default
        let dirs = [NSHomeDirectory() + "/Downloads", NSHomeDirectory() + "/Desktop"]

        var bySize: [Int64: [LargeFile]] = [:]
        for dir in dirs {
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where !name.hasPrefix(".") {
                let path = dir + "/" + name
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      (attrs[.type] as? FileAttributeType) == .typeRegular,
                      let bytes = attrs[.size] as? Int64, bytes >= minBytes else { continue }
                let file = LargeFile(path: path, bytes: bytes,
                                     modified: (attrs[.modificationDate] as? Date) ?? .distantPast)
                bySize[bytes, default: []].append(file)
            }
        }

        var groups: [DuplicateGroup] = []
        for files in bySize.values where files.count > 1 {
            var byHash: [String: [LargeFile]] = [:]
            for file in files {
                let (status, output) = run(["md5", "-q", file.path])
                guard status == 0 else { continue }
                byHash[output.trimmingCharacters(in: .whitespacesAndNewlines), default: []].append(file)
            }
            for (hash, dups) in byHash where dups.count > 1 {
                groups.append(DuplicateGroup(id: hash, files: dups.sorted { $0.modified > $1.modified }))
            }
        }
        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }
}
