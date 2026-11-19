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
/// move between runs of the same code (concurrent maps aside, see
/// `workerPoolAllowance`), while times swing with the machine's load, so
/// times are reported but never fail a check.
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

// A concurrent map above `concurrency: 1` starts a worker for an element
// only when no worker is idle, so a call starts anywhere from one to
// `min(concurrency, elements)` workers, depending on how its reader and
// workers interleave. Its checked counts move with the number of workers by
// more than any percentage that would still catch a regression, so each one
// gets an absolute allowance instead: how far a call's counts can move
// between runs of the same code.

/// The checked counts one more worker adds to a call: its task and its
/// closure, and their retains and releases. With a single-thread
/// cooperative pool (`LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`) every call
/// starts `min(concurrency, elements)` workers and every count is exact;
/// these are the differences between `concurrency: 8` and `64` there.
let workerCost: [BenchmarkMetric: Int] = [
    .objectAllocCount: 2,
    .mallocCountTotal: 4,
    .retainCount: 2,
    .releaseCount: 4,
]

/// How far the retains and releases of one element may move with the path
/// it takes through the pipeline: to an idle worker or a new one, its result
/// to a waiting consumer or kept for a later one. Beyond the workers, runs of
/// the same code move by up to 0.3 per element; one more retain or release
/// per element is 1.
let elementPathTolerance = 0.5

/// The most a checked count of one call to a concurrent map can move
/// between runs of the same code, without a change to it.
///
/// Besides the workers, a results buffer grows when it fills, to twice its
/// size, which allocates. It starts with room for at least `concurrency`
/// results, so it grows at most log2(elements / concurrency) times.
func workerPoolAllowance(_ metric: BenchmarkMetric, concurrency: Int, elements: Int) -> Int {
    let workers = min(concurrency, elements)
    let workerSwing = (workers - 1) * (workerCost[metric] ?? 0)
    switch metric {
        case .objectAllocCount, .mallocCountTotal:
            let fills = (elements + concurrency - 1) / concurrency
            let growths = fills <= 1 ? 0 : Int.bitWidth - (fills - 1).leadingZeroBitCount
            return workerSwing + growths
        default:
            return workerSwing + Int(elementPathTolerance * Double(elements))
    }
}

/// How far, as a share of one call, a checked count of a racing benchmark
/// may move beyond its `raceSwing` before `baseline check` reports it. In a
/// sample of 1,000 calls half a call is far above the few allocations and
/// retains of the benchmark harness, and half of one more per call.
let raceCallShare = 0.5

