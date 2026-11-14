// MARK: - Optional Async Extensions
public extension Optional {
    /// Transforms the wrapped value, if there is one, with an async closure.
    @inlinable
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

    /// Transforms the wrapped value, if there is one, with an async closure that
    /// returns an optional.
    @inlinable
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

    /// Returns `self` if it has a value, or else `alternative`.
    ///
    /// `alternative` runs only when `self` is nil.
    ///
    /// ```swift
    /// let name = cachedName.orElse(fetchName())
    /// ```
    @inlinable
    func orElse(_ alternative: @autoclosure () -> Wrapped?) -> Wrapped? {
        switch self {
            case .some:
                return self
            case .none:
                return alternative()
        }
    }

    /// Returns `self` if it has a value, or else awaits `alternative`.
    @inlinable
    func orElseAsync(
        _ alternative: @autoclosure @escaping () async -> Wrapped?
    ) async -> Wrapped? {
        switch self {
            case .some:
                return self
            case .none:
                return await alternative()
        }
    }

    /// Returns the wrapped value, or `defaultValue` if `self` is nil.
    ///
    /// It works like `??`: `defaultValue` runs only when `self` is nil.
    @inlinable
    func getOrElse(_ defaultValue: @autoclosure () -> Wrapped) -> Wrapped {
        switch self {
            case .some(let value):
                return value
            case .none:
                return defaultValue()
        }
    }

    /// Returns the wrapped value, or awaits `defaultValue` if `self` is nil.
    @inlinable
    func getOrElseAsync(
        _ defaultValue: @autoclosure @escaping () async -> Wrapped
    ) async -> Wrapped {
        switch self {
            case .some(let value):
                return value
            case .none:
                return await defaultValue()
        }
    }

    /// Runs `action` whether or not `self` has a value, and returns `self`
    /// unchanged.
    @inlinable
    func finally(_ action: () -> Void) -> Wrapped? {
        action()
        return self
    }

    /// Awaits `action`, and returns `self` unchanged.
    ///
    /// In a cancelled task, `action` sees the cancellation. To let a cleanup
    /// finish anyway, run it in `withTaskCancellationShield`.
    @inlinable
    func finallyAsync(_ action: () async -> Void) async -> Wrapped? {
        await action()
        return self
    }
}
