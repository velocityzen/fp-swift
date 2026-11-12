/// The state of a retried operation: how many retries so far, how long it waited, and how
/// long the last failure asked it to wait.
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

    /// The wait the last failure asked for, for example from an HTTP `Retry-After` header.
    ///
    /// `withRetry` reads it from the failure with its `requestedDelay` function. It is `nil` on
    /// the first attempt, and when the failure asked for no wait. A policy waits this long only
    /// if it uses it, for example with ``RetryPolicy/requestedDelay``.
    public let requestedDelay: Duration?

    /// Creates a status. A wait out of range becomes zero or the maximum. For the first
    /// attempt, use ``initial``.
    @inlinable
    public init(
        iteration: Int = 0,
        cumulativeDelay: Duration = .zero,
        previousDelay: Duration? = nil,
        requestedDelay: Duration? = nil
    ) {
        self.init(
            unclamped: iteration,
            cumulativeDelay: cumulativeDelay.clampedToRetryDelay,
            previousDelay: previousDelay?.clampedToRetryDelay,
            requestedDelay: requestedDelay?.clampedToRetryDelay
        )
    }

    /// Creates a status from waits already in range. It skips the check, because `Duration`
    /// comparisons are not inlined.
    @inlinable
    init(
        unclamped iteration: Int,
        cumulativeDelay: Duration,
        previousDelay: Duration?,
        requestedDelay: Duration?
    ) {
        self.iteration = iteration
        self.cumulativeDelay = cumulativeDelay
        self.previousDelay = previousDelay
        self.requestedDelay = requestedDelay
    }

    /// The status of the first attempt: no retries, no waits.
    @inlinable
    public static var initial: RetryStatus {
        RetryStatus(unclamped: 0, cumulativeDelay: .zero, previousDelay: nil, requestedDelay: nil)
    }
}

public extension RetryStatus {
    /// Returns the next status, after asking `policy` whether to retry.
    ///
    /// The policy sees this status, with `requestedDelay` as its ``requestedDelay``. Then
    /// ``iteration`` grows by one, and stays at `Int.max` once there. If the policy retries,
    /// its wait becomes ``previousDelay`` and is added to ``cumulativeDelay``.
    ///
    /// - Parameters:
    ///   - policy: Decides whether to retry, and how long to wait first.
    ///   - requestedDelay: The wait the failure asked for, or `nil` if it asked for none.
    @inlinable
    func applying(_ policy: RetryPolicy, requestedDelay: Duration? = nil) -> RetryStatus {
        let requested = requestedDelay?.clampedToRetryDelay
        let current = RetryStatus(
            unclamped: iteration,
            cumulativeDelay: cumulativeDelay,
            previousDelay: previousDelay,
            requestedDelay: requested
        )
        guard let delay = policy(current)?.clampedToRetryDelay else {
            return RetryStatus(
                unclamped: nextIteration,
                cumulativeDelay: cumulativeDelay,
                previousDelay: nil,
                requestedDelay: requested
            )
        }
        return RetryStatus(
            unclamped: nextIteration,
            cumulativeDelay: cumulativeDelay.addingRetryDelay(delay),
            previousDelay: delay,
            requestedDelay: requested
        )
    }
}

extension RetryStatus {
    /// The next iteration. It stops at `Int.max` instead of overflowing, like the waits
    /// stop at ``RetryPolicy/maximumDelay``.
    @inlinable
    var nextIteration: Int {
        iteration == .max ? .max : iteration + 1
    }
}
