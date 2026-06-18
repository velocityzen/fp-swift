// MARK: - Race async operations, first success wins

// MARK: Arity 2…10 (autoclosure)

/// Runs several async `Result`-producing operations concurrently and returns
/// the first one to finish **with a success**, cancelling the rest.
///
/// This is the important correction to a plain "whoever finishes first wins"
/// race: an operation that completes first with a `.failure` does *not* win.
/// Failures are passed over while the remaining operations keep running, so a
/// fast failure never beats a slower success. The first `.success` to arrive is
/// returned immediately and the still-running operations are cancelled.
///
/// If *every* operation fails, the last failure to complete is returned — at
/// least two operations always run, so a failure is always available.
///
/// Operations are taken as autoclosures, so each call is deferred and raced
/// rather than evaluated up front — the same ergonomics as `withAll`:
///
/// ```swift
/// // Hit several mirrors, take whichever responds successfully first.
/// let payload = await withAny(
///     await fetch(from: primaryMirror),
///     await fetch(from: backupMirror),
///     await fetch(from: archiveMirror)
/// )
/// // Result<Payload, NetworkError> — the first mirror to succeed, or the last
/// // failure if all of them failed.
/// ```
///
/// To race a dynamic number of operations, build an array of closures and use
/// the `withAny([...])` array overload instead.
///
/// Cancellation of the losers is cooperative: an in-flight operation stops
/// promptly only if it checks `Task.isCancelled` (or awaits a
/// cancellation-aware API). A long, non-cooperative operation runs to
/// completion before this function returns, even after a winner is chosen.
///
/// Supports 2 to 10 operations; for more, use the array overload.
public func withAny<Success: Sendable, Failure: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    await withAny([a, b])
}

public func withAny<Success: Sendable, Failure: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    await withAny([a, b, c])
}

public func withAny<Success: Sendable, Failure: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    await withAny([a, b, c, d])
}

public func withAny<Success: Sendable, Failure: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    await withAny([a, b, c, d, f])
}

public func withAny<Success: Sendable, Failure: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ g: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    await withAny([a, b, c, d, f, g])
}

public func withAny<Success: Sendable, Failure: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ g: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ h: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    await withAny([a, b, c, d, f, g, h])
}

public func withAny<Success: Sendable, Failure: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ g: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ h: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ i: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    await withAny([a, b, c, d, f, g, h, i])
}

public func withAny<Success: Sendable, Failure: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ g: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ h: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ i: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ j: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    await withAny([a, b, c, d, f, g, h, i, j])
}

public func withAny<Success: Sendable, Failure: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ g: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ h: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ i: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ j: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ k: @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    await withAny([a, b, c, d, f, g, h, i, j, k])
}

// MARK: - Race a dynamic array of operations

/// Runs every operation in `operations` concurrently and returns the first to
/// finish **with a success**, cancelling the rest. This is the array form of
/// the variadic `withAny` — use it to race a number of operations not known
/// until runtime (e.g. one per endpoint loaded from config).
///
/// Failures are passed over while the rest keep running; the first `.success`
/// wins and cancels the others. If every operation fails, the last failure to
/// complete is returned. Cancellation of the losers is cooperative.
///
/// ```swift
/// let attempts: [@Sendable () async -> Result<Payload, NetworkError>] =
///     mirrors.map { mirror in { await fetch(from: mirror) } }
/// let payload = await withAny(attempts)
/// ```
///
/// - Parameter operations: The operations to race. Must not be empty.
/// - Returns: The first successful `Result`, or — if none succeed — the last
///   failure to complete.
/// - Precondition: `operations` is non-empty.
public func withAny<Success: Sendable, Failure: Error>(
    _ operations: [@Sendable () async -> Result<Success, Failure>]
) async -> Result<Success, Failure> {
    precondition(!operations.isEmpty, "withAny requires at least one operation")

    return await withTaskGroup(of: Result<Success, Failure>.self) { group in
        for operation in operations {
            group.addTask { await operation() }
        }

        var lastFailure: Failure?
        for await result in group {
            switch result {
                case .success:
                    group.cancelAll()
                    return result
                case .failure(let error):
                    lastFailure = error
            }
        }

        // Unreachable: the precondition guarantees at least one operation, and
        // each one completes with a success (returned above) or a failure
        // (captured here). Re-running the first keeps the result type inhabited
        // without a force-unwrap.
        guard let lastFailure else {
            return await operations[0]()
        }
        return .failure(lastFailure)
    }
}
