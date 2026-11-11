// Examples from "Retrying" in README.md. The DocC article is made from README.md.
// Keep the code here the same. The custom policies from "Write your own policy"
// are in CustomPolicyTests.swift.

import FPRetry
import Testing

private enum APIError: Error, Equatable {
    case timeout
    case rateLimited(retryAfter: Duration?)
    case server(status: Int)
    case notFound

    /// True when the request can succeed if we try again.
    var isTransient: Bool {
        switch self {
            case .timeout, .rateLimited: true
            case .server(let status): status >= 500
            case .notFound: false
        }
    }
}

extension APIError {
    /// The wait from the Retry-After header, if the server sent one.
    var retryAfter: Duration? {
        guard case .rateLimited(let wait) = self else { return nil }
        return wait
    }
}

private struct User: Equatable, Sendable {
    let id: Int
}

private func loadUser(id: Int) async -> Result<User, APIError> {
    .success(User(id: id))
}

// Wait up to 200ms, 400ms, 800ms and so on, but never more
// than 2s. Retry at most 5 times. Each wait is random (jitter).
private let apiPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
    .and(.limitRetries(5))
    .capDelay(.seconds(2))
    .jitter()

@Suite("README retrying")
struct ReadmeRetryTests {
    @Test
    func quickStart() async {
        let user = await withRetry(apiPolicy) { await loadUser(id: 1) }
        // Result<User, APIError>

        #expect(user == .success(User(id: 1)))
        #expect(Array(apiPolicy.dryRun()).count == 6)
    }

    @Test
    func retryOnlySomeFailures() async {
        let user = await withRetry(apiPolicy, while: \.isTransient) {
            await loadUser(id: 1)
        }

        #expect(user == .success(User(id: 1)))
        #expect(APIError.server(status: 503).isTransient)
        #expect(!APIError.notFound.isTransient)
    }

    @Test
    func waitAsLongAsTheFailureAsks() async {
        let serverPolicy = apiPolicy.and(.requestedDelay)
            .limitRetriesByDelay(.seconds(30))

        let user = await withRetry(
            serverPolicy,
            while: \.isTransient,
            requestedDelay: \.retryAfter
        ) {
            await loadUser(id: 1)
        }

        #expect(user == .success(User(id: 1)))
        #expect(APIError.rateLimited(retryAfter: .seconds(5)).retryAfter == .seconds(5))
        #expect(APIError.timeout.retryAfter == nil)
        // The server's wait wins over apiPolicy's, which is at most 2s.
        #expect(serverPolicy(RetryStatus(requestedDelay: .seconds(10))) == .seconds(10))
        // Past 30s, the policy gives up.
        #expect(serverPolicy(RetryStatus(requestedDelay: .seconds(31))) == nil)
    }

    @Test
    func useTheRetryStatus() async {
        let user = await withRetry(apiPolicy) { status in
            print("attempt", status.iteration + 1)
            return await loadUser(id: 1)
        }

        #expect(user == .success(User(id: 1)))
    }

    @Test
    func jitter() {
        let testPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
            .and(.limitRetries(5))
            .jitter(using: SeededGenerator(seed: 42))

        let again = RetryPolicy.exponentialBackoff(.milliseconds(200))
            .and(.limitRetries(5))
            .jitter(using: SeededGenerator(seed: 42))

        #expect(testPolicy.dryRun().map(\.previousDelay) == again.dryRun().map(\.previousDelay))
    }

    @Test
    func writeYourOwnPolicy() async {
        // Retry the first time at once. Then wait 1 second each time.
        let quickThenSlow = RetryPolicy { status in
            status.iteration == 0 ? .zero : .seconds(1)
        }

        let user = await withRetry(quickThenSlow.and(.limitRetries(3))) {
            await loadUser(id: 1)
        }
        // Waits: 0s, 1s, 1s, then stops

        let linear = RetryPolicy.linearBackoff(.milliseconds(500))
            .and(.limitRetries(4))
            .capDelay(.milliseconds(1500))
        // Waits: 0.5s, 1s, 1.5s, 1.5s, then stops

        #expect(user == .success(User(id: 1)))
        #expect(
            quickThenSlow.and(.limitRetries(3)).dryRun().map(\.previousDelay)
                == [.zero, .seconds(1), .seconds(1), nil]
        )
        #expect(
            linear.dryRun().map(\.previousDelay)
                == [500, 1000, 1500, 1500].map { .milliseconds($0) } + [nil]
        )
    }

    @Test
    func checkAPolicy() {
        let waits = RetryPolicy.exponentialBackoff(.seconds(1))
            .and(.limitRetries(3))
            .dryRun()
            .map(\.previousDelay)
        // [1s, 2s, 4s, nil]

        #expect(waits == [.seconds(1), .seconds(2), .seconds(4), nil])
    }
}
