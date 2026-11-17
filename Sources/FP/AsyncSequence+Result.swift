// MARK: - AsyncSequence Extensions for Result

public extension AsyncSequence {
    /// Turns the sequence into a sequence of results that never throws.
    ///
    /// Each element becomes `.success(element)`, and the error the sequence throws becomes the
    /// last element, `.failure(error)`. After it, the sequence ends and does not read the base
    /// again. The sinks then read it without `try`, and the error keeps its type.
    ///
    /// ```swift
    /// let lines = await file.lines
    ///     .asResults()
    ///     .toResult()  // Result<[String], any Error>
    /// ```
    @inlinable
    func asResults() -> ResultsSequence<Self> {
        ResultsSequence(self)
    }
}

public extension AsyncSequence {
    /// Returns an async sequence of only the success values.
    @inlinable
    func successes<Success, Failure>()
        -> ResultCompactMapSequence<Self, Success>
    where Element == Result<Success, Failure> {
        ResultCompactMapSequence(self) { element in
            if case .success(let value) = element { return value }
            return nil
        }
    }

    /// Returns an async sequence of only the errors.
    @inlinable
    func failures<Success, Failure>()
        -> ResultCompactMapSequence<Self, Failure>
    where Element == Result<Success, Failure> {
        ResultCompactMapSequence(self) { element in
            if case .failure(let error) = element { return error }
            return nil
        }
    }

    /// The values, as a sequence that throws the first failure.
    ///
    /// It gives each `.success` value as it comes. At the first `.failure`, it throws that error
    /// and ends, and does not read the sequence again. It is the inverse of `asResults()`.
    ///
    /// ```swift
    /// for try await user in ids.mapAsyncOrdered(concurrency: 8) { await loadUser(id: $0) }.get() {
    ///     show(user)
    /// }
    /// ```
    @inlinable
    func get<Success, Failure>() -> GetSequence<Self, Success, Failure>
    where Element == Result<Success, Failure>, Self.Failure == Never {
        GetSequence(self)
    }

    /// The elements up to and including the first failure.
    ///
    /// After the failure, it ends and does not read the sequence again. Use it to read an
    /// endless sequence, like `withRepeat`, until something fails.
    @inlinable
    func untilFailure<Success, Failure>() -> UntilSequence<Self, Success, Failure>
    where Element == Result<Success, Failure> {
        UntilSequence(self, stopsOnSuccess: false)
    }

    /// The elements up to and including the first success.
    ///
    /// After the success, it ends and does not read the sequence again. Use it to poll with
    /// `withRepeat` until a call succeeds.
    ///
    /// ```swift
    /// for await status in withRepeat(interval: .seconds(5)) { await checkJob(id) }
    ///     .untilSuccess()
    /// {
    ///     show(status)
    /// }
    /// ```
    @inlinable
    func untilSuccess<Success, Failure>() -> UntilSequence<Self, Success, Failure>
    where Element == Result<Success, Failure> {
        UntilSequence(self, stopsOnSuccess: true)
    }

    // MARK: Map

