// MARK: - Optional Match Extensions
public extension Optional {
    /// Folds the Optional by applying one of two functions depending on some or none.
    @discardableResult
    func match<T>(
        _ onSome: (Wrapped) -> T,
        _ onNone: @autoclosure () -> T
    ) -> T {
        switch self {
            case .some(let value):
                return onSome(value)
            case .none:
                return onNone()
        }
    }

    /// Asynchronously folds the Optional, using an async function for some and a default for none.
    @discardableResult
    func matchAsync<T>(
        _ onSome: (Wrapped) async -> T,
        _ onNone: @autoclosure () -> T
    ) async -> T {
        switch self {
            case .some(let value):
                return await onSome(value)
            case .none:
                return onNone()
        }
    }
}
