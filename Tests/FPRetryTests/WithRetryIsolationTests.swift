import Testing

@testable import FPRetry

/// Non-Sendable state owned by the main actor. Capturing it in the action
/// only compiles if `withRetry` is `nonisolated(nonsending)` and keeps the
/// action on the caller's actor.
private final class Log {
    var entries: [Int] = []

    func record(_ iteration: Int) {
        MainActor.assertIsolated()
        entries.append(iteration)
    }
}

@MainActor
@Suite("withRetry runs on the caller's actor")
struct WithRetryIsolationTests {
    @Test("the action runs on the caller's actor across retries")
    func actionOnCallerActor() async {
        let log = Log()
        let policy = RetryPolicy.constantDelay(.milliseconds(1)).and(.limitRetries(2))

        let result: Result<Int, TestError> = await withRetry(policy, clock: TestClock()) {
            status in
            log.record(status.iteration)
            return .failure(.fatal)
        }

        #expect(result == .failure(.fatal))
        #expect(log.entries == [0, 1, 2])
    }

    @Test("the action runs on the caller's actor after a real wait")
    func actionOnCallerActorAfterSleep() async {
        let log = Log()
        let policy = RetryPolicy.constantDelay(.milliseconds(1)).and(.limitRetries(1))

        let _: Result<Int, TestError> = await withRetry(policy) { status in
            log.record(status.iteration)
            return .failure(.fatal)
        }

        #expect(log.entries == [0, 1])
    }
}
