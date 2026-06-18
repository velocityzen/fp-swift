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
public func withTimeout<Success: Sendable, Failure: Error>(
    _ duration: Duration,
    failingWith timeoutError: Failure,
    _ operation: @Sendable @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    await withTaskGroup(of: Result<Success, Failure>.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: duration)
            return .failure(timeoutError)
        }

        // Two tasks were added, so the first draw always exists. Whichever
        // finishes first wins — the operation (success or failure) or the
        // timer — and the loser is cancelled.
        guard let result = await group.next() else {
            return .failure(timeoutError)
        }
        group.cancelAll()
        return result
    }
}
