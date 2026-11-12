// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import HegelTesting
    import Synchronization

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
    /// depends on when a task was cancelled.
    func pause(_ job: Job) async {
        for _ in 0..<job.delay {
            await Task.yield()
        }
        if job.delay > 4 {
            // Not `try?`-ignored cancellation: a cancelled sleep returns early,
            // which is fine, the result doesn't change.
            try? await Task.sleep(for: .microseconds(job.delay * 20))
        }
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

    /// An async sequence of `jobs` that counts how many elements were read.
    struct CountingSource<Element: Sendable>: AsyncSequence, Sendable {
        typealias Failure = Never

        let elements: [Element]
        /// How many times each read suspends first, like a slow source.
        var yields = 0
        let reads = Reads()

        final class Reads: Sendable {
            private let count = Atomic<Int>(0)
            var value: Int { count.load(ordering: .sequentiallyConsistent) }
            func add() { count.add(1, ordering: .sequentiallyConsistent) }
        }

        struct AsyncIterator: AsyncIteratorProtocol {
            let elements: [Element]
            let yields: Int
            let reads: Reads
            var index = 0

            mutating func next() async -> Element? {
                for _ in 0..<yields {
                    await Task.yield()
                }
                guard index < elements.count else {
                    return nil
                }
                reads.add()
                defer { index += 1 }
                return elements[index]
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(elements: elements, yields: yields, reads: reads)
        }
    }

    func collect<S: AsyncSequence>(_ sequence: S) async -> [S.Element] where S.Failure == Never {
        var values: [S.Element] = []
        for await value in sequence {
            values.append(value)
        }
        return values
    }

    /// How the test reads a sequence: at once, slowly, or from an actor.
    enum Consumer: Sendable, Hashable, CaseIterable {
        case prompt, slow, onActor

        func collect<S: AsyncSequence & Sendable>(_ sequence: S) async -> [S.Element]
        where S.Failure == Never, S.Element: Sendable {
            switch self {
                case .prompt: return await FPPropertyTests.collect(sequence)
                case .slow:
                    var values: [S.Element] = []
                    for await value in sequence {
                        values.append(value)
                        for _ in 0..<3 {
                            await Task.yield()
                        }
                    }
                    return values
                case .onActor: return await Reader().collect(sequence)
            }
        }
    }

    /// Reads a sequence on its own actor, so the iterator runs isolated to it.
    actor Reader {
        func collect<S: AsyncSequence & Sendable>(_ sequence: S) async -> [S.Element]
        where S.Failure == Never, S.Element: Sendable {
            var values: [S.Element] = []
            for await value in sequence {
                values.append(value)
            }
            return values
        }
    }

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

        static let consumer: Gen<Consumer> = .element(of: Consumer.allCases)

        /// Jobs: usually a few, sometimes hundreds. Hegel keeps arrays short
        /// unless told otherwise, so the long ones get a minimum length.
        static func jobs(_ outcomes: [Job.Outcome] = [.keep], min: Int = 0) -> Gen<[Job]> {
            .oneOf(
                .array(of: .job(outcomes: outcomes), count: min...Int.max),
                .array(of: .job(outcomes: outcomes), count: Swift.max(min, 50)...Int.max)
            )
        }
    }

    /// Runs until cancelled, for at most a minute: a transform that only a
    /// cancellation stops.
    func hangUntilCancelled() async {
        try? await Task.sleep(for: .seconds(60))
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

    /// Counts transforms that are running now.
    final class Running: Sendable {
        private let count = Atomic<Int>(0)
        var value: Int { count.load(ordering: .sequentiallyConsistent) }

        func run<T>(_ body: () async -> T) async -> T {
            count.add(1, ordering: .sequentiallyConsistent)
            defer { count.subtract(1, ordering: .sequentiallyConsistent) }
            return await body()
        }
    }

#endif
