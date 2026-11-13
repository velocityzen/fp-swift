// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import HegelTesting
    import Synchronization
    import Testing

    @testable import FPRetry

    // MARK: - The model: exact arithmetic on attoseconds

    /// Retry waits as exact attosecond counts, with the saturation the docs
    /// promise: every wait between zero and `RetryPolicy.maximumDelay`.
    enum Exact {
        static let maximum = Int128(Int64.max) * 1_000_000_000_000_000

        static func clamped(_ d: Duration) -> Int128 {
            min(max(d.attoseconds, 0), maximum)
        }

        static func clampedDuration(_ d: Duration) -> Duration {
            Duration(attoseconds: clamped(d))
        }

        static func adding(_ a: Duration, _ b: Duration) -> Duration {
            Duration(attoseconds: min(clamped(a) + clamped(b), maximum))
        }

        /// `base * 2^exponent`, at most the maximum.
        static func doubled(_ base: Duration, times exponent: Int) -> Duration {
            let b = clamped(base)
            let e = max(exponent, 0)
            guard b > 0 else { return .zero }
            guard e < 120, b <= maximum >> e else {
                return Duration(attoseconds: maximum)
            }
            return Duration(attoseconds: b << e)
        }
    }

    // MARK: - Generated policies

    /// A retry policy, as the expression that builds it, so the test can both
    /// build the policy and evaluate the model of it.
    indirect enum PolicyExpr: Sendable, CustomStringConvertible {
        case limitRetries(Int)
        case constantDelay(Duration)
        case exponentialBackoff(Duration)
        case requestedDelay
        case and(PolicyExpr, PolicyExpr)
        case capDelay(PolicyExpr, Duration)
        case limitRetriesByDelay(PolicyExpr, Duration)
        case limitRetriesByCumulativeDelay(PolicyExpr, Duration)
        /// Jitter with a one-point range, so the multiplier is known.
        case jitter(PolicyExpr, Double)

        var policy: RetryPolicy {
            switch self {
                case .limitRetries(let n): .limitRetries(n)
                case .constantDelay(let d): .constantDelay(d)
                case .exponentialBackoff(let d): .exponentialBackoff(d)
                case .requestedDelay: .requestedDelay
                case .and(let a, let b): a.policy.and(b.policy)
                case .capDelay(let p, let d): p.policy.capDelay(d)
                case .limitRetriesByDelay(let p, let d): p.policy.limitRetriesByDelay(d)
                case .limitRetriesByCumulativeDelay(let p, let d):
                    p.policy.limitRetriesByCumulativeDelay(d)
                case .jitter(let p, let c): p.policy.jitter(c...c)
            }
        }

        /// What the policy should return for `status`, before `withRetry`
        /// clamps it.
        func model(_ status: RetryStatus) -> Duration? {
            switch self {
                case .limitRetries(let n):
                    return status.iteration < n ? .zero : nil
                case .constantDelay(let d):
                    return d
                case .exponentialBackoff(let d):
                    return Exact.doubled(d, times: status.iteration)
                case .requestedDelay:
                    return status.requestedDelay ?? .zero
                case .and(let a, let b):
                    guard let x = a.model(status), let y = b.model(status) else { return nil }
                    return max(x, y)
                case .capDelay(let p, let d):
                    return p.model(status).map { min($0, d) }
                case .limitRetriesByDelay(let p, let d):
                    return p.model(status).flatMap { $0 <= d ? $0 : nil }
                case .limitRetriesByCumulativeDelay(let p, let d):
                    return p.model(status).flatMap { delay in
                        Exact.adding(status.cumulativeDelay, delay) <= d ? delay : nil
                    }
                case .jitter(let p, let c):
                    return p.model(status).map { delay in
                        let base = Exact.clampedDuration(delay)
                        guard c > 0, base > .zero else { return .zero }
                        let exact = Double(Exact.clamped(delay)) * c
                        guard exact < Double(Exact.maximum) else {
                            return Duration(attoseconds: Exact.maximum)
                        }
                        return base * c
                    }
            }
        }

        var description: String {
            switch self {
                case .limitRetries(let n): ".limitRetries(\(n))"
                case .constantDelay(let d): ".constantDelay(\(d))"
                case .exponentialBackoff(let d): ".exponentialBackoff(\(d))"
                case .requestedDelay: ".requestedDelay"
                case .and(let a, let b): "\(a).and(\(b))"
                case .capDelay(let p, let d): "\(p).capDelay(\(d))"
                case .limitRetriesByDelay(let p, let d): "\(p).limitRetriesByDelay(\(d))"
                case .limitRetriesByCumulativeDelay(let p, let d):
                    "\(p).limitRetriesByCumulativeDelay(\(d))"
                case .jitter(let p, let c): "\(p).jitter(\(c)...\(c))"
            }
        }
    }

    enum RetryGen {
        static let maximum = Duration(attoseconds: Exact.maximum)

        /// Waits of every size: everyday ones, sub-nanosecond ones, ones near and
        /// past the maximum, and negative ones.
        static let duration: Gen<Duration> = .oneOf(
            Gen.int(in: 0...2_000).map { Duration.milliseconds($0) },
            Gen.int(in: -3...3).map { Duration(attoseconds: Int128($0)) },
            Gen.int(in: 0...100).map { Duration.nanoseconds($0) },
            Gen<Int64>.integer().map { Duration.milliseconds($0) },
            Gen<Int64>.integer().map { Duration.seconds($0) },
            .element(of: [.zero, maximum, maximum + .nanoseconds(1), .zero - maximum])
        )

        /// The time the policy has waited so far: only waits in range.
        static let status: Gen<RetryStatus> = Hegel.zip(
            .oneOf(
                .int(in: 0...8),
                .int(in: 0...130),
                .int(),
                .element(of: [.max, .max - 1, .min, -1])
            ),
            duration,
            .optional(duration),
            .optional(duration)
        ).map { iteration, cumulative, previous, requested in
            RetryStatus(
                iteration: iteration,
                cumulativeDelay: cumulative,
                previousDelay: previous,
                requestedDelay: requested
            )
        }

        /// Doublings: everyday counts, any count, and counts around 113, after
        /// which even a 1-attosecond wait is past the maximum.
        static let exponent: Gen<Int> = .oneOf(
            .int(in: -2...70),
            .int(in: 108...116),
            .int()
        )

        /// Bases at the edge of saturating after `exponent` doublings: the
        /// largest that still fits, and its neighbours. Or any wait.
        static func doublingBase(after exponent: Int) -> Gen<Duration> {
            let edge = Exact.maximum >> min(max(exponent, 0), 127)
            return .oneOf(
                Gen.element(of: [0, -1, 1]).map { Duration(attoseconds: edge + Int128($0)) },
                duration
            )
        }

        /// Any `Double`: NaN, infinities and negatives scale to no wait or the
        /// maximum.
        static let factor: Gen<Double> = .oneOf(
            .double(in: -2...4),
            .double(),
            .element(of: [0, 0.5, 1, 2, 1e300, .infinity, -.infinity, .nan])
        )

        /// Factors for `base`: any, or at the cutoff past which scaling it
        /// gives the maximum, and the `Double`s either side of the cutoff.
        static func factor(for base: Duration) -> Gen<Double> {
            let clamped = Exact.clampedDuration(base)
            guard clamped > .zero else { return factor }
            let cutoff = maximum / clamped
            return .oneOf(factor, .element(of: [cutoff, cutoff.nextDown, cutoff.nextUp]))
        }

        static let leaf: Gen<PolicyExpr> = .oneOf(
            Gen.oneOf(.int(in: 0...10), .int(), .element(of: [.max, .min, -1]))
                .map { PolicyExpr.limitRetries($0) },
            duration.map { PolicyExpr.constantDelay($0) },
            duration.map { PolicyExpr.exponentialBackoff($0) },
            .just(.requestedDelay)
        )

        static let policy: Gen<PolicyExpr> = .recursive(leaf: leaf) { sub in
            Gen.oneOf(
                Hegel.zip(sub, sub).map { PolicyExpr.and($0, $1) },
                Hegel.zip(sub, duration).map { PolicyExpr.capDelay($0, $1) },
                Hegel.zip(sub, duration).map { PolicyExpr.limitRetriesByDelay($0, $1) },
                Hegel.zip(sub, duration).map { PolicyExpr.limitRetriesByCumulativeDelay($0, $1) },
                // `jitter(c...c)` needs a finite width, so a finite `c`.
                Hegel.zip(sub, .oneOf(.double(in: -2...4), finite)).map {
                    PolicyExpr.jitter($0, $1)
                }
            )
        }
    }

    // MARK: - A clock that records its sleeps

    /// Sleeps return at once and are recorded. A sleep in a cancelled task
    /// throws, like the system clocks.
    final class RecordingClock: Clock {
        struct Instant: InstantProtocol {
            var offset: Duration
            func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
            func duration(to other: Instant) -> Duration { other.offset - offset }
            static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
        }

        private let state = Mutex((now: Instant(offset: .zero), sleeps: [Duration]()))

        var now: Instant { state.withLock { $0.now } }
        var minimumResolution: Duration { .zero }
        var sleeps: [Duration] { state.withLock { $0.sleeps } }

        func sleep(until deadline: Instant, tolerance: Duration?) async throws {
            try Task.checkCancellation()
            state.withLock { state in
                state.sleeps.append(state.now.duration(to: deadline))
                state.now = deadline
            }
        }
    }

    // MARK: - Scripted attempts

    /// What one attempt of the retried operation does.
    struct Attempt: Sendable, Hashable, CustomStringConvertible {
        var succeeds: Bool
        var retryable: Bool
        var requested: Duration?
        /// The attempt cancels the task it runs in.
        var cancels: Bool

        var description: String {
            let outcome = succeeds ? "ok" : retryable ? "retryable" : "fatal"
            let asked = requested.map { " asks \($0)" } ?? ""
            return outcome + asked + (cancels ? " cancels" : "")
        }

        static let success = Attempt(
            succeeds: true,
            retryable: false,
            requested: nil,
            cancels: false
        )
    }

    struct AttemptFailure: Error, Hashable {
        let attempt: Int
        let retryable: Bool
        let requested: Duration?
    }

    extension RetryGen {
        /// How often an attempt succeeds, fails in a way that is retried, and
        /// cancels its task, drawn once per test case.
        static let attemptRates: Gen<(succeeds: Double, retryable: Double, cancels: Double)> =
            Hegel.zip(
                .element(of: [0.05, 0.2, 0.5]),
                .element(of: [0.5, 0.85, 1]),
                .element(of: [0, 0.05, 0.3])
            ).map { (succeeds: $0, retryable: $1, cancels: $2) }

        static func attempt(
            _ rates: (succeeds: Double, retryable: Double, cancels: Double)
        ) -> Gen<Attempt> {
            Hegel.zip(
                .bool(probability: rates.succeeds),
                .bool(probability: rates.retryable),
                .optional(duration),
                .bool(probability: rates.cancels)
            ).map { Attempt(succeeds: $0, retryable: $1, requested: $2, cancels: $3) }
        }
    }

    /// SplitMix64, so seeded jitter is reproducible.
    struct SplitMix: RandomNumberGenerator, Sendable {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    extension RetryGen {
        /// Jitter ranges: everyday ones, negative ones, and ones near the
        /// largest `Double` whose width is still finite.
        static let jitterRange: Gen<ClosedRange<Double>> = .oneOf(
            Hegel.zip(.double(in: -2...2), .double(in: 0...2)).map { $0...($0 + $1) },
            Hegel.zip(.double(in: -1e6...1e6), .double(in: 0...1e6)).map { $0...($0 + $1) },
            .element(of: [0...0, 0...1, -1...0, 1e300...1e300, -1e300...1e300, 0...1e300]),
            // Any range of finite numbers whose width is finite too.
            Hegel.zip(finite, finite).map { min($0, $1)...max($0, $1) }
                .filter { ($0.upperBound - $0.lowerBound).isFinite }
        )

        static let finite: Gen<Double> = .double(
            in: -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude
        )
    }

    // MARK: - Properties

    @Suite("Retry properties", .hegel)
    struct RetryProperties {
        /// Clamping gives the wait itself when it is in range, and the nearest
        /// end otherwise.
        @Test(.hegel(testCases: cases(1_000)))
        func clampingStaysInRange() throws {
            try property { tc in
                let d = try #draw(RetryGen.duration, from: tc)
                #expect(d.clampedToRetryDelay == Exact.clampedDuration(d))

                if d < .zero {
                    try tc.event("below zero")
                } else if d > RetryGen.maximum {
                    try tc.event("past the maximum")
                }
            }
        }

        /// Adding two waits in range is exact, and the maximum when the sum is
        /// past it.
        @Test(.hegel(testCases: cases(1_000)))
        func addingSaturates() throws {
            try property { tc in
                let a = Exact.clampedDuration(try #draw(RetryGen.duration, from: tc))
                let b = Exact.clampedDuration(try #draw(RetryGen.duration, from: tc))
                #expect(a.addingRetryDelay(b) == Exact.adding(a, b))

                if Exact.adding(a, b) == RetryGen.maximum {
                    try tc.event("saturated")
                }
            }
        }

        /// Doubling is exact while the result fits, and the maximum after.
        @Test(.hegel(testCases: cases(1_000)))
        func doublingIsExactUntilTheMaximum() throws {
            try property(reaching: ["exact, at the largest base that fits"]) { tc in
                let exponent = try #draw(RetryGen.exponent, from: tc)
                let base = try #draw(RetryGen.doublingBase(after: exponent), from: tc)
                let doubled = base.doubled(times: exponent)
                #expect(doubled == Exact.doubled(base, times: exponent))

                let edge = Exact.maximum >> min(max(exponent, 0), 127)
                if doubled == RetryGen.maximum {
                    try tc.event("saturated")
                } else if base.attoseconds == edge, edge > 0 {
                    try tc.event("exact, at the largest base that fits")
                }
            }
        }

        /// Scaling multiplies in floating point, so only roughly; but it never
        /// leaves the range, and is zero exactly when it should be.
        @Test(.hegel(testCases: cases(1_000)))
        func scalingStaysInRange() throws {
            // The largest factor below the cutoff for 31 ns once scaled it 1 ms past
            // the maximum.
            let pastTheCutoff: Example = [
                "base": Duration.nanoseconds(31),
                "factor": (RetryGen.maximum / Duration.nanoseconds(31)).nextDown,
            ]
            try property(examples: [pastTheCutoff], reaching: ["just below the cutoff"]) { tc in
                let base = try #draw(RetryGen.duration, from: tc)
                let factor = try #draw(RetryGen.factor(for: base), from: tc)
                let scaled = base.scaledForRetry(by: factor)
                #expect(scaled >= .zero && scaled <= RetryGen.maximum)
                let clampedBase = Double(Exact.clamped(base))
                let exact = min(clampedBase * factor, Double(Exact.maximum))
                if factor > 0, clampedBase > 0 {
                    let error = abs(Double(scaled.attoseconds) - exact)
                    #expect(error <= max(exact * 1e-9, 1), "\(scaled) for an exact \(exact) as")
                } else {
                    #expect(scaled == .zero)
                }

                if scaled == RetryGen.maximum {
                    try tc.event("capped at the maximum")
                } else if scaled == .zero {
                    try tc.event("no wait")
                }
                let clamped = Exact.clampedDuration(base)
                if clamped > .zero, (RetryGen.maximum / clamped).nextDown == factor {
                    try tc.event("just below the cutoff")
                }
            }
        }

        /// A random wait lies between the waits of the range's two ends, and in
        /// range; with a seeded generator, two equal policies wait the same.
        ///
        /// The generator is seeded from a draw, so a failure replays. The
        /// policy without one uses the same arithmetic.
        @Test(.hegel(testCases: cases(1_000)))
        func jitterStaysBetweenItsBounds() throws {
            try property { tc in
                let delay = try #draw(RetryGen.duration, from: tc)
                let range = try #draw(RetryGen.jitterRange, from: tc)
                let seed = try #draw(Gen<UInt64>.integer(), from: tc)
                let waits = try #draw(.int(in: 1...16), from: tc)
                let low = delay.scaledForRetry(by: range.lowerBound)
                let high = delay.scaledForRetry(by: range.upperBound)
                let seeded = RetryPolicy.constantDelay(delay).jitter(
                    range,
                    using: SplitMix(state: seed)
                )
                let again = RetryPolicy.constantDelay(delay).jitter(
                    range,
                    using: SplitMix(state: seed)
                )
                let seededWaits = try (0..<waits).map { _ in try #require(seeded(.initial)) }
                let againWaits = try (0..<waits).map { _ in try #require(again(.initial)) }
                for wait in seededWaits {
                    #expect(wait >= low && wait <= high, "\(wait) is not in \(low)...\(high)")
                    #expect(wait >= .zero && wait <= RetryGen.maximum)
                }
                #expect(seededWaits == againWaits)
            }
        }

        /// Applying a policy to any status takes one step: the iteration grows
        /// by one (and stays at `Int.max`), and the wait the policy gives, in
        /// range, becomes the last wait and is added to the total.
        @Test(.hegel(testCases: cases(1_000)))
        func applyingTakesOneStep() throws {
            try property { tc in
                let expr = try #draw(RetryGen.policy, from: tc)
                let status = try #draw(
                    RetryGen.status,
                    from: tc
                )
                let requested = try #draw(.optional(RetryGen.duration), from: tc)
                let next = status.applying(expr.policy, requestedDelay: requested)
                let asked = RetryStatus(
                    iteration: status.iteration,
                    cumulativeDelay: status.cumulativeDelay,
                    previousDelay: status.previousDelay,
                    requestedDelay: requested
                )
                let delay = expr.model(asked).map(Exact.clampedDuration)
                #expect(next.iteration == (status.iteration == .max ? .max : status.iteration + 1))
                #expect(next.previousDelay == delay)
                #expect(next.requestedDelay == requested.map(Exact.clampedDuration))
                #expect(
                    next.cumulativeDelay
                        == (delay.map { Exact.adding(status.cumulativeDelay, $0) }
                            ?? status.cumulativeDelay)
                )

                if delay == nil {
                    try tc.event("the policy stopped")
                }
                if status.iteration == .max {
                    try tc.event("at the last iteration")
                }
            }
        }

        /// `RetryStatus` is public, so a status at the last iteration can be
        /// made by hand. Applying a policy to it must not crash.
        @Test
        func applyingAtTheLastIterationDoesNotCrash() async {
            await #expect(processExitsWith: .success) {
                _ = RetryStatus(iteration: .max).applying(.limitRetries(1))
            }
        }

        /// Every combination of the built-in policies returns what its model
        /// says, on any status.
        @Test(.hegel(testCases: cases(1_000)))
        func policiesMatchTheModel() throws {
            try property { tc in
                let expr = try #draw(RetryGen.policy, from: tc)
                let policy = expr.policy
                var stopped = false
                for _ in 0..<4 {
                    let status = try #draw(RetryGen.status, from: tc)
                    #expect(policy(status) == expr.model(status), "\(status)")
                    stopped = stopped || expr.model(status) == nil
                }

                if stopped {
                    try tc.event("the policy stopped")
                }
            }
        }

        /// A dry run takes one step per retry, adds up the waits without
        /// overflowing, and ends at the first step where the policy stops.
        @Test(.hegel(testCases: cases(1_000)))
        func dryRunWalksThePolicy() throws {
            try property { tc in
                let expr = try #draw(RetryGen.policy, from: tc)
                // Each retry is a step the model walks too, so the long branch
                // stops at 1,000.
                let limit = try #draw(
                    .oneOf(.int(in: 0...12), .int(in: 0...1_000)),
                    from: tc
                )
                let bounded = PolicyExpr.and(expr, .limitRetries(limit))
                let steps = Array(bounded.policy.dryRun().prefix(limit + 2))

                var expected: [RetryStatus] = []
                var status = RetryStatus.initial
                while true {
                    let delay = bounded.model(status).map(Exact.clampedDuration)
                    let next = RetryStatus(
                        iteration: status.iteration + 1,
                        cumulativeDelay: delay.map { Exact.adding(status.cumulativeDelay, $0) }
                            ?? status.cumulativeDelay,
                        previousDelay: delay,
                        requestedDelay: nil
                    )
                    expected.append(next)
                    guard delay != nil else { break }
                    status = next
                }
                #expect(steps == expected)
                #expect(steps.count <= limit + 1)

                try tc.event(
                    expected.count <= limit ? "the policy stopped first" : "the limit stopped it"
                )
                if expected.contains(where: { $0.cumulativeDelay == RetryGen.maximum }) {
                    try tc.event("the total wait saturated")
                }
            }
        }

        /// `withRetry` against a model of it: the statuses each attempt sees, the
        /// waits it sleeps, and the result it returns, for any policy and any
        /// mix of successes, failures, requested waits and cancellations.
        @Test(.hegel(testCases: cases(500)))
        func withRetryFollowsThePolicy() async throws {
            try await property(reaching: ["retried three times or more"]) { tc in
                // Most combined policies stop within a retry or two, so some
                // cases get one that never stops on its own.
                let expr = try #draw(
                    .oneOf(
                        RetryGen.policy,
                        RetryGen.duration.map { PolicyExpr.constantDelay($0) },
                        RetryGen.duration.map { PolicyExpr.exponentialBackoff($0) },
                        .just(.requestedDelay)
                    ),
                    from: tc
                )
                let limit = try #draw(
                    .oneOf(.int(in: 0...10), .int(in: 0...1_000)),
                    from: tc
                )
                let rates = try #draw(RetryGen.attemptRates, from: tc)
                let script = try #draw(.array(of: RetryGen.attempt(rates)), from: tc)
                // Attempts past the script succeed, so the retries end even
                // under a policy with no limit.
                let limited = try #draw(.bool(), from: tc)
                let bounded = limited ? PolicyExpr.and(expr, .limitRetries(limit)) : expr

                func attempt(_ index: Int) -> Attempt {
                    index < script.count ? script[index] : .success
                }
                func outcome(_ index: Int) -> Result<Int, AttemptFailure> {
                    let a = attempt(index)
                    return a.succeeds
                        ? .success(index)
                        : .failure(
                            AttemptFailure(
                                attempt: index,
                                retryable: a.retryable,
                                requested: a.requested
                            )
                        )
                }

                // The model.
                var expectedStatuses: [RetryStatus] = []
                var expectedSleeps: [Duration] = []
                var expectedResult: Result<Int, AttemptFailure>
                /// Why the model stopped, for the statistics.
                var ending: String
                var status = RetryStatus.initial
                var index = 0
                while true {
                    expectedStatuses.append(status)
                    let a = attempt(index)
                    expectedResult = outcome(index)
                    guard !a.succeeds, a.retryable else {
                        ending = a.succeeds ? "succeeded" : "a failure that is not retried"
                        break
                    }
                    let requested = a.requested.map(Exact.clampedDuration)
                    let asked = RetryStatus(
                        iteration: status.iteration,
                        cumulativeDelay: status.cumulativeDelay,
                        previousDelay: status.previousDelay,
                        requestedDelay: requested
                    )
                    guard let delay = bounded.model(asked).map(Exact.clampedDuration) else {
                        ending = "the policy stopped"
                        break
                    }
                    guard !a.cancels else {
                        ending = "cancelled"
                        break
                    }
                    if delay > .zero {
                        expectedSleeps.append(delay)
                    }
                    status = RetryStatus(
                        iteration: status.iteration + 1,
                        cumulativeDelay: Exact.adding(status.cumulativeDelay, delay),
                        previousDelay: delay,
                        requestedDelay: requested
                    )
                    index += 1
                }

                // The real thing.
                let clock = RecordingClock()
                let seen = Mutex<[RetryStatus]>([])
                let policy = bounded.policy
                let result = await Task {
                    await withRetry(
                        policy,
                        while: { $0.retryable },
                        requestedDelay: { $0.requested },
                        clock: clock
                    ) { status in
                        let index = seen.withLock { seen in
                            seen.append(status)
                            return seen.count - 1
                        }
                        if attempt(index).cancels {
                            withUnsafeCurrentTask { $0?.cancel() }
                        }
                        return outcome(index)
                    }
                }.value

                #expect(seen.withLock { $0 } == expectedStatuses)
                #expect(clock.sleeps == expectedSleeps)
                #expect(result == expectedResult)

                try tc.event(ending)
                try tc.event("attempts", value: Double(expectedStatuses.count))
                if !limited {
                    try tc.event("a policy with no added limit")
                }
                if expectedStatuses.count >= 4 {
                    try tc.event("retried three times or more")
                }
            }
        }
    }

#endif
