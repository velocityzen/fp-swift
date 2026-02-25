import Foundation

public extension Result {
    /// Folds the Result by applying one of two functions depending on success or failure.
    @discardableResult
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

    /// Folds the Result, using a function for success and a default value for failure.
    @discardableResult
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

    /// Folds the Result, using a default value for success and a function for failure.
    @discardableResult
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

    /// Folds the Result using default values for both success and failure.
    @discardableResult
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

    /// Asynchronously folds the Result by applying one of two async functions.
    @discardableResult
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

    /// Asynchronously folds the Result, using an async function for success and a default for failure.
    @discardableResult
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

    /// Asynchronously folds the Result, using a default for success and an async function for failure.
    @discardableResult
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
