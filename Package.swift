// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "fp-swift",
    platforms: [
        .macOS(.v26), .iOS(.v26), .tvOS(.v26), .watchOS(.v26), .visionOS(.v26),
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
