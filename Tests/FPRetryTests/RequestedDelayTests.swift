import Testing

@testable import FPRetry

/// A failure that can ask for a wait, like a response with a `Retry-After` header.
private enum ServerError: Error, Equatable {
    case busy(Int, retryAfter: Duration?)
    case fatal

    var retryAfter: Duration? {
        guard case .busy(_, let wait) = self else { return nil }
        return wait
    }
}

@Suite("Requested delay")
struct RequestedDelayTests {
    // MARK: - The policy

    @Test("requestedDelay waits the requested wait, or retries at once without one")
    func policyWaitsRequested() {
        #expect(RetryPolicy.requestedDelay(.initial) == .zero)
        #expect(
            RetryPolicy.requestedDelay(RetryStatus(requestedDelay: .seconds(7))) == .seconds(7)
        )
    }

    @Test("requestedDelay never stops")
    func policyNeverStops() {
        let delays = RetryPolicy.requestedDelay.dryRun().prefix(50).map(\.previousDelay)

        #expect(delays == Array(repeating: .zero, count: 50))
    }

    @Test("and with requestedDelay waits the longer of the two waits")
    func andWaitsLonger() {
        let policy = RetryPolicy.constantDelay(.seconds(2)).and(.requestedDelay)

        #expect(policy(RetryStatus(requestedDelay: .seconds(5))) == .seconds(5))
        #expect(policy(RetryStatus(requestedDelay: .seconds(1))) == .seconds(2))
        #expect(policy(RetryStatus()) == .seconds(2))
    }

    @Test("and with requestedDelay stops when the other policy stops")
    func andStops() {
        let policy = RetryPolicy.limitRetries(1).and(.requestedDelay)

        #expect(policy(RetryStatus(iteration: 1, requestedDelay: .seconds(5))) == nil)
    }

    @Test("jitter before requestedDelay never shortens the requested wait")
    func jitterBefore() {
        let policy = RetryPolicy.constantDelay(.seconds(1)).jitter().and(.requestedDelay)

        for _ in 0..<100 {
            #expect(policy(RetryStatus(requestedDelay: .seconds(10))) == .seconds(10))
        }
    }

    @Test("limitRetriesByDelay after requestedDelay stops on too long a requested wait")
    func limitRetriesByDelayAfter() {
        let policy = RetryPolicy.exponentialBackoff(.seconds(1))
            .and(.requestedDelay)
            .limitRetriesByDelay(.seconds(30))

        #expect(policy(RetryStatus(requestedDelay: .seconds(30))) == .seconds(30))
        #expect(policy(RetryStatus(requestedDelay: .seconds(31))) == nil)
    }

    @Test("capDelay after requestedDelay cuts the requested wait")
    func capDelayAfter() {
        let policy = RetryPolicy.requestedDelay.capDelay(.seconds(5))

        #expect(policy(RetryStatus(requestedDelay: .seconds(60))) == .seconds(5))
    }

    // MARK: - The status

    @Test("a status keeps a requested wait between zero and the maximum")
    func statusClamps() {
        #expect(RetryStatus(requestedDelay: .seconds(-3)).requestedDelay == .zero)
        #expect(
            RetryStatus(requestedDelay: .seconds(Int64.max)).requestedDelay
                == RetryPolicy.maximumDelay
        )
    }

    @Test("applying shows the policy the requested wait and keeps it in the next status")
    func applyingPassesRequested() {
        let next = RetryStatus.initial.applying(.requestedDelay, requestedDelay: .seconds(3))

        #expect(
            next
                == RetryStatus(
                    iteration: 1,
                    cumulativeDelay: .seconds(3),
                    previousDelay: .seconds(3),
                    requestedDelay: .seconds(3)
                )
        )
    }

    @Test("applying keeps the requested wait when the policy stops")
    func applyingStops() {
        let next = RetryStatus.initial.applying(.limitRetries(0), requestedDelay: .seconds(3))

        #expect(
            next
                == RetryStatus(
                    iteration: 1,
                    cumulativeDelay: .zero,
                    previousDelay: nil,
                    requestedDelay: .seconds(3)
                )
        )
    }

    @Test("applying clamps a negative requested wait to zero")
    func applyingClamps() {
        let next = RetryStatus.initial.applying(.requestedDelay, requestedDelay: .seconds(-1))

        #expect(next.previousDelay == .zero)
        #expect(next.requestedDelay == .zero)
    }

    @Test("applying without a requested wait drops the one before")
    func applyingReplaces() {
        let next = RetryStatus(requestedDelay: .seconds(9)).applying(.requestedDelay)

        #expect(next.previousDelay == .zero)
        #expect(next.requestedDelay == nil)
    }

    // MARK: - withRetry

    @Test("withRetry waits as long as each failure asks, and the policy's wait otherwise")
    func withRetryWaitsRequested() async {
        let clock = TestClock()
        let attempts = Attempts()
        let requests: [Duration?] = [.seconds(5), nil, .seconds(1)]
        let policy = RetryPolicy.constantDelay(.seconds(2))
            .and(.limitRetries(5))
            .and(.requestedDelay)

        let result: Result<Int, ServerError> = await withRetry(
            policy,
            requestedDelay: \.retryAfter,
            clock: clock
        ) { status in
            let attempt = attempts.record(status)
            guard attempt <= requests.count else { return .success(attempt) }
            return .failure(.busy(attempt, retryAfter: requests[attempt - 1]))
        }

        #expect(result == .success(4))
        #expect(clock.sleeps == [.seconds(5), .seconds(2), .seconds(2)])
        #expect(attempts.all.map(\.requestedDelay) == [nil] + requests)
    }

    @Test("withRetry gives the requested wait to a policy that does not use it")
    func withRetryPolicyIgnores() async {
        let clock = TestClock()
        let attempts = Attempts()
        let policy = RetryPolicy.constantDelay(.seconds(1)).and(.limitRetries(2))

        let _: Result<Int, ServerError> = await withRetry(
            policy,
            requestedDelay: \.retryAfter,
            clock: clock
        ) { status in
            .failure(.busy(attempts.record(status), retryAfter: .seconds(10)))
        }

        #expect(clock.sleeps == [.seconds(1), .seconds(1)])
        #expect(attempts.all.map(\.requestedDelay) == [nil, .seconds(10), .seconds(10)])
    }

    @Test("withRetry stops when a failure asks for too long a wait")
    func withRetryStopsOnLongRequest() async {
        let clock = TestClock()
        let attempts = Attempts()
        let policy = RetryPolicy.limitRetries(5)
            .and(.requestedDelay)
            .limitRetriesByDelay(.seconds(30))

        let result: Result<Int, ServerError> = await withRetry(
            policy,
            requestedDelay: \.retryAfter,
            clock: clock
        ) {
            let attempt = attempts.record()
            return .failure(.busy(attempt, retryAfter: .seconds(attempt == 1 ? 10 : 60)))
        }

        #expect(result == .failure(.busy(2, retryAfter: .seconds(60))))
        #expect(clock.sleeps == [.seconds(10)])
    }

    @Test("withRetry counts requested waits in the total wait")
    func withRetryCumulative() async {
        let clock = TestClock()
        let attempts = Attempts()
        let policy = RetryPolicy.requestedDelay.limitRetriesByCumulativeDelay(.seconds(10))

        let _: Result<Int, ServerError> = await withRetry(
            policy,
            requestedDelay: \.retryAfter,
            clock: clock
        ) {
            .failure(.busy(attempts.record(), retryAfter: .seconds(4)))
        }

        #expect(clock.sleeps == [.seconds(4), .seconds(4)])
        #expect(attempts.count == 3)
    }

    @Test("withRetry retries at once when a failure asks for a negative wait")
    func withRetryNegativeRequest() async {
        let clock = TestClock()
        let attempts = Attempts()

        let _: Result<Int, ServerError> = await withRetry(
            RetryPolicy.limitRetries(2).and(.requestedDelay),
            requestedDelay: \.retryAfter,
            clock: clock
        ) {
            .failure(.busy(attempts.record(), retryAfter: .seconds(-5)))
        }

        #expect(clock.sleeps.isEmpty)
        #expect(attempts.count == 3)
    }

    @Test("withRetry asks only failures it retries for a wait")
    func withRetryAsksRetriedFailures() async {
        let clock = TestClock()
        let attempts = Attempts()
        let asked = Attempts()

        let result: Result<Int, ServerError> = await withRetry(
            RetryPolicy.limitRetries(5).and(.requestedDelay),
            while: { $0 != .fatal },
            requestedDelay: { error in
                asked.record()
                return error.retryAfter
            },
            clock: clock
        ) {
            attempts.record() < 2 ? .failure(.busy(1, retryAfter: .seconds(1))) : .failure(.fatal)
        }

        #expect(result == .failure(.fatal))
        #expect(asked.count == 1)
        #expect(clock.sleeps == [.seconds(1)])
    }

    @Test("withRetry without requestedDelay asks for no wait")
    func withRetryDefault() async {
        let clock = TestClock()
        let attempts = Attempts()

        let _: Result<Int, ServerError> = await withRetry(
            RetryPolicy.limitRetries(2).and(.requestedDelay),
            clock: clock
        ) { status in
            .failure(.busy(attempts.record(status), retryAfter: .seconds(10)))
        }

        #expect(clock.sleeps.isEmpty)
        #expect(attempts.all.map(\.requestedDelay) == [nil, nil, nil])
    }
}
