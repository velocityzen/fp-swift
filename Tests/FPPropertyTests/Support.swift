// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import HegelTesting
    import Synchronization
    import Testing

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

    /// An async sequence of `jobs` that counts how many elements were read.
    struct CountingSource<Element: Sendable>: AsyncSequence, Sendable {
        typealias Failure = Never

        let elements: [Element]
        /// How many times each read suspends first, like a slow source.
        var yields = 0
        /// Beaten on every read.
        var heartbeat: Heartbeat? = nil
        let reads = Counter()

        struct AsyncIterator: AsyncIteratorProtocol {
            let elements: [Element]
            let yields: Int
            let reads: Counter
            let heartbeat: Heartbeat?
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
            AsyncIterator(elements: elements, yields: yields, reads: reads, heartbeat: heartbeat)
        }
    }

    func collect<S: AsyncSequence>(
        _ sequence: S,
        _ heartbeat: Heartbeat? = nil
    ) async -> [S.Element] where S.Failure == Never {
        var values: [S.Element] = []
        for await value in sequence {
            values.append(value)
            heartbeat?.beat()
        }
        return values
    }

    /// How the test reads a sequence: at once, slowly, or from an actor.
    enum Consumer: Sendable, Hashable, CaseIterable {
        case prompt, slow, onActor

        /// Reads every element, and beats `heartbeat` for each one.
        func collect<S: AsyncSequence & Sendable>(
            _ sequence: S,
            _ heartbeat: Heartbeat? = nil
        ) async -> [S.Element]
        where S.Failure == Never, S.Element: Sendable {
            switch self {
                case .prompt: return await FPPropertyTests.collect(sequence, heartbeat)
                case .slow:
                    var values: [S.Element] = []
                    for await value in sequence {
                        values.append(value)
                        heartbeat?.beat()
                        for _ in 0..<3 {
                            await Task.yield()
                        }
                    }
                    return values
                case .onActor: return await Reader().collect(sequence, heartbeat)
            }
        }
    }

    /// Reads a sequence on its own actor, so the iterator runs isolated to it.
    actor Reader {
        func collect<S: AsyncSequence & Sendable>(
            _ sequence: S,
            _ heartbeat: Heartbeat?
        ) async -> [S.Element]
        where S.Failure == Never, S.Element: Sendable {
            var values: [S.Element] = []
            for await value in sequence {
                values.append(value)
                heartbeat?.beat()
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

    /// Counts steps of work: reads, finished transforms, delivered values. It
    /// tells a slow test case, which keeps beating, from a stuck one.
    final class Heartbeat: Sendable {
        private let beats = Atomic<Int>(0)
        var count: Int { beats.load(ordering: .relaxed) }
        func beat() { beats.add(1, ordering: .relaxed) }
    }

    /// How long a test case may go without a heartbeat before it counts as
    /// stuck. Every step of the generated work takes milliseconds; this
    /// leaves room for a busy machine.
    let stallLimit: Duration = .seconds(5)

    /// Runs `body` in a task of its own and returns its value, or nil once
    /// `heartbeat` has not beaten for `limit`. The stuck task is then
    /// cancelled.
    ///
    /// A lost wakeup makes the code under test wait forever. Hegel can neither
    /// report nor shrink a test that hangs, so this turns the hang into a
    /// failure: `try #require(await unlessStalled(...))`.
    func unlessStalled<T: Sendable>(
        _ heartbeat: Heartbeat,
        for limit: Duration = stallLimit,
        _ body: @escaping @Sendable () async -> T
    ) async -> T? {
        let (outcomes, delivery) = AsyncStream.makeStream(of: T?.self)
        let work = Task {
            delivery.yield(await body())
        }
        let watchdog = Task {
            var seen = heartbeat.count
            var since = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                let now = heartbeat.count
                if now != seen {
                    (seen, since) = (now, .now)
                } else if since.duration(to: .now) >= limit {
                    delivery.yield(nil)
                    return
                }
            }
        }
        var iterator = outcomes.makeAsyncIterator()
        let outcome = await iterator.next() ?? nil
        watchdog.cancel()
        if outcome == nil {
            work.cancel()
        }
        return outcome
    }

    /// Checks a reach claim once a property has run: some test case reached
    /// the state the property exists to test. A run of only a few cases, such
    /// as the replay of one stored failure, can't judge it, so it is skipped.
    func expectReached(
        _ reached: Int,
        in cases: Int,
        _ claim: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard cases >= 50 else { return }
        #expect(reached > 0, claim, sourceLocation: sourceLocation)
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

    /// Transforms that only a cancellation stops, counted so a property can
    /// check that each one was cancelled.
    ///
    /// A hang counts its cancellation in a cancellation handler, which runs
    /// when the task is cancelled. Waiting for the hanging task to finish
    /// instead would also wait for it to be scheduled again, which can take
    /// seconds on a busy machine.
    final class Hangs: Sendable {
        private let starts = Atomic<Int>(0)
        private let cancelled = Atomic<Int>(0)

        /// Hangs that started.
        var started: Int { starts.load(ordering: .sequentiallyConsistent) }

        /// Hangs that started and were not cancelled. Never too low: a hang
        /// that starts and is cancelled while this reads counts here.
        var uncancelled: Int {
            let cancelled = cancelled.load(ordering: .sequentiallyConsistent)
            return starts.load(ordering: .sequentiallyConsistent) - cancelled
        }

        /// Runs until cancelled, for at most a minute.
        func hang() async {
            starts.add(1, ordering: .sequentiallyConsistent)
            await withTaskCancellationHandler {
                try? await Task.sleep(for: .seconds(60))
            } onCancel: {
                cancelled.add(1, ordering: .sequentiallyConsistent)
            }
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
