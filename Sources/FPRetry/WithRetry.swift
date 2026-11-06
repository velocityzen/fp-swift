// MARK: - Retry an async Result-returning operation

/// Runs `action`. If it fails, waits and runs it again, as `policy` says.
///
/// Returns the first success. If every attempt fails, returns the last
/// failure. A success is never retried.
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
/// `isTransient` is a property of your own error type. It is `true` for
/// failures that can pass on the next try, for example a timeout. The key
/// path `\.isTransient` is the same as `{ error in error.isTransient }`.
///
/// If the task is cancelled, `withRetry` stops and returns the last failure.
/// The action sees the cancellation only if it checks for it.
///
/// - Parameters:
///   - policy: Decides whether to retry, and how long to wait first.
///   - shouldRetry: Returns `true` for failures to retry. By default, every
///     failure is retried.
///   - clock: The clock for the waits. A wait of zero does not use it.
///   - action: The operation to run. It gets the current ``RetryStatus``.
/// - Returns: The first success, or the last failure.
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

/// Runs `action`. If it fails, waits and runs it again, as `policy` says.
///
/// The same as the other `withRetry`, for an action that does not need the
/// ``RetryStatus``.
///
/// ```swift
/// let user = await withRetry(.constantDelay(.seconds(1)).and(.limitRetries(3))) {
///     await fetchUser(id)
/// }
/// ```
///
/// - Parameters:
///   - policy: Decides whether to retry, and how long to wait first.
///   - shouldRetry: Returns `true` for failures to retry. By default, every
///     failure is retried.
///   - clock: The clock for the waits. A wait of zero does not use it.
///   - action: The operation to run.
/// - Returns: The first success, or the last failure.
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
    /// A wait of zero only checks for cancellation, so it does not suspend.
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
