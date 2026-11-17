// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import FP
    import HegelTesting
    import Synchronization
    import Testing

    // MARK: - A clock the test drives

    /// A clock whose time moves only when the test advances it or something
    /// sleeps on it. A sleep ends `lateness` after its deadline, like a late
    /// wakeup. A sleep in a cancelled task throws `CancellationError`, like
    /// the system clocks.
    final class ScriptedClock: Clock {
        struct Instant: InstantProtocol {
            var offset: Duration
            func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
            func duration(to other: Instant) -> Duration { other.offset - offset }
            static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
        }

        private struct State {
            var now = Instant(offset: .zero)
            var lateness: Duration = .zero
            var sleeps: [Duration] = []
            var reads = 0
        }

        private let state = Mutex(State())

        var now: Instant {
            state.withLock { state in
                state.reads += 1
                return state.now
            }
        }

        var minimumResolution: Duration { .zero }

        /// The time since the clock started. Not counted as a read.
        var elapsed: Duration { state.withLock { $0.now.offset } }

        /// Every duration slept so far: from the time of the sleep to its
        /// deadline.
        var sleeps: [Duration] { state.withLock { $0.sleeps } }

        /// How many times `now` was read.
        var reads: Int { state.withLock { $0.reads } }

        /// How long after its deadline the next sleeps end.
        func wakeLate(by lateness: Duration) {
            state.withLock { $0.lateness = lateness }
        }

        func advance(by duration: Duration) {
            state.withLock { $0.now = $0.now.advanced(by: duration) }
        }

        func sleep(until deadline: Instant, tolerance: Duration?) async throws {
            try Task.checkCancellation()
            state.withLock { state in
                state.sleeps.append(state.now.duration(to: deadline))
                state.now = deadline.advanced(by: state.lateness)
            }
        }
    }

    /// The calls of a repeated operation: when each started, and whether its
    /// task was cancelled by then.
    final class RepeatCalls: Sendable {
        struct Call: Sendable, Equatable {
            var start: Duration
            var cancelled: Bool
        }

        private let calls = Mutex<[Call]>([])

        /// Records a call and returns its index, from 0.
        func record(start: Duration) -> Int {
            let call = Call(start: start, cancelled: Task.isCancelled)
            return calls.withLock { calls in
                calls.append(call)
                return calls.count - 1
            }
        }

        var all: [Call] { calls.withLock { $0 } }
    }

    // MARK: - Generated reads

    /// One pull of a repeating sequence: how long the reader takes before it
    /// asks, how late the wakeup is if the pull waits, and how long the call
    /// takes.
    struct RepeatStep: Sendable, Hashable, CustomStringConvertible {
        var gap: Duration
        var late: Duration
        var call: Duration

        var description: String { "gap \(gap), late \(late), call \(call)" }
    }

    enum RepeatGen {
        /// Where the interval counts from.
        static let anchor: Gen<RepeatAnchor> = .element(of: [.start, .finish])

        /// None, the smallest, everyday ones, and long ones.
        static let interval: Gen<Duration> = .oneOf(
            .just(.zero),
            Gen.int(in: 1...3).map { Duration(attoseconds: Int128($0)) },
            Gen.int(in: 1...2_000).map { Duration.milliseconds($0) },
            Gen.int(in: 0...1_000_000_000).map { Duration.seconds($0) }
        )

        /// Times around `interval`: just before it, at it and just after it,
        /// half and twice it; or none, or an everyday time. A call is due
        /// `interval` after the one before it started or finished, so a
        /// reader or a call that takes about that long lands near the
        /// deadline.
        static func around(_ interval: Duration) -> Gen<Duration> {
            let tick = Duration(attoseconds: 1)
            let near = [interval - tick, interval, interval + tick, interval / 2, interval * 2]
                .filter { $0 >= .zero }
            return .oneOf(
                .just(.zero),
                .element(of: near),
                Gen.int(in: 0...3_000).map { Duration.milliseconds($0) }
            )
        }

        /// None, the smallest, or a few milliseconds.
        static let lateness: Gen<Duration> = .oneOf(
            .just(.zero),
            .just(Duration(attoseconds: 1)),
            Gen.int(in: 1...100).map { Duration.milliseconds($0) }
        )

        /// The pulls of one test case. Whether its calls take time and its
        /// wakeups are late is drawn once for the whole case, so some cases
        /// have neither.
        static func steps(
            _ interval: Duration,
            slowCalls: Bool,
            lateWakeups: Bool
        ) -> Gen<[RepeatStep]> {
            .array(
                of: Hegel.zip(
                    around(interval),
                    lateWakeups ? lateness : .just(.zero),
                    slowCalls ? around(interval) : .just(.zero)
                )
                .map { RepeatStep(gap: $0, late: $1, call: $2) },
                count: 1...Int.max
            )
        }
    }

    // MARK: - Properties

    @Suite("Repeat properties", .hegel)
    struct RepeatProperties {
        /// Each pull starts one call and gives its element; nothing runs
        /// ahead of the reader. The first call starts when the reader first
        /// asks. Each later one starts once `interval` has passed since the
        /// one before it started, or with `from: .finish` since it finished,
        /// or at once if it has passed when the reader asks; a late wakeup
        /// delays it by that much. So calls never start closer than
        /// `interval` after the start, or the finish, of the one before, and
        /// an interval of zero never reads the clock.
        @Test(.hegel(testCases: 1_000))
        func callsFollowTheSchedule() async throws {
            try await property(
                reaching: [
                    "waited for the interval", "asked after the interval",
                    "asked right at the deadline", "woke late",
                    "waited longer after a slow call",
                ]
            ) { tc in
                let interval = try #draw(RepeatGen.interval, from: tc)
                let anchor = try #draw(RepeatGen.anchor, from: tc)
                let slowCalls = try #draw(.bool(), from: tc)
                let lateWakeups = try #draw(.bool(), from: tc)
                let steps = try #draw(
                    RepeatGen.steps(interval, slowCalls: slowCalls, lateWakeups: lateWakeups),
                    from: tc
                )

                let clock = ScriptedClock()
                let calls = RepeatCalls()
                let sequence = withRepeat(interval: interval, from: anchor, clock: clock) {
                    let index = calls.record(start: clock.elapsed)
                    clock.advance(by: index < steps.count ? steps[index].call : .zero)
                    return index + 1
                }

                var iterator = sequence.makeAsyncIterator()
                // The model: when the next call is due. Nil before the first.
                var due: Duration?
                // Where the interval of the next call counts from: the start
                // or the finish of the call before it.
                var anchorTime: Duration?
                for (index, step) in steps.enumerated() {
                    clock.advance(by: step.gap)
                    clock.wakeLate(by: step.late)
                    let asked = clock.elapsed
                    let slept = clock.sleeps.count

                    let element = await iterator.next()

                    let started = calls.all.map(\.start)
                    #expect(
                        element == index + 1,
                        "pull \(index + 1) gave \(String(describing: element))"
                    )
                    #expect(
                        started.count == index + 1,
                        "\(started.count) calls after \(index + 1) pulls"
                    )
                    guard started.count == index + 1 else { return }

                    let waits = due.map { asked < $0 } ?? false
                    let expectedStart = waits ? due! + step.late : asked
                    #expect(started[index] == expectedStart, "call \(index + 1)")
                    if let anchorTime {
                        #expect(started[index] - anchorTime >= interval, "call \(index + 1)")
                    }
                    let expectedSleeps = waits ? [due! - asked] : []
                    #expect(
                        Array(clock.sleeps.dropFirst(slept)) == expectedSleeps,
                        "call \(index + 1)"
                    )

                    if waits {
                        try tc.event("waited for the interval")
                        if step.late > .zero {
                            try tc.event("woke late")
                        }
                        if anchor == .finish, steps[index - 1].call > .zero {
                            try tc.event("waited longer after a slow call")
                        }
                    } else if let due, interval > .zero {
                        try tc.event(
                            asked == due
                                ? "asked right at the deadline" : "asked after the interval"
                        )
                    }
                    let finished = started[index] + step.call
                    anchorTime = anchor == .finish ? finished : started[index]
                    due = anchorTime! + interval
                }
                if interval == .zero {
                    #expect(clock.reads == 0)
                    try tc.event("interval of zero")
                }
                try tc.event(anchor == .finish ? "from the finish" : "from the start")
                try tc.event("pulls", value: Double(steps.count))
            }
        }

        /// Cancelling the reader's task ends the sequence, wherever the cancel
        /// lands and wherever the interval counts from: no call starts after
        /// it, every call that started gives its element, and once the
        /// sequence gives nil it stays ended.
        @Test(.hegel(testCases: 1_000))
        func cancellingTheReaderEndsTheSequence() async throws {
            try await property(
                reaching: [
                    "cancelled before the first call", "cancelled during a call",
                    "cancelled after a read", "not cancelled",
                ]
            ) { tc in
                let interval = try #draw(RepeatGen.interval, from: tc)
                let anchor = try #draw(RepeatGen.anchor, from: tc)
                let slowCalls = try #draw(.bool(), from: tc)
                let lateWakeups = try #draw(.bool(), from: tc)
                let steps = try #draw(
                    RepeatGen.steps(interval, slowCalls: slowCalls, lateWakeups: lateWakeups),
                    from: tc
                )

                let clock = ScriptedClock()
                let calls = RepeatCalls()
                // Three checkpoints per pull: the call starts, it ends, and
                // the reader gets its element.
                let run = try await tc.withRandomCancellation(
                    checkpoints: 0...(3 * steps.count),
                    endsWithin: stallLimit
                ) { cancellation in
                    let sequence = withRepeat(interval: interval, from: anchor, clock: clock) {
                        let index = calls.record(start: clock.elapsed)
                        cancellation.checkpoint("call \(index + 1) starts")
                        clock.advance(by: index < steps.count ? steps[index].call : .zero)
                        cancellation.checkpoint("call \(index + 1) ends")
                        return index + 1
                    }

                    var iterator = sequence.makeAsyncIterator()
                    var elements: [Int] = []
                    for step in steps {
                        clock.advance(by: step.gap)
                        clock.wakeLate(by: step.late)
                        guard let element = await iterator.next() else { break }
                        elements.append(element)
                        cancellation.checkpoint("read \(element)")
                    }
                    // Asked again after it gave nil: still nil, with no call.
                    let ended = elements.count < steps.count
                    let again = ended ? await iterator.next() : nil
                    return (elements, again)
                }
                let (elements, again) = run.value

                // The pull a cancel at checkpoint k lands in, from 1.
                let expectedCount =
                    run.cancelledAt.map { k in min((k + 2) / 3, steps.count) } ?? steps.count
                let made = calls.all
                #expect(
                    made.allSatisfy { !$0.cancelled },
                    "call \((made.firstIndex(where: \.cancelled) ?? 0) + 1) started after the cancel"
                )
                #expect(elements == Array(0..<expectedCount).map { $0 + 1 })
                #expect(
                    made.count == elements.count,
                    "\(made.count) calls, \(elements.count) elements"
                )
                #expect(again == nil)

                switch run.cancelledAt {
                    case nil: try tc.event("not cancelled")
                    case 0: try tc.event("cancelled before the first call")
                    case let k? where k % 3 == 0: try tc.event("cancelled after a read")
                    default: try tc.event("cancelled during a call")
                }
            }
        }
    }

#endif
