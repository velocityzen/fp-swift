// MARK: - Optional Match Extensions
public extension Optional {
    /// Returns `onSome(value)` if there is a value, or `onNone` if it is `nil`.
    @discardableResult
    @inlinable
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

    /// Returns `onSome(value)` if there is a value, or `onNone` if it is `nil`. `onSome` is async.
    @discardableResult
    @inlinable
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
