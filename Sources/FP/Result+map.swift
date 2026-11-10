public extension Result {
    /// Maps the success value with an async transform.
    @inlinable
    func mapAsync<T>(
        _ transform: (Success) async -> T
    ) async -> Result<T, Failure> {
        switch self {
            case .success(let value):
                let newValue = await transform(value)
                return .success(newValue)
            case .failure(let error):
                return .failure(error)
        }
    }

    /// Maps the success value with an async transform. A thrown error becomes the failure.
    @inlinable
    func mapAsync<T>(
        _ transform: (Success) async throws -> T
    ) async -> Result<T, Error> where Failure == Error {
        switch self {
            case .success(let value):
                do {
                    let newValue = try await transform(value)
                    return .success(newValue)
                } catch {
                    return .failure(error)
                }
            case .failure(let error):
                return .failure(error)
        }
    }

    /// Maps the error with an async transform.
    @inlinable
    func mapErrorAsync<E: Error>(
        _ transform: (Failure) async -> E
    ) async -> Result<Success, E> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let error):
                let newError = await transform(error)
                return .failure(newError)
        }
    }

    /// Chains an async transform that returns a `Result`.
    @inlinable
    func flatMapAsync<T>(
        _ transform: (Success) async -> Result<T, Failure>
    ) async -> Result<T, Failure> {
        switch self {
            case .success(let value):
                return await transform(value)
            case .failure(let error):
                return .failure(error)
        }
    }

    /// Replaces the success value with `value`.
    @inlinable
    func `as`<T>(_ value: T) -> Result<T, Failure> {
        map { _ in value }
    }

    /// Replaces the success value with `()`.
    @inlinable
    func asUnit() -> Result<Void, Failure> {
        map { _ in () }
    }
}

// MARK: - Additional Convenience Methods
public extension Result where Failure == Error {
    /// Creates a `Result` from an async throwing operation.
    @inlinable
    static func fromAsync(
        _ operation: () async throws -> Success
    ) async -> Result<Success, Error> {
        do {
            let value = try await operation()
            return .success(value)
        } catch {
            return .failure(error)
        }
    }
}
