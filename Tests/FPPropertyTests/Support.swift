// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import Foundation
    import HegelTesting
    import Synchronization

    /// A property's number of test cases: `base`, times `FP_PROPERTY_SCALE`
    /// when it is set, as in the nightly run.
    ///
    /// A count given in Swift overrides every Hegel profile, so a deeper
    /// profile in `hegel.toml` could not raise it.
    func cases(_ base: Int) -> Int {
        let scale = ProcessInfo.processInfo.environment["FP_PROPERTY_SCALE"].flatMap { Int($0) }
        return base * max(scale ?? 1, 1)
    }

    /// One element of generated async work: a value, how long its transform
    /// takes, and what the transform does with it.
    struct Job: Sendable, Hashable, CustomStringConvertible {
        var value: Int
        /// How many times the transform suspends before it finishes. Above 4, it
        /// also sleeps, so that work really overlaps across threads.
        var delay: Int
        var outcome: Outcome

        enum Outcome: Sendable, Hashable, CaseIterable {
            case keep, drop, fail
        }

        var description: String { "\(value)/\(delay)/\(outcome)" }
    }

    struct JobFailure: Error, Hashable {
        let value: Int
    }

    extension Gen where Value == Job {
        static func job(outcomes: [Job.Outcome] = [.keep]) -> Gen<Job> {
            Hegel.zip(
                .oneOf(.int(in: 0...99), .int()),
                // Suspensions; each costs time, so the long branch stops at 1,000.
                .oneOf(.int(in: 0...8), .int(in: 0...1_000)),
                .element(of: outcomes)
            )
            .map { Job(value: $0, delay: $1, outcome: $2) }
        }
    }

    /// Spends `job.delay` suspensions, ignoring cancellation, so a result never
    /// depends on when a task was cancelled. Beats `heartbeat` when done.
    func pause(_ job: Job, _ heartbeat: Heartbeat? = nil) async {
        for _ in 0..<job.delay {
            await Task.yield()
        }
        if job.delay > 4 {
            // Not `try?`-ignored cancellation: a cancelled sleep returns early,
            // which is fine, the result doesn't change.
            try? await Task.sleep(for: .microseconds(job.delay * 20))
        }
        heartbeat?.beat()
    }

    /// The transform the properties use, and its model.
    func transformed(_ job: Job) -> Int { job.value &* 2 &+ 1 }

    /// Counts how many transforms run at once, and the most there ever were.
    final class InFlight: Sendable {
        private let current = Atomic<Int>(0)
        private let highest = Atomic<Int>(0)

        var peak: Int { highest.load(ordering: .sequentiallyConsistent) }

        func run<T>(_ body: () async -> T) async -> T {
            let now = current.add(1, ordering: .sequentiallyConsistent).newValue
            _ = highest.max(now, ordering: .sequentiallyConsistent)
            defer { current.subtract(1, ordering: .sequentiallyConsistent) }
            return await body()
        }
    }

    /// An async sequence of `jobs` that counts how many elements were read,
    /// and how many of its iterators were made and released.
    struct CountingSource<Element: Sendable>: AsyncSequence, Sendable {
        typealias Failure = Never

        let elements: [Element]
        /// How many times each read suspends first, like a slow source.
        var yields = 0
        /// Beaten on every read.
        var heartbeat: Heartbeat? = nil
        let reads = Counter()
        let iterators = Counter()
        let released = Counter()

        struct AsyncIterator: AsyncIteratorProtocol {
            let elements: [Element]
            let yields: Int
            let reads: Counter
            let heartbeat: Heartbeat?
            /// Shared by the iterator's copies; counts the release of the last.
            let lifetime: Lifetime
            var index = 0

            mutating func next() async -> Element? {
                for _ in 0..<yields {
                    await Task.yield()
                }
                guard index < elements.count else {
                    return nil
                }
                reads.add()
                heartbeat?.beat()
                defer { index += 1 }
                return elements[index]
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            iterators.add()
            return AsyncIterator(
                elements: elements,
                yields: yields,
                reads: reads,
                heartbeat: heartbeat,
                lifetime: Lifetime(released)
            )
        }

        /// This source, beating `heartbeat` on every read. The copy shares
        /// this one's counters, so a source made before
        /// `withStallDetection` can be read inside it.
        func beating(_ heartbeat: Heartbeat) -> Self {
            var source = self
            source.heartbeat = heartbeat
            return source
        }
    }

    /// Adds to `released` when it is released.
    final class Lifetime: Sendable {
        let released: Counter
        init(_ released: Counter) { self.released = released }
        deinit { released.add() }
    }

    /// How far the reader of a concurrent map got ahead of its consumer:
    /// elements read, less the values delivered and the elements the
    /// transform dropped.
    ///
    /// It is measured each time the consumer is done with a value. The
    /// consumer is then outside `next()`, so every result the pipeline has
    /// counted as taken is one the test has counted as delivered.
    final class ReadAhead: Sendable {
        private let reads: Counter
        /// Elements the transform dropped. The transform adds to it before it
        /// returns nil, which can only make the measure lower.
        let dropped = Counter()
        private let delivered = Atomic<Int>(0)
        private let highest = Atomic<Int>(0)

        init(of reads: Counter) { self.reads = reads }

        /// The most it ever was.
        var most: Int { highest.load(ordering: .sequentiallyConsistent) }

        /// Counts one value delivered, after the consumer is done with it.
        func measure() {
            let delivered = delivered.add(1, ordering: .sequentiallyConsistent).newValue
            let ahead = reads.value - delivered - dropped.value
            _ = highest.max(ahead, ordering: .sequentiallyConsistent)
        }
    }

    func collect<S: AsyncSequence>(
        _ sequence: S,
        _ heartbeat: Heartbeat? = nil,
        _ readAhead: ReadAhead? = nil
    ) async -> [S.Element] where S.Failure == Never {
        var values: [S.Element] = []
        for await value in sequence {
            values.append(value)
            heartbeat?.beat()
            readAhead?.measure()
        }
        return values
    }

    /// How the test reads a sequence: at once, slowly, or from an actor.
    enum Consumer: Sendable, Hashable {
        case prompt
        /// Suspends `yields` times after each value, so that results pile up
        /// behind it.
        case slow(yields: Int)
        case onActor

        /// Reads every element. For each one, beats `heartbeat` and measures
        /// `readAhead`.
        func collect<S: AsyncSequence & Sendable>(
            _ sequence: S,
            _ heartbeat: Heartbeat? = nil,
            _ readAhead: ReadAhead? = nil
        ) async -> [S.Element]
        where S.Failure == Never, S.Element: Sendable {
            switch self {
                case .prompt: return await FPPropertyTests.collect(sequence, heartbeat, readAhead)
                case .slow(let yields):
                    var values: [S.Element] = []
                    for await value in sequence {
                        values.append(value)
                        heartbeat?.beat()
                        // The reader catches up meanwhile, so the measure
                        // comes after.
                        for _ in 0..<yields {
                            await Task.yield()
                        }
                        readAhead?.measure()
                    }
                    return values
                case .onActor: return await Reader().collect(sequence, heartbeat, readAhead)
            }
        }
    }

    /// Reads a sequence on its own actor, so the iterator runs isolated to it.
    actor Reader {
        func collect<S: AsyncSequence & Sendable>(
            _ sequence: S,
            _ heartbeat: Heartbeat?,
            _ readAhead: ReadAhead?
        ) async -> [S.Element]
        where S.Failure == Never, S.Element: Sendable {
            var values: [S.Element] = []
            for await value in sequence {
                values.append(value)
                heartbeat?.beat()
                readAhead?.measure()
            }
            return values
        }
    }

    /// A count that many tasks can add to.
    final class Counter: Sendable {
        private let count = Atomic<Int>(0)
        var value: Int { count.load(ordering: .sequentiallyConsistent) }
        func add() { count.add(1, ordering: .sequentiallyConsistent) }
    }

    /// How long a test case may go without a heartbeat before it counts as
    /// stuck, for `withStallDetection(after:)`. Every step of the generated
    /// work takes milliseconds; this leaves room for a busy machine.
    ///
    /// ThreadSanitizer slows every task switch, and the properties run side
    /// by side, so on a CI machine with few cores a pause of a few hundred
    /// suspensions can wait more than 5 seconds for a thread. Under it the
    /// limit is a minute: that run looks for races, and the other runs still
    /// catch hangs at 5 seconds.
    let stallLimit: Duration = .seconds(underThreadSanitizer ? 60 : 5)

    /// Whether ThreadSanitizer's runtime is loaded, which defines
    /// `__tsan_init`.
    let underThreadSanitizer: Bool = {
        // RTLD_DEFAULT, which Swift does not import: a lookup in every
        // loaded image.
        #if canImport(Darwin)
            let everyImage = UnsafeMutableRawPointer(bitPattern: -2)
        #else
            let everyImage: UnsafeMutableRawPointer? = nil
        #endif
        return dlsym(everyImage, "__tsan_init") != nil
    }()

    /// Shared draws: mostly small values, so most cases run fast, and sometimes
    /// the extremes the API accepts.
    enum Draw {
        /// Small; past the element count; around the 1024 slots a buffer makes
        /// room for up front; or unbounded.
        static let concurrency: Gen<Int> = .oneOf(
            .int(in: 1...8),
            .int(in: 1...Int.max),
            .int(in: 1_020...1_030),
            .just(.max)
        )

        /// `concurrency`, at least 2: always the concurrent pipeline.
        static let parallel: Gen<Int> = .oneOf(
            .int(in: 2...8),
            .int(in: 2...Int.max),
            .int(in: 1_020...1_030),
            .just(.max)
        )

        static let bufferLimit: Gen<Int> = .oneOf(
            .just(.max),
            .int(in: 0...6),
            .int(in: 0...Int.max),
            .int(in: 1_020...1_030)
        )

        /// Suspensions per source read: usually none. Each costs time on every
        /// read, so the long branch stops at 1,000.
        static let sourceYields: Gen<Int> = .oneOf(.just(0), .int(in: 0...3), .int(in: 0...1_000))

        /// Prompt, from an actor, or slow: a few suspensions per value, or up
        /// to hundreds. Each costs time on every value, so it stops at 300.
        static let consumer: Gen<Consumer> = .oneOf(
            .just(.prompt),
            .just(.onActor),
            Gen<Int>.int(in: 1...8).map { .slow(yields: $0) },
            Gen<Int>.int(in: 0...300).map { .slow(yields: $0) }
        )

        /// Jobs: usually a few, sometimes hundreds. Hegel keeps arrays short
        /// unless told otherwise, so the long ones get a minimum length.
        static func jobs(_ outcomes: [Job.Outcome] = [.keep], min: Int = 0) -> Gen<[Job]> {
            .oneOf(
                .array(of: .job(outcomes: outcomes), count: min...Int.max),
                .array(of: .job(outcomes: outcomes), count: Swift.max(min, 50)...Int.max)
            )
        }

        /// The outcomes one test case's jobs draw from, for `jobs(_:min:)`: a
        /// few picks from `allowed`, so an outcome can be missing, rare or
        /// in every job.
        static func outcomes(_ allowed: [Job.Outcome]) -> Gen<[Job.Outcome]> {
            .array(of: .element(of: allowed), count: 1...4)
        }

        /// Which jobs skip the transform: none, or those whose value is a
        /// multiple of the drawn number. 1 passes every job through.
        static let passEvery: Gen<Int?> = .optional(.int(in: 1...4))

        /// The `passthrough` for `passEvery`, and its model: a job that skips
        /// the transform becomes its negated value.
        static func passthrough(_ every: Int?) -> (@Sendable (Job) -> Int?)? {
            guard let every else { return nil }
            return { job in job.value.isMultiple(of: every) ? 0 &- job.value : nil }
        }
    }

    /// Waits up to `limit` for `condition`, checking every millisecond.
    func eventually(within limit: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }

#endif
