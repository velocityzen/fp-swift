/*
 * Result+tap - Side Effects for Result Chains
 *
 * Use `.tap()` / `.tapError()` to perform side effects while keeping the
 * Result chain flowing:
 *
 *   someOperation()
 *       .tap { value in saveToCache(value) }
 *       .tapAsync { value in await sendAnalytics(value) }
 *       .map { value in transform(value) }
 *
 * Variants:
 * - `.tap()` / `.tapError()` - Sync side effect, keeps Result unchanged
 * - `.tapAsync()` / `.tapErrorAsync()` - Async side effect, keeps Result unchanged
 * - Throwing variants convert Failure type to Error; if the action throws,
 *   the thrown error becomes the failure (replacing the original failure in
 *   the tapError case)
 * - Result-returning variants propagate the action's failure
 */
public extension Result {

    // MARK: Sync taps

    /// Performs a side effect with the success value, returning the original Result unchanged.
    @inlinable
    func tap(
        _ action: (Success) -> Void
    ) -> Result<Success, Failure> {
        if case .success(let value) = self {
            action(value)
        }
        return self
    }

    /// Performs a side effect with the success value, discarding the action's return value.
    @inlinable
    func tap<T>(
        _ action: (Success) -> T
    ) -> Result<Success, Failure> {
        if case .success(let value) = self {
            let _ = action(value)
        }
        return self
    }

    /// Performs a throwing side effect, converting thrown errors to failure.
    @inlinable
    func tap(
        _ action: (Success) throws -> Void
    ) -> Result<Success, Error> {
        switch self {
            case .success(let value):
                do {
                    try action(value)
                    return .success(value)
                } catch {
                    return .failure(error)
                }
            case .failure(let error):
                return .failure(error)
        }
    }

    /// Performs a throwing side effect, discarding the return value and converting thrown errors to failure.
    @inlinable
    func tap<T>(
        _ action: (Success) throws -> T
    ) -> Result<Success, Error> {
        switch self {
            case .success(let value):
                do {
                    let _ = try action(value)
                    return .success(value)
                } catch {
                    return .failure(error)
                }
            case .failure(let error):
                return .failure(error)
        }
    }

    /// Performs a Result-returning side effect, propagating its failure if it fails.
    @inlinable
    func tap(
        _ action: (Success) -> Result<Void, Failure>
    ) -> Result<Success, Failure> {
        switch self {
            case .success(let value):
                return action(value).map { value }
            case .failure(let error):
                return .failure(error)
        }
    }

    /// Performs a Result-returning side effect, discarding its success value and propagating failure.
    @inlinable
    func tap<T>(
        _ action: (Success) -> Result<T, Failure>
    ) -> Result<Success, Failure> {
        switch self {
            case .success(let value):
                return action(value).map { _ in value }
            case .failure(let error):
                return .failure(error)
        }
    }

    // MARK: Async taps

    /// Asynchronously performs a side effect with the success value.
    @inlinable
    func tapAsync(
        _ action: (Success) async -> Void
    ) async -> Result<Success, Failure> {
        if case .success(let value) = self {
            await action(value)
        }
        return self
    }

    /// Asynchronously performs a side effect, discarding the action's return value.
    @inlinable
    func tapAsync<T>(
        _ action: (Success) async -> T
    ) async -> Result<Success, Failure> {
        if case .success(let value) = self {
            let _ = await action(value)
        }
        return self
    }

    /// Asynchronously performs a throwing side effect, converting thrown errors to failure.
    @inlinable
    func tapAsync(
        _ action: (Success) async throws -> Void
    ) async -> Result<Success, Error> {
        switch self {
            case .success(let value):
                do {
                    try await action(value)
                    return .success(value)
                } catch {
                    return .failure(error)
                }
            case .failure(let error):
                return .failure(error)
        }
    }

    /// Asynchronously performs a throwing side effect, discarding the return value.
    @inlinable
    func tapAsync<T>(
        _ action: (Success) async throws -> T
    ) async -> Result<Success, Error> {
        switch self {
            case .success(let value):
                do {
                    let _ = try await action(value)
                    return .success(value)
                } catch {
                    return .failure(error)
                }
            case .failure(let error):
                return .failure(error)
        }
    }

    /// Asynchronously performs a Result-returning side effect, propagating its failure.
    @inlinable
    func tapAsync(
        _ action: (Success) async -> Result<Void, Failure>
    ) async -> Result<Success, Failure> {
        switch self {
            case .success(let value):
                return await action(value).map { value }
            case .failure(let error):
                return .failure(error)
        }
    }

