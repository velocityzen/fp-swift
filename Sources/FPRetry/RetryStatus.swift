/// The state of a retried operation: how many retries so far, and how long
/// it waited.
///
/// `withRetry` gives the status to each attempt, and to the policy.
/// ``RetryPolicy/dryRun()`` shows the statuses of a policy without waiting.
///
/// Every wait in a status is between zero and ``RetryPolicy/maximumDelay``.
public struct RetryStatus: Sendable, Hashable {
    /// The number of retries so far. It is `0` on the first attempt, `1` on
    /// the first retry, and so on.
    public let iteration: Int

    /// The total time waited so far.
    public let cumulativeDelay: Duration

    /// The last wait. It is `nil` on the first attempt, and when the policy
    /// stops.
    public let previousDelay: Duration?

    /// Creates a status. Waits are kept between zero and
    /// ``RetryPolicy/maximumDelay``. For the first attempt, use ``initial``.
    @inlinable
    public init(
        iteration: Int = 0,
        cumulativeDelay: Duration = .zero,
        previousDelay: Duration? = nil
    ) {
        self.init(
            unclamped: iteration,
            cumulativeDelay: cumulativeDelay.clampedToRetryDelay,
            previousDelay: previousDelay?.clampedToRetryDelay
        )
    }

    /// Creates a status from waits that are already between zero and
    /// `maximumDelay`.
    ///
    /// `Duration` comparisons are calls into the standard library, so a
    /// retry clamps each wait only once.
    @inlinable
    init(unclamped iteration: Int, cumulativeDelay: Duration, previousDelay: Duration?) {
        self.iteration = iteration
        self.cumulativeDelay = cumulativeDelay
        self.previousDelay = previousDelay
    }

    /// The status of the first attempt: no retries, no waits.
    @inlinable
    public static var initial: RetryStatus {
        RetryStatus(unclamped: 0, cumulativeDelay: .zero, previousDelay: nil)
    }
}

public extension RetryStatus {
    /// The next status, after asking `policy` whether to retry.
    ///
    /// ``iteration`` grows by one. If the policy retries, its wait becomes
    /// ``previousDelay`` and is added to ``cumulativeDelay``. If the policy
    /// stops, ``previousDelay`` is `nil`.
    ///
    /// A wait below zero becomes zero. A wait above
    /// ``RetryPolicy/maximumDelay`` becomes the maximum.
    ///
    /// ```swift
    /// let next = RetryStatus.initial.applying(.constantDelay(.seconds(1)))
    /// // RetryStatus(iteration: 1, cumulativeDelay: 1s, previousDelay: 1s)
    /// ```
    @inlinable
    func applying(_ policy: RetryPolicy) -> RetryStatus {
        guard let delay = policy(self)?.clampedToRetryDelay else {
            return RetryStatus(
                unclamped: iteration + 1,
                cumulativeDelay: cumulativeDelay,
                previousDelay: nil
            )
        }
        return RetryStatus(
            unclamped: iteration + 1,
            cumulativeDelay: cumulativeDelay.addingRetryDelay(delay),
            previousDelay: delay
        )
    }
}
