// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexLevel",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexLevelCore", targets: ["CodexLevelCore"]),
        .executable(name: "CodexLevel", targets: ["CodexLevelApp"]),
    ],
    targets: [
        .target(name: "CodexLevelCore"),
        .executableTarget(name: "CodexLevelApp", dependencies: ["CodexLevelCore"]),
        .testTarget(name: "CodexLevelCoreTests", dependencies: ["CodexLevelCore"]),
        .testTarget(name: "CodexLevelAppTests", dependencies: ["CodexLevelApp", "CodexLevelCore"]),
    ]
)
