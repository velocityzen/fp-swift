// MARK: - AsyncSequence Extensions for Result

public extension AsyncSequence {
    /// Returns an async sequence of only the success values.
    func successes<Success, Failure>()
        -> AsyncCompactMapSequence<Self, Success>
    where Element == Result<Success, Failure> {
        compactMap { element in
            if case .success(let value) = element { return value }
            return nil
        }
    }

    /// Returns an async sequence of only the failure errors.
    func failures<Success, Failure>()
        -> AsyncCompactMapSequence<Self, Failure>
    where Element == Result<Success, Failure> {
        compactMap { element in
            if case .failure(let error) = element { return error }
            return nil
        }
    }

    // MARK: Map

    /// Transforms the success values, preserving failures.
    func map<Success, Failure, T>(
        _ transform: @Sendable @escaping (Success) -> T
    ) -> AsyncMapSequence<Self, Result<T, Failure>>
    where Element == Result<Success, Failure> {
        map { element in
            element.map(transform)
        }
    }

    /// Asynchronously transforms the success values, preserving failures.
    func mapAsync<Success, Failure, T>(
        _ transform: @Sendable @escaping (Success) async -> T
    ) -> AsyncMapSequence<Self, Result<T, Failure>>
    where Element == Result<Success, Failure> {
        map { element in
            await element.mapAsync(transform)
        }
    }

    /// Transforms the failure errors, preserving successes.
    func mapError<Success, Failure, E>(
        _ transform: @Sendable @escaping (Failure) -> E
    ) -> AsyncMapSequence<Self, Result<Success, E>>
    where Element == Result<Success, Failure> {
        map { element in
            element.mapError(transform)
        }
    }

    /// Asynchronously transforms the failure errors, preserving successes.
    func mapErrorAsync<Success, Failure, E: Error>(
        _ transform: @Sendable @escaping (Failure) async -> E
    ) -> AsyncMapSequence<Self, Result<Success, E>>
    where Element == Result<Success, Failure> {
        map { element in
            await element.mapErrorAsync(transform)
        }
    }

    // MARK: FlatMap

    /// Transforms the success values with a Result-returning closure.
    func flatMap<Success, Failure, T>(
        _ transform: @Sendable @escaping (Success) -> Result<T, Failure>
    ) -> AsyncMapSequence<Self, Result<T, Failure>>
    where Element == Result<Success, Failure> {
        map { element in
            element.flatMap(transform)
        }
    }

    /// Asynchronously transforms the success values with a Result-returning closure.
    func flatMapAsync<Success, Failure, T>(
        _ transform: @Sendable @escaping (Success) async -> Result<T, Failure>
    ) -> AsyncMapSequence<Self, Result<T, Failure>>
    where Element == Result<Success, Failure> {
        map { element in
            await element.flatMapAsync(transform)
        }
    }

    // MARK: Tap

    /// Performs a side effect on success values, passing through all Results unchanged.
    func tap<Success, Failure>(
        _ action: @Sendable @escaping (Success) -> Void
    ) -> AsyncMapSequence<Self, Result<Success, Failure>>
    where Element == Result<Success, Failure> {
        map { element in
            element.tap(action)
        }
    }

    /// Asynchronously performs a side effect on success values, passing through all Results unchanged.
    func tapAsync<Success, Failure>(
        _ action: @Sendable @escaping (Success) async -> Void
    ) -> AsyncMapSequence<Self, Result<Success, Failure>>
    where Element == Result<Success, Failure> {
        map { element in
            await element.tapAsync(action)
        }
    }

    // MARK: TapError

    /// Performs a side effect on failure errors, passing through all Results unchanged.
    func tapError<Success, Failure>(
        _ action: @Sendable @escaping (Failure) -> Void
    ) -> AsyncMapSequence<Self, Result<Success, Failure>>
    where Element == Result<Success, Failure> {
        map { element in
            element.tapError(action)
        }
    }

    /// Asynchronously performs a side effect on failure errors, passing through all Results unchanged.
    func tapErrorAsync<Success, Failure>(
        _ action: @Sendable @escaping (Failure) async -> Void
    ) -> AsyncMapSequence<Self, Result<Success, Failure>>
    where Element == Result<Success, Failure> {
        map { element in
            await element.tapErrorAsync(action)
        }
    }
}
