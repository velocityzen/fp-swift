import Synchronization
import Testing

@testable import FPRetry

enum TestError: Error, Equatable {
    case transient(Int)
    case fatal
}

/// Counts attempts and records the status each one was given.
final class Attempts: Sendable {
    private let statuses = Mutex<[RetryStatus]>([])

    var count: Int { statuses.withLock { $0.count } }
    var all: [RetryStatus] { statuses.withLock { $0 } }

    /// Records an attempt and returns its number, counting from 1.
    @discardableResult
    func record(_ status: RetryStatus = .initial) -> Int {
        statuses.withLock { statuses in
            statuses.append(status)
            return statuses.count
        }
    }
}

@Suite("withRetry")
struct WithRetryTests {
    let threeTimes = RetryPolicy.constantDelay(.seconds(1)).and(.limitRetries(3))

    @Test("a first success is returned without retrying")
    func successFirstTime() async {
        let clock = TestClock()
        let attempts = Attempts()

        let result: Result<Int, TestError> = await withRetry(threeTimes, clock: clock) {
            attempts.record()
            return .success(42)
        }

        #expect(result == .success(42))
        #expect(attempts.count == 1)
        #expect(clock.sleeps.isEmpty)
    }

    @Test("retries after each failure until the action succeeds")
    func retriesUntilSuccess() async {
        let clock = TestClock()
        let attempts = Attempts()

        let result: Result<Int, TestError> = await withRetry(threeTimes, clock: clock) {
            let attempt = attempts.record()
            return attempt < 3 ? .failure(.transient(attempt)) : .success(attempt)
        }

        #expect(result == .success(3))
        #expect(clock.sleeps == [.seconds(1), .seconds(1)])
    }

    @Test("returns the latest failure once the policy gives up")
    func givesUp() async {
        let clock = TestClock()
        let attempts = Attempts()

        let result: Result<Int, TestError> = await withRetry(threeTimes, clock: clock) {
            .failure(.transient(attempts.record()))
        }

        #expect(result == .failure(.transient(4)))
        #expect(attempts.count == 4)
        #expect(clock.sleeps == [.seconds(1), .seconds(1), .seconds(1)])
    }

    @Test("does not retry a failure the predicate rejects")
    func predicateStops() async {
        let clock = TestClock()
        let attempts = Attempts()

        let result: Result<Int, TestError> = await withRetry(
            threeTimes,
            while: { $0 != .fatal },
            clock: clock
        ) {
            attempts.record() < 2 ? .failure(.transient(1)) : .failure(.fatal)
        }

        #expect(result == .failure(.fatal))
        #expect(attempts.count == 2)
        #expect(clock.sleeps == [.seconds(1)])
    }

    @Test("passes each attempt its status")
    func passesStatus() async {
        let clock = TestClock()
        let attempts = Attempts()
        let policy = RetryPolicy.exponentialBackoff(.milliseconds(100)).and(.limitRetries(3))

        let _: Result<Int, TestError> = await withRetry(policy, clock: clock) { status in
            .failure(.transient(attempts.record(status)))
        }

        #expect(
            attempts.all == [
                RetryStatus(iteration: 0, cumulativeDelay: .zero, previousDelay: nil),
                RetryStatus(
                    iteration: 1,
                    cumulativeDelay: .milliseconds(100),
                    previousDelay: .milliseconds(100)
                ),
                RetryStatus(
                    iteration: 2,
                    cumulativeDelay: .milliseconds(300),
                    previousDelay: .milliseconds(200)
                ),
                RetryStatus(
                    iteration: 3,
                    cumulativeDelay: .milliseconds(700),
                    previousDelay: .milliseconds(400)
                ),
            ]
        )
        #expect(clock.sleeps == [100, 200, 400].map { .milliseconds($0) })
    }

    @Test("waits the same delays as the policy's dry run")
    func matchesDryRun() async {
        let clock = TestClock()
        let policy = RetryPolicy.exponentialBackoff(.seconds(1))
            .capDelay(.seconds(10))
            .limitRetriesByCumulativeDelay(.seconds(60))

        let _: Result<Int, TestError> = await withRetry(policy, clock: clock) {
            .failure(.fatal)
        }

        #expect(clock.sleeps == policy.dryRun().compactMap(\.previousDelay))
    }

    @Test("an immediate retry does not sleep")
    func immediateRetryDoesNotSleep() async {
        let clock = TestClock()
        let attempts = Attempts()

        let result: Result<Int, TestError> = await withRetry(.limitRetries(5), clock: clock) {
            .failure(.transient(attempts.record()))
        }

        #expect(result == .failure(.transient(6)))
        #expect(clock.sleeps.isEmpty)
    }

    @Test("a policy that never retries runs the action once")
    func neverRetries() async {
        let attempts = Attempts()

        let result: Result<Int, TestError> = await withRetry(.limitRetries(0)) {
            .failure(.transient(attempts.record()))
        }

        #expect(result == .failure(.transient(1)))
    }

    @Test("retries on the continuous clock by default")
    func defaultClock() async {
        let attempts = Attempts()
        let policy = RetryPolicy.constantDelay(.milliseconds(1)).and(.limitRetries(2))

        let result: Result<Int, TestError> = await withRetry(policy) {
            let attempt = attempts.record()
            return attempt < 3 ? .failure(.transient(attempt)) : .success(attempt)
        }

        #expect(result == .success(3))
    }

    // MARK: - Cancellation

    @Test("stops at a cancelled wait and returns the latest failure")
    func cancelledWait() async {
        let attempts = Attempts()

        // The action cancels its own task, so the wait after it is cancelled.
        let result: Result<Int, TestError> = await Task {
            await withRetry(.constantDelay(.seconds(1)), clock: TestClock()) {
                withUnsafeCurrentTask { $0?.cancel() }
                return .failure(.transient(attempts.record()))
            }
        }.value

        #expect(result == .failure(.transient(1)))
        #expect(attempts.count == 1)
    }

    @Test("stops before an immediate retry in a cancelled task")
    func cancelledImmediateRetry() async {
        let attempts = Attempts()

        let result: Result<Int, TestError> = await Task {
            await withRetry(.limitRetries(5)) {
                withUnsafeCurrentTask { $0?.cancel() }
                return .failure(.transient(attempts.record()))
            }
        }.value

        #expect(result == .failure(.transient(1)))
        #expect(attempts.count == 1)
    }

    @Test("stops a long wait on the continuous clock when cancelled", .timeLimit(.minutes(10)))
    func cancelledContinuousClock() async {
        let attempts = Attempts()

        let result: Result<Int, TestError> = await Task {
            await withRetry(.constantDelay(.seconds(3_600))) {
                withUnsafeCurrentTask { $0?.cancel() }
                return .failure(.transient(attempts.record()))
            }
        }.value

        #expect(result == .failure(.transient(1)))
    }
}
