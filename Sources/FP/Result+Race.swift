// MARK: - Race async operations, first success wins

// MARK: Arity 2…10 (autoclosure)

// Arities 3 to 10 repeat arity 2, so only arity 2 has comments.

/// Runs several async operations at the same time and returns the first success.
///
/// A failure does not win: the other operations keep running, so a fast failure never beats a
/// slower success. When the first success arrives, the other operations are cancelled. If all
/// operations fail, the result is the last failure to arrive.
///
/// Each argument is an autoclosure, so the calls start inside `withAny`, not before it. A
/// cancelled operation stops early only if it checks for cancellation, and this function
/// returns only after all operations stop.
///
/// ```swift
/// let payload = await withAny(
///     await fetch(from: primaryMirror),
///     await fetch(from: backupMirror)
/// )
/// ```
///
/// Takes 2 to 10 operations. For more, or for a number known only at run time, pass an array.
@inlinable
public func withAny<Success: Sendable, Failure: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    let gate = Gate<Result<Success, Failure>>(parties: 2)
    async let _ = gate.race(await a())
    async let _ = gate.race(await b())
    // Leaving the scope cancels the running operations and waits for them to stop.
    return await gate.wait()
}

@inlinable
public func withAny<Success: Sendable, Failure: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    let gate = Gate<Result<Success, Failure>>(parties: 3)
    async let _ = gate.race(await a())
    async let _ = gate.race(await b())
    async let _ = gate.race(await c())
    return await gate.wait()
}

@inlinable
public func withAny<Success: Sendable, Failure: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    let gate = Gate<Result<Success, Failure>>(parties: 4)
    async let _ = gate.race(await a())
    async let _ = gate.race(await b())
    async let _ = gate.race(await c())
    async let _ = gate.race(await d())
    return await gate.wait()
}

@inlinable
public func withAny<Success: Sendable, Failure: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    let gate = Gate<Result<Success, Failure>>(parties: 5)
    async let _ = gate.race(await a())
    async let _ = gate.race(await b())
    async let _ = gate.race(await c())
    async let _ = gate.race(await d())
    async let _ = gate.race(await f())
    return await gate.wait()
}

@inlinable
public func withAny<Success: Sendable, Failure: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ g: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    let gate = Gate<Result<Success, Failure>>(parties: 6)
    async let _ = gate.race(await a())
    async let _ = gate.race(await b())
    async let _ = gate.race(await c())
    async let _ = gate.race(await d())
    async let _ = gate.race(await f())
    async let _ = gate.race(await g())
    return await gate.wait()
}

@inlinable
public func withAny<Success: Sendable, Failure: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ g: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ h: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    let gate = Gate<Result<Success, Failure>>(parties: 7)
    async let _ = gate.race(await a())
    async let _ = gate.race(await b())
    async let _ = gate.race(await c())
    async let _ = gate.race(await d())
    async let _ = gate.race(await f())
    async let _ = gate.race(await g())
    async let _ = gate.race(await h())
    return await gate.wait()
}

@inlinable
public func withAny<Success: Sendable, Failure: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ g: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ h: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ i: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    let gate = Gate<Result<Success, Failure>>(parties: 8)
    async let _ = gate.race(await a())
    async let _ = gate.race(await b())
    async let _ = gate.race(await c())
    async let _ = gate.race(await d())
    async let _ = gate.race(await f())
    async let _ = gate.race(await g())
    async let _ = gate.race(await h())
    async let _ = gate.race(await i())
    return await gate.wait()
}

@inlinable
public func withAny<Success: Sendable, Failure: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ g: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ h: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ i: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ j: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    let gate = Gate<Result<Success, Failure>>(parties: 9)
    async let _ = gate.race(await a())
    async let _ = gate.race(await b())
    async let _ = gate.race(await c())
    async let _ = gate.race(await d())
    async let _ = gate.race(await f())
    async let _ = gate.race(await g())
    async let _ = gate.race(await h())
    async let _ = gate.race(await i())
    async let _ = gate.race(await j())
    return await gate.wait()
}

@inlinable
public func withAny<Success: Sendable, Failure: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ g: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ h: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ i: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ j: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>,
    _ k: @concurrent @Sendable @autoclosure @escaping () async -> Result<Success, Failure>
) async -> Result<Success, Failure> {
    let gate = Gate<Result<Success, Failure>>(parties: 10)
    async let _ = gate.race(await a())
    async let _ = gate.race(await b())
    async let _ = gate.race(await c())
    async let _ = gate.race(await d())
    async let _ = gate.race(await f())
    async let _ = gate.race(await g())
    async let _ = gate.race(await h())
    async let _ = gate.race(await i())
    async let _ = gate.race(await j())
    async let _ = gate.race(await k())
    return await gate.wait()
}

// MARK: - Race a dynamic array of operations

/// Runs all `operations` at the same time and returns the first success.
///
/// Use it when the number of operations is known only at run time. `operations` must not be
/// empty. Otherwise it works like the `withAny` that takes 2 to 10 operations.
///
/// ```swift
/// let attempts: [@concurrent @Sendable () async -> Result<Payload, AppError>] =
///     mirrors.map { mirror in { await fetch(from: mirror) } }
/// let payload = await withAny(attempts)
/// ```
// Not `@inlinable`: specialized in the caller, it costs one more retain and release per
// operation and is not faster.
public func withAny<Success: Sendable, Failure: Error>(
    _ operations: [@concurrent @Sendable () async -> Result<Success, Failure>]
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

        // Unreachable: there is at least one operation, and each one gives a success (returned
        // above) or a failure (kept here). Running the first one again avoids a force-unwrap.
        guard let lastFailure else {
            return await operations[0]()
        }
        return .failure(lastFailure)
    }
}
