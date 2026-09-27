// swift-tools-version: 6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny")
]

let package = Package(
    name: "AERESBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AERESBar", targets: ["AERESBar"])
    ],
    targets: [
        // Domain, providers and state. Foundation only: no AppKit, fully unit-testable.
        .target(
            name: "AERESBarCore",
            swiftSettings: swiftSettings
        ),
        // Menu bar items, hover panel, brand marks (AppKit + SwiftUI).
        .target(
            name: "AERESBarUI",
            dependencies: ["AERESBarCore"],
            swiftSettings: swiftSettings
        ),
        // Composition root and command-line entry point.
        .executableTarget(
            name: "AERESBar",
            dependencies: ["AERESBarCore", "AERESBarUI"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AERESBarCoreTests",
            dependencies: ["AERESBarCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AERESBarUITests",
            dependencies: ["AERESBarUI", "AERESBarCore"],
            swiftSettings: swiftSettings
        ),
    ]
)
