import Foundation

public extension Result {
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

}
