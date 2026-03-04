// MARK: - Optional Async Extensions
public extension Optional {
    /// Asynchronously transforms the wrapped value, returning nil if the optional is empty.
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

    /// Asynchronously transforms the wrapped value to another optional value and flattens the result.
    func flatMapAsync<T>(
        _ transform: (Wrapped) async -> T?
    ) async -> T? {
        switch self {
            case .some(let value):
                return await transform(value)
            case .none:
                return nil
        }
    }

    /// Returns the default value when nil, or nil when the optional has a value.
    func orElse<T>(_ defaultValue: T) -> T? {
        switch self {
            case .some:
                return nil
            case .none:
                return defaultValue
        }
    }
}
