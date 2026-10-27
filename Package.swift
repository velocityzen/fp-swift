// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "fp-swift",
    platforms: [
        .macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v9), .visionOS(.v1),
    ],
    products: [
        .library(
            name: "FP",
            targets: ["FP"])
    ],
    targets: [
        .target(
            name: "FP",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
        .testTarget(
            name: "fpTests",
            dependencies: ["FP"]
        ),
    ]
)
