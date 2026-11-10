// MARK: - Retry an async Result-returning operation

/// Runs `action`, and runs it again after a failure, as `policy` says.
///
/// Returns the first success, or the last failure when the policy stops. If the task is
/// cancelled, it starts no new attempt and returns the last failure. A running attempt sees
/// the cancellation only if it checks for it.
///
/// ```swift
/// // isTransient is a property of your own error type.
/// let user = await withRetry(apiPolicy, while: \.isTransient) { status in
///     log("attempt \(status.iteration + 1)")
///     return await fetchUser(id)
/// }
/// ```
///
/// - Parameters:
///   - policy: Decides whether to retry, and how long to wait first.
///   - shouldRetry: Returns `true` for failures to retry. The default retries every failure.
///   - clock: The clock for the waits. A wait of zero does not use it.
///   - action: The operation. It gets the current ``RetryStatus``.
@inlinable
public func withRetry<Success, Failure: Error, C: Clock<Duration>>(
    _ policy: RetryPolicy,
    while shouldRetry: (Failure) -> Bool = { _ in true },
    clock: C = ContinuousClock(),
    _ action: (RetryStatus) async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    var status = RetryStatus.initial
    while true {
        let result = await action(status)
        guard case .failure(let error) = result, shouldRetry(error) else {
            return result
        }
        let next = status.applying(policy)
        guard let delay = next.previousDelay, await clock.wait(delay) else {
            return result
        }
        status = next
    }
}

/// Runs `action`, and runs it again after a failure, as `policy` says.
///
/// For an action that does not need the ``RetryStatus``. Otherwise it works like the other
/// `withRetry`.
@inlinable
public func withRetry<Success, Failure: Error, C: Clock<Duration>>(
    _ policy: RetryPolicy,
    while shouldRetry: (Failure) -> Bool = { _ in true },
    clock: C = ContinuousClock(),
    _ action: () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    await withRetry(policy, while: shouldRetry, clock: clock) { _ in await action() }
}

extension Clock<Duration> {
    /// Waits `delay`. Returns `false` if the task is cancelled.
    ///
    /// A wait of zero only checks for cancellation and does not suspend.
    @inlinable
    func wait(_ delay: Duration) async -> Bool {
        guard delay > .zero else { return !Task.isCancelled }
        do {
            try await sleep(for: delay)
            return true
        } catch {
            return false
        }
    }
}
