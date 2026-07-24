// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TidyDisk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TidyDisk",
            path: "Sources/TidyDisk"
        )
    ]
)
