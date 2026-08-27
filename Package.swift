// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SnapAssist",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SnapAssistCore", targets: ["SnapAssistCore"]),
    ],
    targets: [
        .target(name: "SnapAssistCore"),
        .testTarget(name: "SnapAssistCoreTests", dependencies: ["SnapAssistCore"]),
    ]
)

