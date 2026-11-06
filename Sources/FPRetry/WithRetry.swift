// MARK: - Retry an async Result-returning operation

/// Runs `action` and, while it fails with an error `shouldRetry` accepts,
/// runs it again after the delay `policy` gives, until it succeeds or the
/// policy gives up.
///
/// Returns the first success, or the latest failure once the policy gives up
/// or `shouldRetry` rejects the error. A success is never retried.
///
/// ```swift
/// let apiPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
///     .and(.limitRetries(5))
///     .capDelay(.seconds(2))
///     .jitter()
///
/// let user = await withRetry(apiPolicy, while: \.isTransient) { status in
///     logger.debug("attempt \(status.iteration + 1)")
///     return await fetchUser(id)
/// }
/// // Result<User, APIError>
/// ```
///
/// `isTransient` stands for a property of your own error type that tells
/// failures worth retrying (a timeout, a 503) from ones that fail the same
/// way every time (a 404). The key path `\.isTransient` works as the
/// function `{ error in error.isTransient }`.
///
/// Each attempt gets the current ``RetryStatus``: `iteration` is `0` on the
/// first attempt, and `previousDelay` is the delay waited before it.
///
/// Retrying stops when the task is cancelled: a cancelled wait, or a
/// cancellation seen before an immediate retry, returns the latest failure
/// at once. The action itself sees cancellation only if it checks for it.
///
/// - Parameters:
///   - policy: Decides whether to retry a failure, and after what delay.
///   - shouldRetry: Whether a failure may be retried at all. Retries every
///     failure by default.
///   - clock: The clock that waits out the delays. A delay of `.zero`
///     retries without waiting on it.
///   - action: The operation to run, given the current status.
/// - Returns: The first success, or the latest failure.
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

/// Runs `action` and, while it fails with an error `shouldRetry` accepts,
/// runs it again after the delay `policy` gives, until it succeeds or the
/// policy gives up.
///
/// The same as the overload whose action takes a ``RetryStatus``, for an
/// action that does not need it.
///
/// ```swift
/// let user = await withRetry(.constantDelay(.seconds(1)).and(.limitRetries(3))) {
///     await fetchUser(id)
/// }
/// ```
///
/// - Parameters:
///   - policy: Decides whether to retry a failure, and after what delay.
///   - shouldRetry: Whether a failure may be retried at all. Retries every
///     failure by default.
///   - clock: The clock that waits out the delays. A delay of `.zero`
///     retries without waiting on it.
///   - action: The operation to run.
/// - Returns: The first success, or the latest failure.
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
    /// Waits `delay` before a retry: `true` to retry, `false` when the task
    /// was cancelled before or while waiting.
    ///
    /// A delay of `.zero` only checks for cancellation, so an immediate retry
    /// costs no suspension.
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
