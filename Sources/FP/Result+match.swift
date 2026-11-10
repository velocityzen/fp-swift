public extension Result {
    /// Returns `onSuccess(value)` on success, or `onFailure(error)` on failure.
    @discardableResult
    @inlinable
    func match<T>(
        _ onSuccess: (Success) -> T,
        _ onFailure: (Failure) -> T
    ) -> T {
        switch self {
            case .success(let value):
                return onSuccess(value)
            case .failure(let error):
                return onFailure(error)
        }
    }

    /// Returns `onSuccess(value)` on success, or `failure` on failure.
    @discardableResult
    @inlinable
    func match<T>(
        _ onSuccess: (Success) -> T,
        _ failure: @autoclosure () -> T
    ) -> T {
        switch self {
            case .success(let value):
                return onSuccess(value)
            case .failure:
                return failure()
        }
    }

    /// Returns `success` on success, or `onFailure(error)` on failure.
    @discardableResult
    @inlinable
    func match<T>(
        _ success: @autoclosure () -> T,
        _ onFailure: (Failure) -> T
    ) -> T {
        switch self {
            case .success:
                return success()
            case .failure(let error):
                return onFailure(error)
        }
    }

    /// Returns `success` on success, or `failure` on failure.
    @discardableResult
    @inlinable
    func match<T>(
        _ success: @autoclosure () -> T,
        _ failure: @autoclosure () -> T
    ) -> T {
        switch self {
            case .success:
                return success()
            case .failure:
                return failure()
        }
    }

    /// Returns `onSuccess(value)` on success, or `onFailure(error)` on failure. Both are async.
    @discardableResult
    @inlinable
    func matchAsync<T>(
        _ onSuccess: (Success) async -> T,
        _ onFailure: (Failure) async -> T
    ) async -> T {
        switch self {
            case .success(let value):
                return await onSuccess(value)
            case .failure(let error):
                return await onFailure(error)
        }
    }

    /// Returns `onSuccess(value)` on success, or `failure` on failure. `onSuccess` is async.
    @discardableResult
    @inlinable
    func matchAsync<T>(
        _ onSuccess: (Success) async -> T,
        _ failure: @autoclosure () -> T
    ) async -> T {
        switch self {
            case .success(let value):
                return await onSuccess(value)
            case .failure:
                return failure()
        }
    }

    /// Returns `success` on success, or `onFailure(error)` on failure. `onFailure` is async.
    @discardableResult
    @inlinable
    func matchAsync<T>(
        _ success: @autoclosure () -> T,
        _ onFailure: (Failure) async -> T
    ) async -> T {
        switch self {
            case .success:
                return success()
            case .failure(let error):
                return await onFailure(error)
        }
    }
}
