/**
 * Result+IO - Functional Extensions for Result Type
 *
 * ARCHITECTURAL PATTERN:
 * Use `.tap()` methods to perform side effects while keeping the Result chain flowing.
 * This enables functional-style error handling with clear success/failure paths.
 *
 * Usage:
 *   someOperation()
 *       .tap { value in saveToCache(value) }
 *       .tapAsync { value in await sendAnalytics(value) }
 *       .map { value in transform(value) }
 *
 * Variants:
 * - `.tap()` - Sync side effect, keeps Result unchanged
 * - `.tapAsync()` - Async side effect, keeps Result unchanged
 * - Throwing variants convert Failure type to Error
 *
 * See CLAUDE.md "Code Hygiene Patterns > Functional Result Extensions"
 */
import Foundation

public extension Result {

    // MARK: Sync taps

    /// Performs a side effect with the success value, returning the original Result unchanged.
    func tap(
        _ action: (Success) -> Void
    ) -> Result<Success, Failure> {
        if case .success(let value) = self {
            action(value)
        }
        return self
    }

    /// Performs a side effect with the success value, discarding the action's return value.
    func tap<T>(
        _ action: (Success) -> T
    ) -> Result<Success, Failure> {
        if case .success(let value) = self {
            let _ = action(value)
        }
        return self
    }

    /// Performs a throwing side effect, converting thrown errors to failure.
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
    func tapAsync(
        _ action: (Success) async -> Void
    ) async -> Result<Success, Failure> {
        if case .success(let value) = self {
            await action(value)
        }
        return self
    }

    /// Asynchronously performs a side effect, discarding the action's return value.
    func tapAsync<T>(
        _ action: (Success) async -> T
    ) async -> Result<Success, Failure> {
        if case .success(let value) = self {
            let _ = await action(value)
        }
        return self
    }

    /// Asynchronously performs a throwing side effect, converting thrown errors to failure.
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
    func tapError(
        _ action: (Failure) -> Void
    ) -> Result<Success, Failure> {
        if case .failure(let error) = self {
            action(error)
        }
        return self
    }

    /// Performs a side effect with the failure value, discarding the action's return value.
    func tapError<T>(
        _ action: (Failure) -> T
    ) -> Result<Success, Failure> {
        if case .failure(let error) = self {
            let _ = action(error)
        }
        return self
    }

    /// Performs a throwing side effect on failure, converting thrown errors to failure.
    func tapError(
        _ action: (Failure) throws -> Void
    ) -> Result<Success, Error> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let error):
                do {
                    try action(error)
                    return .failure(error)
                } catch {
                    return .failure(error)
                }
        }
    }

    /// Performs a throwing side effect on failure, discarding the return value.
    func tapError<T>(
        _ action: (Failure) throws -> T
    ) -> Result<Success, Error> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let error):
                do {
                    let _ = try action(error)
                    return .failure(error)
                } catch {
                    return .failure(error)
                }
        }
    }

    /// Performs a Result-returning side effect on failure, propagating the original error.
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
    func tapErrorAsync(
        _ action: (Failure) async -> Void
    ) async -> Result<Success, Failure> {
        if case .failure(let error) = self {
            await action(error)
        }
        return self
    }

    /// Asynchronously performs a side effect on failure, discarding the action's return value.
    func tapErrorAsync<T>(
        _ action: (Failure) async -> T
    ) async -> Result<Success, Failure> {
        if case .failure(let error) = self {
            let _ = await action(error)
        }
        return self
    }

    /// Asynchronously performs a throwing side effect on failure.
    func tapErrorAsync(
        _ action: (Failure) async throws -> Void
    ) async -> Result<Success, Error> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let error):
                do {
                    try await action(error)
                    return .failure(error)
                } catch {
                    return .failure(error)
                }
        }
    }

    /// Asynchronously performs a throwing side effect on failure, discarding the return value.
    func tapErrorAsync<T>(
        _ action: (Failure) async throws -> T
    ) async -> Result<Success, Error> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let error):
                do {
                    let _ = try await action(error)
                    return .failure(error)
                } catch {
                    return .failure(error)
                }
        }
    }

    /// Asynchronously performs a Result-returning side effect on failure.
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
    func finally(_ action: () -> Void) -> Result<Success, Failure> {
        action()
        return self
    }

    /// Asynchronous variant of ``finally(_:)``.
    func finallyAsync(_ action: () async -> Void) async -> Result<Success, Failure> {
        await action()
        return self
    }
}
