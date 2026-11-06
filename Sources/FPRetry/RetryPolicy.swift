/// Decides after each failure whether to retry, and how long to wait first.
///
/// A policy is a function. It takes a ``RetryStatus`` and returns the wait
/// before the next retry, or `nil` to stop. Create a policy once and use it
/// in many places:
///
/// ```swift
/// // Wait up to 200ms, 400ms, 800ms, and so on, but never more than 2s.
/// // Retry at most 5 times. Each wait is random (jitter).
/// let apiPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
///     .and(.limitRetries(5))
///     .capDelay(.seconds(2))
///     .jitter()
///
/// let user = await withRetry(apiPolicy) { await fetchUser(id) }
/// ```
///
/// **Basic policies**
/// - ``limitRetries(_:)``: retry at once, at most `n` times.
/// - ``constantDelay(_:)``: wait the same time before each retry. Never stops.
/// - ``exponentialBackoff(_:)``: double the wait before each retry. Never stops.
///
/// **Modifiers**
/// - ``and(_:)``: retry while both policies retry. Wait the longer time.
/// - ``capDelay(_:)``: never wait longer than a maximum.
/// - ``limitRetriesByDelay(_:)``: stop when the next wait is too long.
/// - ``limitRetriesByCumulativeDelay(_:)``: stop when the total wait is too
///   long.
/// - ``jitter(_:)``: make each wait random, so many clients do not retry at
///   the same time. Put it last.
///
/// **Your own policies**
///
/// Use ``init(_:)`` with any function of the status. To reuse a policy, add
/// a `static func` in an extension. Then it works like the built-in ones:
///
/// ```swift
/// extension RetryPolicy {
///     static func linearBackoff(_ step: Duration) -> RetryPolicy {
///         RetryPolicy { status in step * (status.iteration + 1) }
///     }
/// }
///
/// let policy = RetryPolicy.linearBackoff(.milliseconds(500))
///     .and(.limitRetries(4))
///     .capDelay(.milliseconds(1500))
/// // Waits: 0.5s, 1s, 1.5s, 1.5s, then stops
/// ```
///
/// A modifier is an instance method. It calls `self(status)` and changes
/// the wait it returns. It keeps `nil`, so it stops when `self` stops.
///
/// Use ``dryRun()`` to see the steps of a policy without waiting.
public struct RetryPolicy: Sendable {
    @usableFromInline
    let delay: @Sendable (RetryStatus) -> Duration?

    /// Creates a policy from a function. The function returns the wait
    /// before the next retry, or `nil` to stop.
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

    /// The longest possible wait: `Int64.max` milliseconds, about 292
    /// million years.
    ///
    /// ``RetryStatus/applying(_:)`` keeps every wait at or below this value.
    /// So a growing backoff stops growing here and never overflows.
    @inlinable
    public static var maximumDelay: Duration { .milliseconds(Int64.max) }
}

// MARK: - Basic policies

public extension RetryPolicy {
    /// Retries at once, at most `count` times.
    ///
    /// ```swift
    /// RetryPolicy.limitRetries(3)  // Waits: 0, 0, 0, then stops
    /// ```
    @inlinable
    static func limitRetries(_ count: Int) -> RetryPolicy {
        RetryPolicy { status in
            status.iteration < count ? .zero : nil
        }
    }

    /// Waits `delay` before each retry. Never stops.
    ///
    /// `constantDelay(.zero)` is the identity of ``and(_:)``.
    @inlinable
    static func constantDelay(_ delay: Duration) -> RetryPolicy {
        RetryPolicy { _ in delay }
    }

    /// Waits `base` before the first retry, then doubles the wait each time.
    /// Never stops.
    ///
    /// ```swift
    /// RetryPolicy.exponentialBackoff(.milliseconds(100))
    /// // Waits: 100ms, 200ms, 400ms, 800ms, …
    /// ```
    ///
    /// The wait stops growing at ``maximumDelay``. Use ``capDelay(_:)`` for
    /// a smaller limit.
    @inlinable
    static func exponentialBackoff(_ base: Duration) -> RetryPolicy {
        RetryPolicy { status in
            base.doubled(times: status.iteration)
        }
    }
}

// MARK: - Modifiers

public extension RetryPolicy {
    /// Retries only while both policies retry, and waits the longer of the
    /// two waits.
    ///
    /// ```swift
    /// RetryPolicy.constantDelay(.seconds(1)).and(.limitRetries(3))
    /// // Waits: 1s, 1s, 1s, then stops
    /// ```
    ///
    /// `and` is associative, and `constantDelay(.zero)` is its identity. So
    /// you can combine many policies in any grouping:
    /// `policies.reduce(.constantDelay(.zero)) { $0.and($1) }`.
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
    ///
    /// ```swift
    /// RetryPolicy.constantDelay(.seconds(2)).limitRetriesByCumulativeDelay(.seconds(5))
    /// // Waits: 2s, 2s, then stops (one more wait would make 6s in total)
    /// ```
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
    /// The steps of this policy when every attempt fails. The last step is
    /// the one where the policy stops.
    ///
    /// ```swift
    /// let waits = RetryPolicy.exponentialBackoff(.seconds(1))
    ///     .and(.limitRetries(3))
    ///     .dryRun()
    ///     .map(\.previousDelay)
    /// // [1s, 2s, 4s, nil]
    /// ```
    ///
    /// The sequence is lazy. If the policy never stops, the sequence never
    /// ends, so take only the first steps with `prefix`.
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
