// swift-tools-version: 6.3

import PackageDescription

// Same isolation semantics as the FP target.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

// A separate package so the library itself never depends on
// the benchmark package: run `swift package benchmark` from this directory.
let package = Package(
    name: "fp-swift-benchmarks",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "fp-swift", path: ".."),
        .package(
            url: "https://github.com/ordo-one/benchmark",
            .upToNextMajor(from: "1.38.1")
        ),
    ],
    targets: [
        .target(
            name: "BenchmarkSupport",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark")
            ],
            swiftSettings: swiftSettings
        )
    ]
)

// Each suite is its own executable under Benchmarks/, which is where the
// benchmark plugin discovers them, and depends on the product it measures.
let suites = [
    ("ArrayBenchmarks", "FP"),
    ("AsyncSequenceBenchmarks", "FP"),
    ("CombinatorBenchmarks", "FP"),
    ("RetryBenchmarks", "FPRetry"),
]

for (suite, product) in suites {
    package.targets.append(
        .executableTarget(
            name: suite,
            dependencies: [
                "BenchmarkSupport",
                .product(name: product, package: "fp-swift"),
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/\(suite)",
            swiftSettings: swiftSettings,
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        )
    )
}
