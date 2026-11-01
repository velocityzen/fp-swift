import Benchmark

/// Metrics recorded by every FP benchmark: time, instructions, heap traffic
/// and ARC traffic. Every value is reported per call of the API under test.
public let fpMetrics: [BenchmarkMetric] = [
    .wallClock,
    .cpuTotal,
    .throughput,
    .instructions,
    .mallocCountTotal,
    .mallocBytesCount,
    .memoryLeakedBytes,
    .objectAllocCount,
    .retainCount,
    .releaseCount,
]

/// The metrics `baseline check` fails on. Allocation and ARC counts barely
/// move between runs of the same code, while times swing with the machine's
/// load, so times are reported but never fail a check.
public let checkedMetrics: [BenchmarkMetric] = [
    .mallocCountTotal,
    .objectAllocCount,
    .retainCount,
    .releaseCount,
]

/// How far, in percent, a checked metric's median may move before
/// `baseline check` reports it. Two runs of the same code differ by up to
/// 3% where a race decides whether cancelled tasks allocate (`withAny`);
/// one allocation more per element or per operation is at least 6%.
let checkedTolerance = 5.0

var fpThresholds: [BenchmarkMetric: BenchmarkThresholds] {
    Dictionary(
        uniqueKeysWithValues: fpMetrics.map { metric in
            let thresholds =
                checkedMetrics.contains(metric)
                ? BenchmarkThresholds(relative: [.p50: checkedTolerance])
                : BenchmarkThresholds()
            return (metric, thresholds)
        }
    )
}

public extension Benchmark.Configuration {
    /// The configuration every FP benchmark uses.
    ///
    /// Each sample runs `scaling` calls in a `benchmark.scaledIterations`
    /// loop, and the scaled metrics are divided back to a single call. Use
    /// `.kilo` for calls in the micro- or nanosecond range, so timer and
    /// sampling overhead stays out of the numbers, and `.one` for calls that
    /// already take a millisecond or so.
    static func fp(
        _ tags: [String: String] = [:],
        scaling: BenchmarkScalingFactor = .kilo
    ) -> Self {
        .init(
            metrics: fpMetrics,
            tags: tags,
            warmupIterations: 5,
            scalingFactor: scaling,
            maxDuration: .seconds(1),
            maxIterations: 10_000,
            thresholds: fpThresholds
        )
    }
}

/// The failure every failing benchmark transform returns.
public struct BenchError: Error, Equatable, Sendable {
    public init() {}
}

public typealias IntResult = Result<Int, BenchError>

/// A value too wide for an existential's inline buffer (three words), so
/// wrapping it in `any Sendable` allocates a box.
public struct Wide: Sendable {
    public var a: Int
    public var b: Int
    public var c: Int
    public var d: Int

    public init(_ value: Int) {
        a = value
        b = value
        c = value
        d = value
    }
}

/// An async sequence of `0..<count` that never suspends or allocates, so a
/// benchmark measures the operator applied to it rather than its source.
public struct CountingSequence: AsyncSequence, Sendable {
    public typealias Element = Int
    public typealias Failure = Never

    public let count: Int

    public init(_ count: Int) {
        self.count = count
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(count: count)
    }

    public struct Iterator: AsyncIteratorProtocol {
        let count: Int
        var current = 0

        public mutating func next() async -> Int? {
            guard current < count else { return nil }
            defer { current += 1 }
            return current
        }
    }
}

/// An async sequence of `count` results, every third a failure, that never
/// suspends or allocates, so a benchmark measures the `Result` operator
/// applied to it rather than a mapping layer that makes the results.
public struct ResultSequence: AsyncSequence, Sendable {
    public typealias Element = IntResult
    public typealias Failure = Never

    public let count: Int

    public init(_ count: Int) {
        self.count = count
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(count: count)
    }

    public struct Iterator: AsyncIteratorProtocol {
        let count: Int
        var current = 0

        public mutating func next() async -> IntResult? {
            guard current < count else { return nil }
            defer { current += 1 }
            return current.isMultiple(of: 3) ? .failure(BenchError()) : .success(current)
        }
    }
}
