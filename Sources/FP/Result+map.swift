import Foundation

public extension Result {
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
}

// MARK: - Additional Convenience Methods
public extension Result where Failure == Error {
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
