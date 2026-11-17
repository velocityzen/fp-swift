// MARK: - Read an async sequence of Results into one value

// Each of these reads the sequence and returns one value. They stop reading where their comments
// say. Stopping releases the iterator, so earlier stages stop too: a concurrent map stops reading
// its source and cancels its running transforms, but does not wait for them to stop.
//
// They throw only what the sequence throws. A sequence that can't throw needs no `try`.

extension AsyncSequence {
    /// Reads the elements on `isolation` and passes each one to `step`, until `step` returns a
    /// value or the sequence ends. Every sink reads through this loop.
    ///
    /// The sinks are `nonisolated(nonsending)`, so they hop on their implicit isolation, but
    /// `#isolation` hands `next(isolation:)` a converted copy of it. The compiler removes a hop
    /// only when an earlier hop on the same value dominates it, so it treats the two as
    /// different executors. An operator whose `next(isolation:)` calls an opaque function, like
    /// the cancellation check in `failOnCancellation`, then costs one more executor switch per
    /// element. Here the loop and the operators before it hop on the same `isolation`, and the
    /// compiler removes their hops.
    @inlinable
    func readElements<R>(
        isolation: isolated (any Actor)?,
        until step: (Element) -> R?
    ) async throws(Failure) -> R? {
        var iterator = makeAsyncIterator()
        while let element = try await iterator.next(isolation: isolation) {
            if let result = step(element) {
                return result
            }
        }
        return nil
    }
}

public extension AsyncSequence {
    /// Returns all success values in order, or the first failure.
    ///
    /// It stops reading at the first failure.
    ///
    /// ```swift
    /// let users = await ids.mapAsyncOrdered(concurrency: 8) { id in
    ///     await loadUser(id)
    /// }
    /// .toResult()  // Result<[User], AppError>
    /// ```
    ///
    /// Its result can be dropped, to run a sequence only for what its stages do. Reading
    /// still stops at the first failure.
    @discardableResult
    @inlinable
    func toResult<Success, E>() async throws(Failure) -> Result<[Success], E>
    where Element == Result<Success, E> {
        var values: [Success] = []
        let failure = try await readElements(isolation: #isolation) { element -> E? in
            switch element {
                case .success(let value):
                    values.append(value)
                    return nil
                case .failure(let error):
                    return error
            }
        }
        if let failure {
            return .failure(failure)
        }
        return .success(values)
    }

    /// Returns every element, successes and failures, in order.
    ///
    /// It reads to the end, so it never returns for a sequence that never ends.
    @inlinable
    func toArray<Success, E>() async throws(Failure) -> [Result<Success, E>]
    where Element == Result<Success, E> {
        var elements: [Result<Success, E>] = []
        _ = try await readElements(isolation: #isolation) { element -> Never? in
            elements.append(element)
            return nil
        }
        return elements
    }

    /// Splits the elements into their success values and their failures, each in order.
    ///
    /// It reads to the end, so it never returns for a sequence that never ends.
    @inlinable
    func separate<Success, E>() async throws(Failure) -> (successes: [Success], failures: [E])
    where Element == Result<Success, E> {
        var successes: [Success] = []
        var failures: [E] = []
        _ = try await readElements(isolation: #isolation) { element -> Never? in
            switch element {
                case .success(let value):
                    successes.append(value)
                case .failure(let error):
                    failures.append(error)
            }
            return nil
        }
        return (successes, failures)
    }

