import Testing

@testable import FPRetry

// The custom policies from the README and the DocC page, so the examples
// stay true to what the library does.

extension RetryPolicy {
    /// Waits `step` before the first retry, `2 × step` before the second, and so on.
    static func linearBackoff(_ step: Duration) -> RetryPolicy {
        RetryPolicy { status in step * (status.iteration + 1) }
    }

    /// Waits at least `minimum` before every retry.
    func minimumDelay(_ minimum: Duration) -> RetryPolicy {
        RetryPolicy { status in
            self(status).map { delay in max(delay, minimum) }
        }
    }
}

@Suite("Custom policies")
struct CustomPolicyTests {
    let quickThenSlow = RetryPolicy { status in
        status.iteration == 0 ? .zero : .seconds(1)
    }

    let apiPolicy = RetryPolicy.linearBackoff(.milliseconds(500))
        .and(.limitRetries(4))
        .capDelay(.milliseconds(1500))

    @Test("an inline policy combines with a built-in limit")
    func inlinePolicy() {
        let delays = quickThenSlow.and(.limitRetries(3)).dryRun().map(\.previousDelay)

        #expect(delays == [.zero, .seconds(1), .seconds(1), nil])
    }

    @Test("a static policy in an extension chains with the built-in modifiers")
    func staticPolicy() {
        let delays = apiPolicy.dryRun().map(\.previousDelay)

        #expect(delays == [500, 1000, 1500, 1500].map { .milliseconds($0) } + [nil])
    }

    @Test("a custom modifier reshapes delays and keeps the wrapped policy's limit")
    func customModifier() {
        let delays = RetryPolicy.limitRetries(3).minimumDelay(.milliseconds(100))
            .dryRun().map(\.previousDelay)

        #expect(delays == [.milliseconds(100), .milliseconds(100), .milliseconds(100), nil])
    }

    @Test("a custom modifier chains with the built-in ones")
    func customModifierChains() {
        let delays = RetryPolicy.exponentialBackoff(.milliseconds(10))
            .minimumDelay(.milliseconds(50))
            .capDelay(.milliseconds(100))
            .and(.limitRetries(5))
            .dryRun().map(\.previousDelay)

        #expect(delays == [50, 50, 50, 80, 100].map { .milliseconds($0) } + [nil])
    }

    @Test("withRetry waits the delays of a custom policy")
    func withRetryCustomPolicy() async {
        let clock = TestClock()

        let _: Result<Int, TestError> = await withRetry(apiPolicy, clock: clock) {
            .failure(.fatal)
        }

        #expect(clock.sleeps == [500, 1000, 1500, 1500].map { .milliseconds($0) })
    }

    @Test("withRetry retries a custom policy's zero delay without sleeping")
    func withRetryInlinePolicy() async {
        let clock = TestClock()
        let attempts = Attempts()

        let result: Result<Int, TestError> = await withRetry(
            quickThenSlow.and(.limitRetries(3)),
            clock: clock
        ) {
            .failure(.transient(attempts.record()))
        }

        #expect(result == .failure(.transient(4)))
        #expect(clock.sleeps == [.seconds(1), .seconds(1)])
    }
}
