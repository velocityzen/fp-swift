import Testing

@testable import FPRetry

@Suite("RetryPolicy")
struct RetryPolicyTests {
    /// The delays a policy waits, ending with `nil` where it gives up.
    func delays(_ policy: RetryPolicy, prefix: Int = 100) -> [Duration?] {
        policy.dryRun().prefix(prefix).map(\.previousDelay)
    }

    // MARK: - Basic policies

    @Test("limitRetries retries at once, the given number of times")
    func limitRetries() {
        #expect(delays(.limitRetries(3)) == [.zero, .zero, .zero, nil])
    }

    @Test("limitRetries(0) never retries")
    func limitRetriesZero() {
        #expect(delays(.limitRetries(0)) == [nil])
    }

    @Test("constantDelay waits the same delay forever")
    func constantDelay() {
        let delays = delays(.constantDelay(.seconds(1)), prefix: 50)
        #expect(delays == Array(repeating: .seconds(1), count: 50))
    }

    @Test("exponentialBackoff doubles the delay before every retry")
    func exponentialBackoff() {
        let delays = delays(.exponentialBackoff(.milliseconds(100)), prefix: 5)
        #expect(delays == [100, 200, 400, 800, 1600].map { .milliseconds($0) })
    }

    @Test("exponentialBackoff saturates at maximumDelay instead of overflowing")
    func exponentialBackoffSaturates() {
        let policy = RetryPolicy.exponentialBackoff(.seconds(1))

        #expect(policy(RetryStatus(iteration: 62)) == RetryPolicy.maximumDelay)
        #expect(policy(RetryStatus(iteration: 1_000)) == RetryPolicy.maximumDelay)
        #expect(policy(RetryStatus(iteration: .max)) == RetryPolicy.maximumDelay)
        #expect(
            RetryPolicy.exponentialBackoff(RetryPolicy.maximumDelay)(RetryStatus(iteration: 1))
                == RetryPolicy.maximumDelay
        )
    }

    @Test("exponentialBackoff keeps doubling a small delay past 62 retries")
    func exponentialBackoffSmallBase() {
        let policy = RetryPolicy.exponentialBackoff(.milliseconds(1))
        #expect(policy(RetryStatus(iteration: 62)) == .milliseconds(1) * (1 << 62))
        #expect(policy(RetryStatus(iteration: 63)) == RetryPolicy.maximumDelay)

        let tiny = RetryPolicy.exponentialBackoff(Duration(attoseconds: 1))
        #expect(tiny(RetryStatus(iteration: 62)) == Duration(attoseconds: 1 << 62))
        #expect(tiny(RetryStatus(iteration: 112)) == Duration(attoseconds: Int128(1) << 112))
        #expect(tiny(RetryStatus(iteration: 113)) == RetryPolicy.maximumDelay)
    }

    @Test("exponentialBackoff of a delay that is not positive retries at once")
    func exponentialBackoffNonPositive() {
        #expect(delays(.exponentialBackoff(.zero), prefix: 3) == [.zero, .zero, .zero])
        #expect(delays(.exponentialBackoff(.seconds(-1)), prefix: 3) == [.zero, .zero, .zero])
    }

    // MARK: - and

    @Test("and waits the longer delay and gives up when either policy does")
    func and() {
        let policy = RetryPolicy.exponentialBackoff(.seconds(1))
            .and(.constantDelay(.seconds(3)))
            .and(.limitRetries(4))

        #expect(delays(policy) == [3, 3, 4, 8].map { .seconds($0) } + [nil])
    }

    @Test("constantDelay(.zero) is the identity of and")
    func andIdentity() {
        let policy = RetryPolicy.exponentialBackoff(.seconds(1)).and(.limitRetries(5))
        let identity = RetryPolicy.constantDelay(.zero)

        #expect(delays(identity.and(policy)) == delays(policy))
        #expect(delays(policy.and(identity)) == delays(policy))
    }

    @Test("and is associative")
    func andAssociative() {
        let a = RetryPolicy.exponentialBackoff(.milliseconds(100))
        let b = RetryPolicy.constantDelay(.milliseconds(500))
        let c = RetryPolicy.limitRetries(6)

        #expect(delays(a.and(b).and(c)) == delays(a.and(b.and(c))))
    }

    // MARK: - Modifiers

    @Test("capDelay caps every delay without changing how often it retries")
    func capDelay() {
        let policy = RetryPolicy.exponentialBackoff(.seconds(1))
            .capDelay(.seconds(5))
            .and(.limitRetries(5))

        #expect(delays(policy) == [1, 2, 4, 5, 5].map { .seconds($0) } + [nil])
    }

    @Test("limitRetriesByDelay gives up once a delay would be too long")
    func limitRetriesByDelay() {
        let policy = RetryPolicy.exponentialBackoff(.seconds(1))
            .limitRetriesByDelay(.seconds(5))

        #expect(delays(policy) == [1, 2, 4].map { .seconds($0) } + [nil])
    }

    @Test("limitRetriesByCumulativeDelay gives up before the total wait is too long")
    func limitRetriesByCumulativeDelay() {
        let policy = RetryPolicy.constantDelay(.seconds(2))
            .limitRetriesByCumulativeDelay(.seconds(5))

        #expect(delays(policy) == [.seconds(2), .seconds(2), nil])
    }

    @Test("limitRetriesByCumulativeDelay allows a total wait of exactly the maximum")
    func limitRetriesByCumulativeDelayInclusive() {
        let policy = RetryPolicy.constantDelay(.seconds(2))
            .limitRetriesByCumulativeDelay(.seconds(4))

        #expect(delays(policy) == [.seconds(2), .seconds(2), nil])
    }

    // MARK: - Statuses

    @Test("dryRun lists every status, ending with the one that gives up")
    func dryRun() {
        let policy = RetryPolicy.constantDelay(.seconds(1)).and(.limitRetries(2))

        #expect(
            Array(policy.dryRun()) == [
                RetryStatus(
                    iteration: 1,
                    cumulativeDelay: .seconds(1),
                    previousDelay: .seconds(1)
                ),
                RetryStatus(
                    iteration: 2,
                    cumulativeDelay: .seconds(2),
                    previousDelay: .seconds(1)
                ),
                RetryStatus(iteration: 3, cumulativeDelay: .seconds(2), previousDelay: nil),
            ]
        )
    }

    @Test("dryRun is lazy, so a policy that never gives up can be sampled")
    func dryRunLazy() {
        let statuses = Array(RetryPolicy.constantDelay(.seconds(1)).dryRun().prefix(3))

        #expect(statuses.map(\.iteration) == [1, 2, 3])
        #expect(statuses.last?.cumulativeDelay == .seconds(3))
    }

    @Test("applying clamps a negative delay to zero")
    func applyingClampsNegative() {
        let status = RetryStatus.initial.applying(.constantDelay(.seconds(-5)))

        #expect(status == RetryStatus(iteration: 1, cumulativeDelay: .zero, previousDelay: .zero))
    }

    @Test("applying saturates the delay and the cumulative delay at maximumDelay")
    func applyingSaturates() {
        let tooLong = RetryPolicy.constantDelay(.seconds(Int64.max))
        let statuses = Array(tooLong.dryRun().prefix(3))

        #expect(statuses.allSatisfy { $0.previousDelay == RetryPolicy.maximumDelay })
        #expect(statuses.allSatisfy { $0.cumulativeDelay == RetryPolicy.maximumDelay })
    }

    @Test("a custom policy sees the status it is asked with")
    func customPolicy() {
        let firstMinute = RetryPolicy { status in
            status.cumulativeDelay < .seconds(60) ? .seconds(25) : nil
        }

        #expect(delays(firstMinute) == [.seconds(25), .seconds(25), .seconds(25), nil])
    }
}