    /// Returns the first element, a success or a failure, or `nil` if the sequence is empty.
    ///
    /// It stops reading after the first element. After a concurrent map that gives results in
    /// the order they finish, it is the first one to finish.
    @inlinable
    func first<Success, E>() async throws(Failure) -> Result<Success, E>?
    where Element == Result<Success, E> {
        try await readElements(isolation: #isolation) { element in element }
    }

    /// Returns the first success value, or `nil` if there is none.
    ///
    /// It skips failures and stops reading at the first success.
    @inlinable
    func firstSuccess<Success, E>() async throws(Failure) -> Success?
    where Element == Result<Success, E> {
        try await readElements(isolation: #isolation) { element -> Success? in
            if case .success(let value) = element {
                return value
            }
            return nil
        }
    }

    /// Returns the first failure, or `nil` if there is none.
    ///
    /// It skips successes and stops reading at the first failure.
    @inlinable
    func firstError<Success, E>() async throws(Failure) -> E?
    where Element == Result<Success, E> {
        try await readElements(isolation: #isolation) { element -> E? in
            if case .failure(let error) = element {
                return error
            }
            return nil
        }
    }

    /// Returns the first success, or the last failure if nothing succeeds, or `nil` if the
    /// sequence is empty. It follows the same rule as `withAny`.
    ///
    /// It skips failures and stops reading at the first success. With no success, it reads to
    /// the end, so it never returns for a sequence that never ends and never succeeds.
    ///
    /// ```swift
    /// let payload = await mirrors.mapAsyncUnordered(concurrency: 4) { mirror in
    ///     await fetch(from: mirror)
    /// }
    /// .firstSuccessOrLastError()
    /// ```
    @inlinable
    func firstSuccessOrLastError<Success, E>() async throws(Failure) -> Result<Success, E>?
    where Element == Result<Success, E> {
        var lastFailure: Result<Success, E>?
        let success = try await readElements(isolation: #isolation) {
            element -> Result<Success, E>? in
            if case .success = element {
                return element
            }
            lastFailure = element
            return nil
        }
        return success ?? lastFailure
    }

    /// Returns the last element, a success or a failure, or `nil` if the sequence is empty.
    ///
    /// It reads to the end, so it never returns for a sequence that never ends. It keeps only
    /// the latest element while it reads.
    @inlinable
    func last<Success, E>() async throws(Failure) -> Result<Success, E>?
    where Element == Result<Success, E> {
        var last: Result<Success, E>?
        _ = try await readElements(isolation: #isolation) { element -> Never? in
            last = element
            return nil
        }
        return last
    }

    /// Returns the last success value, or `nil` if there is none.
    ///
    /// It skips failures and reads to the end, so it never returns for a sequence that never
    /// ends.
    @inlinable
    func lastSuccess<Success, E>() async throws(Failure) -> Success?
    where Element == Result<Success, E> {
        var last: Success?
        _ = try await readElements(isolation: #isolation) { element -> Never? in
            if case .success(let value) = element {
                last = value
            }
            return nil
        }
        return last
    }

    /// Returns the last failure, or `nil` if there is none.
    ///
    /// It skips successes and reads to the end, so it never returns for a sequence that never
    /// ends.
    @inlinable
    func lastError<Success, E>() async throws(Failure) -> E?
    where Element == Result<Success, E> {
        var last: E?
        _ = try await readElements(isolation: #isolation) { element -> Never? in
            if case .failure(let error) = element {
                last = error
            }
            return nil
        }
        return last
    }

    /// Combines all success values into one value, or returns the first failure.
    ///
    /// It starts with `initial` and stops reading at the first failure. `combine` runs on the
    /// caller's actor.
    ///
    /// ```swift
    /// let total = await sizes.reduce(0) { sum, size in sum + size }
    /// ```
    @inlinable
    func reduce<Success, E, U>(
        _ initial: U,
        _ combine: (U, Success) -> U
    ) async throws(Failure) -> Result<U, E>
    where Element == Result<Success, E> {
        var accumulated = initial
        let failure = try await readElements(isolation: #isolation) { element -> E? in
            switch element {
                case .success(let value):
                    accumulated = combine(accumulated, value)
                    return nil
                case .failure(let error):
                    return error
            }
        }
        if let failure {
            return .failure(failure)
        }
        return .success(accumulated)
    }

    /// Updates one value in place with each success value, or returns the first failure.
    ///
    /// It starts with `initial` and stops reading at the first failure. `update` changes the
    /// value in place, so building an array or a dictionary does not copy it for every element.
    /// `update` runs on the caller's actor.
    ///
    /// ```swift
    /// let byOwner = await files.reduce(into: [String: [File]]()) { groups, file in
    ///     groups[file.owner, default: []].append(file)
    /// }
    /// ```
    @inlinable
    func reduce<Success, E, U>(
        into initial: U,
        _ update: (inout U, Success) -> Void
    ) async throws(Failure) -> Result<U, E>
    where Element == Result<Success, E> {
        var accumulated = initial
        let failure = try await readElements(isolation: #isolation) { element -> E? in
            switch element {
                case .success(let value):
                    update(&accumulated, value)
                    return nil
                case .failure(let error):
                    return error
            }
        }
        if let failure {
            return .failure(failure)
        }
        return .success(accumulated)
    }
}
