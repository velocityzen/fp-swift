/*
 * Result+tap: side effects in a Result chain.
 *
 * `tap` and `tapError` run an action and pass the Result on unchanged:
 *
 *   someOperation()
 *       .tap { value in saveToCache(value) }
 *       .tapAsync { value in await sendAnalytics(value) }
 *       .map { value in transform(value) }
 *
 * If the action throws or returns a failure, that error becomes the new failure. Throwing
 * actions change the failure type to `Error`.
 */
public extension Result {

    // MARK: Sync taps

    /// Runs `action` on success. Returns the result unchanged.
    @inlinable
    func tap(
        _ action: (Success) -> Void
    ) -> Result<Success, Failure> {
        if case .success(let value) = self {
            action(value)
        }
        return self
    }

    /// Runs `action` on success and ignores what it returns.
    @inlinable
    func tap<T>(
        _ action: (Success) -> T
    ) -> Result<Success, Failure> {
        if case .success(let value) = self {
            let _ = action(value)
        }
        return self
    }

    /// Runs a throwing `action` on success. A thrown error becomes the failure.
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

    /// Runs a throwing `action` on success and ignores what it returns. A thrown error becomes
    /// the failure.
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

    /// Runs `action` on success. If `action` fails, its failure is the result.
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

    /// Runs `action` on success and ignores its value. If `action` fails, its failure is the
    /// result.
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

    /// Runs an async `action` on success. Returns the result unchanged.
    @inlinable
    func tapAsync(
        _ action: (Success) async -> Void
    ) async -> Result<Success, Failure> {
        if case .success(let value) = self {
            await action(value)
        }
        return self
    }

    /// Runs an async `action` on success and ignores what it returns.
    @inlinable
    func tapAsync<T>(
        _ action: (Success) async -> T
    ) async -> Result<Success, Failure> {
        if case .success(let value) = self {
            let _ = await action(value)
        }
        return self
    }

    /// Runs an async throwing `action` on success. A thrown error becomes the failure.
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

    /// Runs an async throwing `action` on success and ignores what it returns. A thrown error
    /// becomes the failure.
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

    /// Runs an async `action` on success. If `action` fails, its failure is the result.
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

    /// Runs an async `action` on success and ignores its value. If `action` fails, its failure
    /// is the result.
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

    /// Runs `action` on failure. Returns the result unchanged.
    @inlinable
    func tapError(
        _ action: (Failure) -> Void
    ) -> Result<Success, Failure> {
        if case .failure(let error) = self {
            action(error)
        }
        return self
    }

    /// Runs `action` on failure and ignores what it returns.
    @inlinable
    func tapError<T>(
        _ action: (Failure) -> T
    ) -> Result<Success, Failure> {
        if case .failure(let error) = self {
            let _ = action(error)
        }
        return self
    }

    /// Runs a throwing `action` on failure. A thrown error replaces the failure.
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

    /// Runs a throwing `action` on failure and ignores what it returns. A thrown error replaces
    /// the failure.
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

    /// Runs `action` on failure. If `action` fails, its failure replaces the original one.
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

    /// Runs an async `action` on failure. Returns the result unchanged.
    @inlinable
    func tapErrorAsync(
        _ action: (Failure) async -> Void
    ) async -> Result<Success, Failure> {
        if case .failure(let error) = self {
            await action(error)
        }
        return self
    }

    /// Runs an async `action` on failure and ignores what it returns.
    @inlinable
    func tapErrorAsync<T>(
        _ action: (Failure) async -> T
    ) async -> Result<Success, Failure> {
        if case .failure(let error) = self {
            let _ = await action(error)
        }
        return self
    }

    /// Runs an async throwing `action` on failure. A thrown error replaces the failure.
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

    /// Runs an async throwing `action` on failure and ignores what it returns. A thrown error
    /// replaces the failure.
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

    /// Runs an async `action` on failure. If `action` fails, its failure replaces the original
    /// one.
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

    /// Runs `action` on success and on failure. Returns the result unchanged.
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

    /// Async version of ``finally(_:)``.
    ///
    /// In a cancelled task, `action` sees the cancellation. To let a cleanup finish anyway, run
    /// it in `withTaskCancellationShield`.
    @inlinable
    func finallyAsync(_ action: () async -> Void) async -> Result<Success, Failure> {
        await action()
        return self
    }
}
