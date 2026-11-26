import Foundation

/// `TidyDisk --measure` prints the disk breakdown as text;
/// `TidyDisk --measure <folder>` lists that folder's children by size.
enum DiskReport {
    static func printAndExit() -> Never {
        let args = CommandLine.arguments
        let walker = DiskWalker()
        func row(_ label: String, _ bytes: Int64, _ files: Int) {
            let name = label.padding(toLength: 34, withPad: " ", startingAt: 0)
            let size = Format.bytes(bytes).padding(toLength: 12, withPad: " ", startingAt: 0)
            print("  \(name)\(size)\(Format.count(files)) files")
        }

        if let flag = args.firstIndex(of: "--measure"), args.count > flag + 1 {
            let path = (args[flag + 1] as NSString).standardizingPath
            let started = Date()
            let nodes = walker.listing(of: path)
            print("\(Engine.abbreviate(path)) in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
            nodes.prefix(40).forEach { row($0.name, $0.bytes, $0.files) }
            exit(0)
        }

        let index = walker.measure()
        print("Measured \(Format.bytes(index.measuredBytes)) in \(Format.count(index.totalFiles)) files, "
              + "\(String(format: "%.1f", index.duration)) s")
        print("\nBy location")
        DiskKind.allCases.forEach { row($0.title, index.stat($0).bytes, index.stat($0).files) }
        print("\nBy file type")
        FileGroup.allCases.forEach { row($0.title, index.stat($0).bytes, index.stat($0).files) }
        print("\nTop folders")
        index.roots.forEach { root in
            row(root.name, root.bytes, root.files)
            root.children?.prefix(8).forEach { row("  " + $0.name, $0.bytes, $0.files) }
        }
        print("\nLarge files (100 MB and up): \(index.largeFiles.count)")
        index.largeFiles.prefix(10).forEach { row(Engine.abbreviate($0.path), $0.bytes, 1) }
        if !index.skipped.isEmpty {
            print("\nNot measured without Full Disk Access:")
            index.skipped.forEach { print("  " + Engine.abbreviate($0)) }
        }
        if !index.denied.isEmpty {
            print("\nmacOS refused \(index.denied.count) folders, e.g.:")
            index.denied.prefix(8).forEach { print("  " + Engine.abbreviate($0)) }
        }
        exit(0)
    }
}
