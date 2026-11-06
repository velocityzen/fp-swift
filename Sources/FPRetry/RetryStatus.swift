/// Where a retried operation stands: how many times it has been retried and
/// how long it has waited so far.
///
/// `withRetry` passes the current status to every attempt and asks the policy
/// for the next delay with it. ``RetryPolicy/dryRun()`` lists the statuses a
/// policy goes through without running anything.
///
/// Every delay a status holds is within `.zero...`
/// ``RetryPolicy/maximumDelay``.
public struct RetryStatus: Sendable, Hashable {
    /// The number of retries made so far: `0` on the first attempt, `1` on
    /// the first retry, and so on.
    public let iteration: Int

    /// The sum of every delay waited so far.
    public let cumulativeDelay: Duration

    /// The delay waited before the latest retry: `nil` on the first attempt,
    /// and in the status a policy returns when it gives up.
    public let previousDelay: Duration?

    /// Creates a status, clamping its delays to `.zero...`
    /// ``RetryPolicy/maximumDelay``. Use ``initial`` for the status of a
    /// first attempt.
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

    /// Creates a status from delays already within `.zero...maximumDelay`.
    ///
    /// `Duration`'s comparisons are calls into the standard library, so a
    /// retry clamps each delay once, not every time it builds a status.
    @inlinable
    init(unclamped iteration: Int, cumulativeDelay: Duration, previousDelay: Duration?) {
        self.iteration = iteration
        self.cumulativeDelay = cumulativeDelay
        self.previousDelay = previousDelay
    }

    /// The status of a first attempt: no retries, nothing waited.
    @inlinable
    public static var initial: RetryStatus {
        RetryStatus(unclamped: 0, cumulativeDelay: .zero, previousDelay: nil)
    }
}

public extension RetryStatus {
    /// The status after asking `policy` whether to retry.
    ///
    /// The iteration goes up by one. When the policy retries, its delay
    /// becomes ``previousDelay`` and is added to ``cumulativeDelay``; when it
    /// gives up, ``previousDelay`` is `nil` and ``cumulativeDelay`` stays put.
    ///
    /// Delays are clamped to `.zero...`
    /// ``RetryPolicy/maximumDelay``: a negative delay retries at once, and
    /// one too long for a clock to sleep is cut short.
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
