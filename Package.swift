// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacToCast",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MacToCast"),
        .testTarget(name: "MacToCastTests", dependencies: ["MacToCast"]),
    ]
)
