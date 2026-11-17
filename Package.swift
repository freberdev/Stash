// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stash",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "StashCore"),
        .executableTarget(name: "Stash", dependencies: ["StashCore"]),
        .testTarget(name: "StashCoreTests", dependencies: ["StashCore"]),
    ]
)
