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
            targets: ["FP"]
        ),
        .library(
            name: "FPRetry",
            targets: ["FPRetry"]
        ),
    ],
    dependencies: [
        // Property-based tests. Test targets only, so FP's users never
        // fetch it.
        .package(url: "https://github.com/velocityzen/hegel-swift", from: "0.51.8")
    ],
    targets: [
        .target(
            name: "FP",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
        // Retry policies and `withRetry` for async `Result`-returning work.
        // It imports nothing from FP, so it does not depend on it.
        .target(
            name: "FPRetry",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
        .testTarget(
            name: "fpTests",
            dependencies: ["FP"]
        ),
        .testTarget(
            name: "FPRetryTests",
            dependencies: ["FPRetry"]
        ),
        // Hegel's engine is built for macOS and Linux only, so on the other
        // platforms this target is empty: every file is behind
        // `#if os(macOS) || os(Linux)`.
        .testTarget(
            name: "FPPropertyTests",
            dependencies: [
                "FP",
                "FPRetry",
                .product(
                    name: "HegelTesting",
                    package: "hegel-swift",
                    condition: .when(platforms: [.macOS, .linux])
                ),
            ]
        ),
    ]
)