    /// Asynchronously performs a Result-returning side effect, discarding its success value.
    @inlinable
    func tapAsync<T>(
        _ action: (Success) async -> Result<T, Failure>
    ) async -> Result<Success, Failure> {
        switch self {
            case .success(let value):
                return await action(value).map { _ in value }
            case .failure(let error):
                return .failure(error)
        }
    }

    // MARK: Sync tapError

    /// Performs a side effect with the failure value, returning the original Result unchanged.
    @inlinable
    func tapError(
        _ action: (Failure) -> Void
    ) -> Result<Success, Failure> {
        if case .failure(let error) = self {
            action(error)
        }
        return self
    }

    /// Performs a side effect with the failure value, discarding the action's return value.
    @inlinable
    func tapError<T>(
        _ action: (Failure) -> T
    ) -> Result<Success, Failure> {
        if case .failure(let error) = self {
            let _ = action(error)
        }
        return self
    }

    /// Performs a throwing side effect on failure. If the action throws, the
    /// thrown error replaces the original failure.
    @inlinable
    func tapError(
        _ action: (Failure) throws -> Void
    ) -> Result<Success, Error> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let originalError):
                do {
                    try action(originalError)
                    return .failure(originalError)
                } catch let thrownError {
                    return .failure(thrownError)
                }
        }
    }

    /// Performs a throwing side effect on failure, discarding the return value.
    /// If the action throws, the thrown error replaces the original failure.
    @inlinable
    func tapError<T>(
        _ action: (Failure) throws -> T
    ) -> Result<Success, Error> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let originalError):
                do {
                    let _ = try action(originalError)
                    return .failure(originalError)
                } catch let thrownError {
                    return .failure(thrownError)
                }
        }
    }

    /// Performs a Result-returning side effect on failure. If the action
    /// succeeds, the original failure is preserved; if the action fails, its
    /// failure replaces the original.
    @inlinable
    func tapError<T>(
        _ action: (Failure) -> Result<T, Failure>
    ) -> Result<Success, Failure> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let error):
                return action(error).flatMap { _ in
                    .failure(error)
                }
        }
    }

    // MARK: Async tapError

    /// Asynchronously performs a side effect with the failure value.
    @inlinable
    func tapErrorAsync(
        _ action: (Failure) async -> Void
    ) async -> Result<Success, Failure> {
        if case .failure(let error) = self {
            await action(error)
        }
        return self
    }

    /// Asynchronously performs a side effect on failure, discarding the action's return value.
    @inlinable
    func tapErrorAsync<T>(
        _ action: (Failure) async -> T
    ) async -> Result<Success, Failure> {
        if case .failure(let error) = self {
            let _ = await action(error)
        }
        return self
    }

    /// Asynchronously performs a throwing side effect on failure. If the
    /// action throws, the thrown error replaces the original failure.
    @inlinable
    func tapErrorAsync(
        _ action: (Failure) async throws -> Void
    ) async -> Result<Success, Error> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let originalError):
                do {
                    try await action(originalError)
                    return .failure(originalError)
                } catch let thrownError {
                    return .failure(thrownError)
                }
        }
    }

    /// Asynchronously performs a throwing side effect on failure, discarding
    /// the return value. If the action throws, the thrown error replaces the
    /// original failure.
    @inlinable
    func tapErrorAsync<T>(
        _ action: (Failure) async throws -> T
    ) async -> Result<Success, Error> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let originalError):
                do {
                    let _ = try await action(originalError)
                    return .failure(originalError)
                } catch let thrownError {
                    return .failure(thrownError)
                }
        }
    }

    /// Asynchronously performs a Result-returning side effect on failure. If
    /// the action succeeds, the original failure is preserved; if the action
    /// fails, its failure replaces the original.
    @inlinable
    func tapErrorAsync<T>(
        _ action: (Failure) async -> Result<T, Failure>
    ) async -> Result<Success, Failure> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let error):
                return await action(error).flatMap { _ in
                    .failure(error)
                }
        }
    }

    // MARK: Finally

    /// Performs a side effect regardless of success or failure, returning self
    /// unchanged. Useful for cleanup, logging, or metrics that should run no
    /// matter the outcome.
    ///
    /// ```swift
    /// fetchUser(id: 1)
    ///     .tap { user in cache.store(user) }
    ///     .tapError { error in logger.error("\(error)") }
    ///     .finally { metrics.record(.requestComplete) }
    /// ```
    @inlinable
    func finally(_ action: () -> Void) -> Result<Success, Failure> {
        action()
        return self
    }

    /// Asynchronous variant of ``finally(_:)``.
    @inlinable
    func finallyAsync(_ action: () async -> Void) async -> Result<Success, Failure> {
        await action()
        return self
    }
}