func fpThresholds(
    scaling: BenchmarkScalingFactor,
    concurrency: Int,
    elements: Int,
    raceSwing: [BenchmarkMetric: Int]
) -> [BenchmarkMetric: BenchmarkThresholds] {
    Dictionary(
        uniqueKeysWithValues: fpMetrics.map { metric in
            guard checkedMetrics.contains(metric) else {
                return (metric, BenchmarkThresholds())
            }

            guard concurrency > 1 else {
                guard !raceSwing.isEmpty else {
                    return (metric, BenchmarkThresholds(relative: [.p50: checkedTolerance]))
                }

                // Absolute thresholds apply to raw samples, which cover
                // `scaling` calls each.
                let perCall = Double(raceSwing[metric] ?? 0) + raceCallShare
                let allowance = Int(perCall * Double(scaling.rawValue))
                return (metric, BenchmarkThresholds(absolute: [.p50: allowance]))
            }

            // Absolute thresholds apply to raw samples, which cover
            // `scaling` calls each.
            let allowance =
                workerPoolAllowance(metric, concurrency: concurrency, elements: elements)
                * scaling.rawValue
            return (metric, BenchmarkThresholds(absolute: [.p50: allowance]))
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
    ///
    /// For a concurrent map, pass its `concurrency` and the `elements` of its
    /// source. Above `concurrency: 1` its checked counts depend on how many
    /// workers its pool starts (see `workerPoolAllowance`).
    ///
    /// For a call that takes one of two paths by a race the benchmark cannot
    /// control, pass `raceSwing`: per checked metric, how much more its
    /// costlier path counts. Which path calls take moves with the machine's
    /// load, so its checked counts may move by that much plus half a call
    /// (`raceCallShare`) rather than by a percentage.
    static func fp(
        _ tags: [String: String] = [:],
        scaling: BenchmarkScalingFactor = .kilo,
        concurrency: Int = 1,
        elements: Int = 0,
        raceSwing: [BenchmarkMetric: Int] = [:]
    ) -> Self {
        precondition(concurrency == 1 || elements > 0, "a concurrent map needs its elements")
        precondition(concurrency == 1 || raceSwing.isEmpty, "a concurrent map has an allowance")
        return .init(
            metrics: fpMetrics,
            tags: tags,
            warmupIterations: 5,
            scalingFactor: scaling,
            maxDuration: .seconds(1),
            maxIterations: 10_000,
            thresholds: fpThresholds(
                scaling: scaling,
                concurrency: concurrency,
                elements: elements,
                raceSwing: raceSwing
            )
        )
    }
}

/// A clock whose sleeps return at once, on the time of `ContinuousClock`. A
/// benchmark of a sequence that waits on it measures how the sequence keeps
/// its deadlines, not the waits.
///
/// Its `sleep` is `@concurrent`, like those of the system clocks and the
/// `Clock` requirement, so a caller on an actor hops off it for the sleep
/// and back, as it would with `ContinuousClock`.
public struct ImmediateClock: Clock, Sendable {
    public typealias Instant = ContinuousClock.Instant

    public init() {}

    public var now: Instant { .now }

    public var minimumResolution: Duration { .zero }

    @concurrent
    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {}
}

/// The failure every failing benchmark transform returns.
public struct BenchError: Error, Equatable, Sendable {
    public init() {}
}

public typealias IntResult = Result<Int, BenchError>

/// A fair coin flip for `index`, the same on every run: the top bit of
/// SplitMix64's finalizer. Inputs built from it put their failures or `nil`s
/// at positions a branch predictor can't learn, so a branch on each element
/// mispredicts about half the time, where a regular pattern such as every
/// third element is predicted almost always.
public func coinFlip(_ index: Int) -> Bool {
    var z = UInt64(truncatingIfNeeded: index) &+ 0x9E37_79B9_7F4A_7C15
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return (z ^ (z >> 31)) >> 63 == 1
}

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

/// An async sequence of `0..<count` that throws `BenchError` where it would
/// end. It never suspends or allocates.
///
/// Its iterator implements `next(isolation:)`, as the standard library's
/// sequences do, so a read doesn't go through the default implementation,
/// which reaches a typed-throwing `next()` through the protocol and casts
/// the error it throws.
public struct ThrowingCountingSequence: AsyncSequence, Sendable {
    public typealias Element = Int
    public typealias Failure = BenchError

    public let count: Int

    public init(_ count: Int) {
        self.count = count
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(count: count)
    }

    public struct Iterator: AsyncIteratorProtocol {
        public typealias Failure = BenchError

        let count: Int
        var current = 0

        public mutating func next(
            isolation actor: isolated (any Actor)?
        ) async throws(BenchError) -> Int? {
            guard current < count else { throw BenchError() }
            defer { current += 1 }
            return current
        }

        public mutating func next() async throws(BenchError) -> Int? {
            try await next(isolation: nil)
        }
    }
}

/// An async sequence of `count` successes that never suspends or allocates.
/// The sinks that stop at the first failure read all of it.
public struct SuccessSequence: AsyncSequence, Sendable {
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
            return .success(current)
        }
    }
}

/// An async sequence of `count` failures that never suspends or allocates.
/// The sinks that stop at the first success read all of it.
public struct FailureSequence: AsyncSequence, Sendable {
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
            current += 1
            return .failure(BenchError())
        }
    }
}