    /// Transforms each success value, and passes failures through unchanged.
    @inlinable
    func map<Success, Failure, T>(
        _ transform: @Sendable @escaping (Success) -> T
    ) -> ResultMapSequence<Self, Result<T, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapSequence(self) { element in
            element.map(transform)
        }
    }

    /// Transforms each success value with an async closure, and passes failures
    /// through unchanged.
    @inlinable
    func mapAsync<Success, Failure, T>(
        _ transform: @Sendable @escaping (Success) async -> T
    ) -> ResultMapAsyncSequence<Self, Result<T, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapAsyncSequence(self) { element in
            await element.mapAsync(transform)
        }
    }

    /// Transforms each error, and passes successes through unchanged.
    @inlinable
    func mapError<Success, Failure, E>(
        _ transform: @Sendable @escaping (Failure) -> E
    ) -> ResultMapSequence<Self, Result<Success, E>>
    where Element == Result<Success, Failure> {
        ResultMapSequence(self) { element in
            element.mapError(transform)
        }
    }

    /// Transforms each error with an async closure, and passes successes
    /// through unchanged.
    @inlinable
    func mapErrorAsync<Success, Failure, E: Error>(
        _ transform: @Sendable @escaping (Failure) async -> E
    ) -> ResultMapAsyncSequence<Self, Result<Success, E>>
    where Element == Result<Success, Failure> {
        ResultMapAsyncSequence(self) { element in
            await element.mapErrorAsync(transform)
        }
    }

    // MARK: FlatMap

    /// Transforms each success value with a closure that returns a `Result`.
    @inlinable
    func flatMap<Success, Failure, T>(
        _ transform: @Sendable @escaping (Success) -> Result<T, Failure>
    ) -> ResultMapSequence<Self, Result<T, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapSequence(self) { element in
            element.flatMap(transform)
        }
    }

    /// Transforms each success value with an async closure that returns a
    /// `Result`.
    @inlinable
    func flatMapAsync<Success, Failure, T>(
        _ transform: @Sendable @escaping (Success) async -> Result<T, Failure>
    ) -> ResultMapAsyncSequence<Self, Result<T, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapAsyncSequence(self) { element in
            await element.flatMapAsync(transform)
        }
    }

    // MARK: Tap

    /// Runs `action` on each success value, and passes every element through
    /// unchanged.
    @inlinable
    func tap<Success, Failure>(
        _ action: @Sendable @escaping (Success) -> Void
    ) -> ResultMapSequence<Self, Result<Success, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapSequence(self) { element in
            element.tap(action)
        }
    }

    /// Runs an async `action` on each success value, and passes every element
    /// through unchanged.
    @inlinable
    func tapAsync<Success, Failure>(
        _ action: @Sendable @escaping (Success) async -> Void
    ) -> ResultMapAsyncSequence<Self, Result<Success, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapAsyncSequence(self) { element in
            await element.tapAsync(action)
        }
    }

    // MARK: TapError

    /// Runs `action` on each error, and passes every element through unchanged.
    @inlinable
    func tapError<Success, Failure>(
        _ action: @Sendable @escaping (Failure) -> Void
    ) -> ResultMapSequence<Self, Result<Success, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapSequence(self) { element in
            element.tapError(action)
        }
    }

    /// Runs an async `action` on each error, and passes every element through
    /// unchanged.
    @inlinable
    func tapErrorAsync<Success, Failure>(
        _ action: @Sendable @escaping (Failure) async -> Void
    ) -> ResultMapAsyncSequence<Self, Result<Success, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapAsyncSequence(self) { element in
            await element.tapErrorAsync(action)
        }
    }

    // MARK: Cancellation

    /// Ends the sequence with one `.failure(error)` when the task that reads it is cancelled.
    ///
    /// In a cancelled task, many sequences end early instead of throwing: `AsyncStream` and the
    /// concurrent maps return `nil`. A sink that reads to the end, like `toResult()`, then gives
    /// a partial result that looks complete. Put this before the sink to get a failure instead.
    ///
    /// It checks for cancellation before each read and when `Base` ends. If the task is
    /// cancelled, it gives `.failure(error)` and ends, and does not read `Base` again. Otherwise
    /// it passes every element through.
    ///
    /// It can't tell a sequence that ended because of the cancellation from one that ended
    /// just before it, so it gives the failure in both cases. Inside
    /// `withTaskCancellationShield`, the task does not look cancelled, so it passes every
    /// element through.
    ///
    /// ```swift
    /// let users = await ids.mapAsyncOrdered(concurrency: 8) { id in
    ///     await loadUser(id)
    /// }
    /// .failOnCancellation(with: .cancelled)
    /// .toResult()  // .failure(.cancelled) in a cancelled task
    /// ```
    @inlinable
    func failOnCancellation<Success, Failure>(
        with error: Failure
    ) -> FailOnCancellationSequence<Self>
    where Element == Result<Success, Failure> {
        FailOnCancellationSequence(self, failure: .failure(error))
    }
}
