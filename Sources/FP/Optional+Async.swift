// MARK: - Optional Async Extensions
public extension Optional {
    func mapAsync<T>(
        _ transform: (Wrapped) async -> T
    ) async -> T? {
        switch self {
            case .some(let value):
                return await transform(value)
            case .none:
                return nil
        }
    }

    func mapAsync<T>(
        _ transform: (Wrapped) async throws -> T
    ) async rethrows -> T? {
        switch self {
            case .some(let value):
                return try await transform(value)
            case .none:
                return nil
        }
    }

    func orElse<T>(_ defaultValue: T) -> T? {
        switch self {
            case .some:
                return nil
            case .none:
                return defaultValue
        }
    }
}
