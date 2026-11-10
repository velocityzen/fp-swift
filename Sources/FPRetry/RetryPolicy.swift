/// Decides after each failure whether to retry, and how long to wait first.
///
/// A policy is a function. It takes a ``RetryStatus`` and returns the wait before the next
/// retry, or `nil` to stop. Combine the built-in policies, or write your own with ``init(_:)``.
///
/// ```swift
/// // Random waits up to 200ms, 400ms, 800ms, 1.6s, 2s, then stops.
/// let apiPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
///     .and(.limitRetries(5))
///     .capDelay(.seconds(2))
///     .jitter()
/// ```
public struct RetryPolicy: Sendable {
    @usableFromInline
    let delay: @Sendable (RetryStatus) -> Duration?

    /// Creates a policy from a function that returns the wait before the next retry, or `nil`
    /// to stop.
    ///
    /// ```swift
    /// // Retry every second, but only in the first minute.
    /// let firstMinute = RetryPolicy { status in
    ///     status.cumulativeDelay < .seconds(60) ? .seconds(1) : nil
    /// }
    /// ```
    @inlinable
    public init(_ delay: @escaping @Sendable (RetryStatus) -> Duration?) {
        self.delay = delay
    }

    /// Returns the wait before the next retry, or `nil` to stop.
    @inlinable
    public func callAsFunction(_ status: RetryStatus) -> Duration? {
        delay(status)
    }

    /// The longest wait: `Int64.max` milliseconds, about 292 million years.
    ///
    /// Longer waits become this value, so a growing wait never overflows.
    @inlinable
    public static var maximumDelay: Duration { .milliseconds(Int64.max) }
}

// MARK: - Basic policies

public extension RetryPolicy {
    /// Retries at once, at most `count` times. That is at most `count + 1` attempts.
    @inlinable
    static func limitRetries(_ count: Int) -> RetryPolicy {
        RetryPolicy { status in
            status.iteration < count ? .zero : nil
        }
    }

    /// Waits `delay` before each retry. Never stops.
    @inlinable
    static func constantDelay(_ delay: Duration) -> RetryPolicy {
        RetryPolicy { _ in delay }
    }

    /// Waits `base` before the first retry, then doubles the wait each time. Never stops.
    ///
    /// Use ``capDelay(_:)`` to set a maximum wait.
    @inlinable
    static func exponentialBackoff(_ base: Duration) -> RetryPolicy {
        RetryPolicy { status in
            base.doubled(times: status.iteration)
        }
    }
}

// MARK: - Modifiers

public extension RetryPolicy {
    /// Retries only while both policies retry, and waits the longer of the two waits.
    ///
    /// ```swift
    /// RetryPolicy.constantDelay(.seconds(1)).and(.limitRetries(3))
    /// // Waits: 1s, 1s, 1s, then stops
    /// ```
    @inlinable
    func and(_ other: RetryPolicy) -> RetryPolicy {
        RetryPolicy { status in
            guard let first = self(status), let second = other(status) else {
                return nil
            }
            return max(first, second)
        }
    }

    /// Never waits longer than `maximum`. Retries as often as before.
    ///
    /// ```swift
    /// RetryPolicy.exponentialBackoff(.seconds(1)).capDelay(.seconds(5))
    /// // Waits: 1s, 2s, 4s, 5s, 5s, …
    /// ```
    @inlinable
    func capDelay(_ maximum: Duration) -> RetryPolicy {
        RetryPolicy { status in
            self(status).map { min($0, maximum) }
        }
    }

    /// Stops when the next wait would be longer than `maximum`.
    ///
    /// ```swift
    /// RetryPolicy.exponentialBackoff(.seconds(1)).limitRetriesByDelay(.seconds(5))
    /// // Waits: 1s, 2s, 4s, then stops (the next wait would be 8s)
    /// ```
    @inlinable
    func limitRetriesByDelay(_ maximum: Duration) -> RetryPolicy {
        RetryPolicy { status in
            self(status).flatMap { $0 <= maximum ? $0 : nil }
        }
    }

    /// Stops when the total wait would be longer than `maximum`.
    @inlinable
    func limitRetriesByCumulativeDelay(_ maximum: Duration) -> RetryPolicy {
        RetryPolicy { status in
            self(status).flatMap { delay in
                status.cumulativeDelay.addingRetryDelay(delay.clampedToRetryDelay) <= maximum
                    ? delay : nil
            }
        }
    }
}

// MARK: - Dry run

public extension RetryPolicy {
    /// Returns the steps of this policy when every attempt fails, without waiting.
    ///
    /// The last step is where the policy stops. If the policy never stops, the sequence never
    /// ends, so use `prefix`.
    ///
    /// ```swift
    /// let waits = RetryPolicy.exponentialBackoff(.seconds(1))
    ///     .and(.limitRetries(3))
    ///     .dryRun()
    ///     .map(\.previousDelay)
    /// // [1s, 2s, 4s, nil]
    /// ```
    @inlinable
    func dryRun() -> some Sequence<RetryStatus> {
        sequence(state: Optional(RetryStatus.initial)) { state in
            guard let current = state else { return nil }
            let next = current.applying(self)
            state = next.previousDelay == nil ? nil : next
            return next
        }
    }
}
