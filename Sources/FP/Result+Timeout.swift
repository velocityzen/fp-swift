// MARK: - Run an async operation with a timeout

/// Runs `operation`, returning its `Result` if it finishes within `duration`,
/// or `.failure(timeoutError)` if it doesn't — cancelling the operation when
/// the timeout wins.
///
/// This is a race between the operation and a timer where whichever finishes
/// **first** wins. A fast failure is *not* swallowed: if the operation fails
/// before the timeout elapses, that failure is returned immediately. The
/// timeout error only wins when the operation outlasts `duration`, in which
/// case the still-running operation is cancelled.
///
/// ```swift
/// let user = await withTimeout(.seconds(5), failingWith: .timeout) {
///     await fetchUser(id)
/// }
/// // Result<User, AppError> — the fetch result, or .failure(.timeout) after 5s.
/// ```
///
/// Cancellation is cooperative: when the timeout fires, the operation stops
/// promptly only if it checks `Task.isCancelled` (or awaits a
/// cancellation-aware API). A non-cooperative operation keeps running until it
/// finishes naturally, though its result is discarded once the timeout has won.
///
/// - Parameters:
///   - duration: How long to wait before timing out.
///   - timeoutError: The failure returned if `duration` elapses first.
///   - operation: The async work to run.
/// - Returns: The operation's `Result`, or `.failure(timeoutError)` on timeout.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
@inlinable
public func withTimeout<Success: Sendable, Failure: Error>(
    _ duration: Duration,
    failingWith timeoutError: Failure,
    _ operation: @concurrent @Sendable @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    // Whichever finishes first opens the gate — the operation (success or
    // failure) or the timer. Leaving the scope then cancels the loser and
    // waits for it to stop.
    let gate = Gate<Result<Success, Failure>>()
    async let _ = gate.open(with: await operation())
    async let _ = gate.open(after: duration, with: .failure(timeoutError))
    return await gate.wait()
}
