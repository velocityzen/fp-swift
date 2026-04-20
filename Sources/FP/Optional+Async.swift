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

    /// Returns `self` if it's `.some`; otherwise returns the alternative.
    /// The alternative is only evaluated when `self` is nil.
    ///
    /// Mirrors fp-ts `Option.orElse`: the left-most `.some` wins, and the
    /// alternative is chained only when `self` is `.none`.
    ///
    /// ```swift
    /// let name = cachedName.orElse(fetchName())
    /// ```
    func orElse(_ alternative: @autoclosure () -> Wrapped?) -> Wrapped? {
        switch self {
            case .some:
                return self
            case .none:
                return alternative()
        }
    }

    /// Asynchronous variant of ``orElse(_:)``.
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

    /// Returns the wrapped value, or a default if `self` is nil.
    /// The default is only evaluated when `self` is nil.
    ///
    /// Mirrors fp-ts `Option.getOrElse`. Equivalent to Swift's `??` operator.
    ///
    /// ```swift
    /// let count = parsed.getOrElse(0)
    /// ```
    func getOrElse(_ defaultValue: @autoclosure () -> Wrapped) -> Wrapped {
        switch self {
            case .some(let value):
                return value
            case .none:
                return defaultValue()
        }
    }

    /// Asynchronous variant of ``getOrElse(_:)``.
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
}
