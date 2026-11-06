/// A retry policy: given where a retried operation stands, the delay before
/// the next retry, or `nil` to give up.
///
/// A policy is a plain value — a function of ``RetryStatus`` — so it is
/// defined once and reused by every call that retries with it. Build one from
/// the basic policies and refine it with modifiers:
///
/// ```swift
/// // Random delays up to 200ms, 400ms, 800ms, … capped at 2s, at most 5 retries.
/// let apiPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
///     .and(.limitRetries(5))
///     .capDelay(.seconds(2))
///     .jitter()
///
/// let user = await withRetry(apiPolicy) { await fetchUser(id) }
/// ```
///
/// **Basic policies**
/// - ``limitRetries(_:)`` retries at once, a fixed number of times.
/// - ``constantDelay(_:)`` waits the same delay before every retry, forever.
/// - ``exponentialBackoff(_:)`` doubles the delay before every retry, forever.
///
/// **Combining and modifying**
/// - ``and(_:)`` retries only while both policies do, waiting the longer of
///   their delays. With ``constantDelay(_:)`` of `.zero` as its identity it
///   makes policies a monoid.
/// - ``capDelay(_:)`` caps every delay, retrying as often as before.
/// - ``limitRetriesByDelay(_:)`` gives up once a single delay grows too long.
/// - ``limitRetriesByCumulativeDelay(_:)`` gives up before the total wait
///   grows too long.
/// - ``jitter(_:)`` multiplies every delay by a random factor, so clients
///   that failed together do not retry together. Add it last.
///
/// **Your own policies**
///
/// ``init(_:)`` wraps any function of the status. Put a reusable one in an
/// extension as a `static func`, and it reads and composes like the
/// built-ins:
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
/// // 0.5s, 1s, 1.5s, 1.5s, then gives up
/// ```
///
/// A modifier is an instance method that calls `self(status)` and reshapes
/// the delay it returns, passing `nil` through.
///
/// ``dryRun()`` lists the statuses a policy goes through, to check its
/// schedule without running anything.
public struct RetryPolicy: Sendable {
    @usableFromInline
    let delay: @Sendable (RetryStatus) -> Duration?

    /// Creates a policy from a function of the status to the delay before
    /// the next retry, or `nil` to give up.
    ///
    /// ```swift
    /// // Retry every second during the first minute only.
    /// let firstMinute = RetryPolicy { status in
    ///     status.cumulativeDelay < .seconds(60) ? .seconds(1) : nil
    /// }
    /// ```
    @inlinable
    public init(_ delay: @escaping @Sendable (RetryStatus) -> Duration?) {
        self.delay = delay
    }

    /// The delay before the next retry, or `nil` when the policy gives up.
    @inlinable
    public func callAsFunction(_ status: RetryStatus) -> Duration? {
        delay(status)
    }

    /// The longest delay a retry waits: `Int64.max` milliseconds, about 292
    /// million years.
    ///
    /// ``RetryStatus/applying(_:)`` clamps every delay to it, so a backoff
    /// that keeps growing saturates instead of overflowing, and every delay
    /// can be slept.
    @inlinable
    public static var maximumDelay: Duration { .milliseconds(Int64.max) }
}

// MARK: - Basic policies

public extension RetryPolicy {
    /// Retries at once, at most `count` times.
    ///
    /// ```swift
    /// RetryPolicy.limitRetries(3)  // .zero, .zero, .zero, then gives up
    /// ```
    @inlinable
    static func limitRetries(_ count: Int) -> RetryPolicy {
        RetryPolicy { status in
            status.iteration < count ? .zero : nil
        }
    }

    /// Waits `delay` before every retry, and never gives up.
    ///
    /// `constantDelay(.zero)` is the identity of ``and(_:)``.
    @inlinable
    static func constantDelay(_ delay: Duration) -> RetryPolicy {
        RetryPolicy { _ in delay }
    }

    /// Waits `base` before the first retry and doubles the delay before
    /// every retry after it, and never gives up.
    ///
    /// ```swift
    /// RetryPolicy.exponentialBackoff(.milliseconds(100))
    /// // 100ms, 200ms, 400ms, 800ms, …
    /// ```
    ///
    /// The delay saturates at ``maximumDelay`` rather than overflowing; cap
    /// it with ``capDelay(_:)``.
    @inlinable
    static func exponentialBackoff(_ base: Duration) -> RetryPolicy {
        RetryPolicy { status in
            base.doubled(times: status.iteration)
        }
    }
}

// MARK: - Combining and modifying

public extension RetryPolicy {
    /// A policy that retries only while both this one and `other` do,
    /// waiting the longer of their two delays.
    ///
    /// ```swift
    /// RetryPolicy.constantDelay(.seconds(1)).and(.limitRetries(3))
    /// // 1s, 1s, 1s, then gives up
    /// ```
    ///
    /// `and` is associative and ``constantDelay(_:)`` of `.zero` is its
    /// identity, so policies combine in any grouping:
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

    /// Caps every delay at `maximum`, retrying exactly as often as before.
    ///
    /// ```swift
    /// RetryPolicy.exponentialBackoff(.seconds(1)).capDelay(.seconds(5))
    /// // 1s, 2s, 4s, 5s, 5s, …
    /// ```
    @inlinable
    func capDelay(_ maximum: Duration) -> RetryPolicy {
        RetryPolicy { status in
            self(status).map { min($0, maximum) }
        }
    }

    /// Gives up as soon as the next delay would be longer than `maximum`.
    ///
    /// ```swift
    /// RetryPolicy.exponentialBackoff(.seconds(1)).limitRetriesByDelay(.seconds(5))
    /// // 1s, 2s, 4s, then gives up (the next delay would be 8s)
    /// ```
    @inlinable
    func limitRetriesByDelay(_ maximum: Duration) -> RetryPolicy {
        RetryPolicy { status in
            self(status).flatMap { $0 <= maximum ? $0 : nil }
        }
    }

    /// Gives up as soon as the next delay would bring the total time waited
    /// past `maximum`.
    ///
    /// ```swift
    /// RetryPolicy.constantDelay(.seconds(2)).limitRetriesByCumulativeDelay(.seconds(5))
    /// // 2s, 2s, then gives up (another 2s would be 6s in all)
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
    /// The statuses this policy goes through when every attempt fails, in
    /// order, ending with the status in which it gives up.
    ///
    /// ```swift
    /// let delays = RetryPolicy.exponentialBackoff(.seconds(1))
    ///     .and(.limitRetries(3))
    ///     .dryRun()
    ///     .map(\.previousDelay)
    /// // [1s, 2s, 4s, nil]
    /// ```
    ///
    /// The sequence is lazy, so a policy that never gives up yields statuses
    /// forever: take a `prefix` of it.
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
