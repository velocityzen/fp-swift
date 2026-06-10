// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "fp-swift",
    platforms: [
        .macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6), .visionOS(.v1),
    ],
    products: [
        .library(
            name: "FP",
            targets: ["FP"])
    ],
    targets: [
        .target(
            name: "FP"),
        .testTarget(
            name: "fpTests",
            dependencies: ["FP"]
        ),
    ]
)
