// swift-tools-version: 6.0
// Development tools pinned to exact versions, so local runs and CI format and lint identically.
// Usage: swift run -c release --package-path BuildTools swift-format --version
import PackageDescription

let package = Package(
    name: "BuildTools",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-format.git", exact: "604.0.0")
    ],
    targets: [
        .target(name: "BuildTools", path: "Sources")
    ]
)
