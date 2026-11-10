// MARK: - Run an async operation with a timeout

/// Runs `operation` with a time limit.
///
/// If `operation` finishes within `duration`, this returns its result, even a failure.
/// Otherwise it cancels `operation` and returns `.failure(timeoutError)`.
///
/// A cancelled operation stops early only if it checks for cancellation. Its result is then
/// ignored, and this function returns only after it stops.
///
/// ```swift
/// let user = await withTimeout(.seconds(5), failingWith: .timeout) {
///     await fetchUser(id)
/// }
/// ```
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
@inlinable
public func withTimeout<Success: Sendable, Failure: Error>(
    _ duration: Duration,
    failingWith timeoutError: Failure,
    _ operation: @concurrent @Sendable @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    // The operation (success or failure) or the timer, whichever finishes first, opens the gate.
    // Leaving the scope cancels the other and waits for it to stop.
    let gate = Gate<Result<Success, Failure>>()
    async let _ = gate.open(with: await operation())
    async let _ = gate.open(after: duration, with: .failure(timeoutError))
    return await gate.wait()
}
