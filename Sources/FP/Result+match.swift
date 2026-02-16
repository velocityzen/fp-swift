import Foundation

public extension Result {
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
