/// The state of a retried operation: how many retries so far, and how long it waited.
///
/// `withRetry` passes the status to each attempt and to the policy. Every wait in a status is
/// between zero and ``RetryPolicy/maximumDelay``.
public struct RetryStatus: Sendable, Hashable {
    /// The number of retries so far: `0` on the first attempt, `1` on the first retry, and so on.
    public let iteration: Int

    /// The total time waited so far.
    public let cumulativeDelay: Duration

    /// The last wait. It is `nil` on the first attempt, and when the policy stops.
    public let previousDelay: Duration?

    /// Creates a status. A wait out of range becomes zero or the maximum. For the first
    /// attempt, use ``initial``.
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

    /// Creates a status from waits already in range. It skips the check, because `Duration`
    /// comparisons are not inlined.
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
    /// Returns the next status, after asking `policy` whether to retry.
    ///
    /// ``iteration`` grows by one. If the policy retries, its wait becomes ``previousDelay``
    /// and is added to ``cumulativeDelay``.
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
