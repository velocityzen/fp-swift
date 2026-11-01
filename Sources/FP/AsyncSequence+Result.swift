// MARK: - AsyncSequence Extensions for Result

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

    /// Returns an async sequence of only the failure errors.
    @inlinable
    func failures<Success, Failure>()
        -> ResultCompactMapSequence<Self, Failure>
    where Element == Result<Success, Failure> {
        ResultCompactMapSequence(self) { element in
            if case .failure(let error) = element { return error }
            return nil
        }
    }

    // MARK: Map

    /// Transforms the success values, preserving failures.
    @inlinable
    func map<Success, Failure, T>(
        _ transform: @Sendable @escaping (Success) -> T
    ) -> ResultMapSequence<Self, Result<T, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapSequence(self) { element in
            element.map(transform)
        }
    }

    /// Asynchronously transforms the success values, preserving failures.
    @inlinable
    func mapAsync<Success, Failure, T>(
        _ transform: @Sendable @escaping (Success) async -> T
    ) -> ResultMapAsyncSequence<Self, Result<T, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapAsyncSequence(self) { element in
            await element.mapAsync(transform)
        }
    }

    /// Transforms the failure errors, preserving successes.
    @inlinable
    func mapError<Success, Failure, E>(
        _ transform: @Sendable @escaping (Failure) -> E
    ) -> ResultMapSequence<Self, Result<Success, E>>
    where Element == Result<Success, Failure> {
        ResultMapSequence(self) { element in
            element.mapError(transform)
        }
    }

    /// Asynchronously transforms the failure errors, preserving successes.
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

    /// Transforms the success values with a Result-returning closure.
    @inlinable
    func flatMap<Success, Failure, T>(
        _ transform: @Sendable @escaping (Success) -> Result<T, Failure>
    ) -> ResultMapSequence<Self, Result<T, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapSequence(self) { element in
            element.flatMap(transform)
        }
    }

    /// Asynchronously transforms the success values with a Result-returning closure.
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

    /// Performs a side effect on success values, passing through all Results unchanged.
    @inlinable
    func tap<Success, Failure>(
        _ action: @Sendable @escaping (Success) -> Void
    ) -> ResultMapSequence<Self, Result<Success, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapSequence(self) { element in
            element.tap(action)
        }
    }

    /// Asynchronously performs a side effect on success values, passing through all Results unchanged.
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

    /// Performs a side effect on failure errors, passing through all Results unchanged.
    @inlinable
    func tapError<Success, Failure>(
        _ action: @Sendable @escaping (Failure) -> Void
    ) -> ResultMapSequence<Self, Result<Success, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapSequence(self) { element in
            element.tapError(action)
        }
    }

    /// Asynchronously performs a side effect on failure errors, passing through all Results unchanged.
    @inlinable
    func tapErrorAsync<Success, Failure>(
        _ action: @Sendable @escaping (Failure) async -> Void
    ) -> ResultMapAsyncSequence<Self, Result<Success, Failure>>
    where Element == Result<Success, Failure> {
        ResultMapAsyncSequence(self) { element in
            await element.tapErrorAsync(action)
        }
    }
}
