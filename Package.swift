// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SnapAssist",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SnapAssistCore", targets: ["SnapAssistCore"]),
        .executable(name: "SnapAssist", targets: ["SnapAssist"]),
        .executable(name: "SnapAssistFixture", targets: ["SnapAssistFixture"]),
    ],
    targets: [
        .target(name: "SnapAssistCore"),
        .executableTarget(
            name: "SnapAssist",
            dependencies: ["SnapAssistCore"]
        ),
        .executableTarget(name: "SnapAssistFixture"),
        .testTarget(name: "SnapAssistCoreTests", dependencies: ["SnapAssistCore"]),
    ]
)
