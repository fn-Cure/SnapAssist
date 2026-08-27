// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SnapAssist",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SnapAssistCore", targets: ["SnapAssistCore"]),
        .executable(name: "SnapAssist", targets: ["SnapAssist"]),
    ],
    targets: [
        .target(name: "SnapAssistCore"),
        .executableTarget(
            name: "SnapAssist",
            dependencies: ["SnapAssistCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "SnapAssistCoreTests", dependencies: ["SnapAssistCore"]),
    ]
)
