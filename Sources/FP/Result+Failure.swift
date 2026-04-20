import Foundation

public extension Result {
    /// Returns `self` if it's a success; otherwise returns the alternative.
    /// The alternative is only evaluated on failure.
    ///
    /// Mirrors fp-ts `Either.alt`: the left-most success wins, but if both
    /// sides are failures the alternative's failure is returned.
    ///
    /// ```swift
    /// fetchUser(id: 1).alt { fetchUserFromCache(id: 1) }
    /// ```
    func alt(_ alternative: () -> Result<Success, Failure>) -> Result<Success, Failure> {
        switch self {
            case .success:
                return self
            case .failure:
                return alternative()
        }
    }

    /// Asynchronous variant of ``alt(_:)``.
    func altAsync(
        _ alternative: () async -> Result<Success, Failure>
    ) async -> Result<Success, Failure> {
        switch self {
            case .success:
                return self
            case .failure:
                return await alternative()
        }
    }

    /// Returns `self` if it's a success; otherwise computes a recovery `Result`
    /// from the failure. The recovery may change the `Failure` type.
    ///
    /// Mirrors fp-ts `Either.orElse`. Unlike ``alt(_:)``, the recovery receives
    /// the failure value and can transform the error type.
    ///
    /// ```swift
    /// fetchUser(id: 1).orElse { error in
    ///     error is Timeout ? fetchUser(id: 1) : .failure(AppError.wrap(error))
    /// }
    /// ```
    func orElse<NewFailure>(
        _ onFailure: (Failure) -> Result<Success, NewFailure>
    ) -> Result<Success, NewFailure> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let error):
                return onFailure(error)
        }
    }

    /// Asynchronous variant of ``orElse(_:)``.
    func orElseAsync<NewFailure>(
        _ onFailure: (Failure) async -> Result<Success, NewFailure>
    ) async -> Result<Success, NewFailure> {
        switch self {
            case .success(let value):
                return .success(value)
            case .failure(let error):
                return await onFailure(error)
        }
    }

    /// Returns the success value, or computes a fallback from the failure.
    ///
    /// Mirrors fp-ts `Either.getOrElse`. Unlike ``alt(_:)``, the fallback
    /// returns an unwrapped `Success` rather than another `Result`.
    ///
    /// ```swift
    /// let count = parse(input).getOrElse { _ in 0 }
    /// ```
    func getOrElse(_ onFailure: (Failure) -> Success) -> Success {
        switch self {
            case .success(let value):
                return value
            case .failure(let error):
                return onFailure(error)
        }
    }

    /// Returns the success value, or a default value if it's a failure.
    /// The default is only evaluated on failure.
    ///
    /// ```swift
    /// let count = parse(input).getOrElse(0)
    /// ```
    func getOrElse(_ defaultValue: @autoclosure () -> Success) -> Success {
        switch self {
            case .success(let value):
                return value
            case .failure:
                return defaultValue()
        }
    }

    /// Asynchronous variant of ``getOrElse(_:)-(_)`` taking a closure of the failure.
    func getOrElseAsync(
        _ onFailure: (Failure) async -> Success
    ) async -> Success {
        switch self {
            case .success(let value):
                return value
            case .failure(let error):
                return await onFailure(error)
        }
    }

    /// Returns the success value, or awaits a default value if it's a failure.
    /// The default is only evaluated on failure.
    ///
    /// ```swift
    /// let user = await fetchUser(id: 1).getOrElseAsync(await loadGuestUser())
    /// ```
    func getOrElseAsync(
        _ defaultValue: @autoclosure @escaping () async -> Success
    ) async -> Success {
        switch self {
            case .success(let value):
                return value
            case .failure:
                return await defaultValue()
        }
    }
}
