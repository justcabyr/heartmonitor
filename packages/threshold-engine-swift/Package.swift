// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ThresholdEngine",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "ThresholdEngine", targets: ["ThresholdEngine"]),
    ],
    targets: [
        .target(name: "ThresholdEngine"),
        .testTarget(
            name: "ThresholdEngineTests",
            dependencies: ["ThresholdEngine"]
        ),
    ]
)
