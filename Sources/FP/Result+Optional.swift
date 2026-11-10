public extension Result {
    /// Creates a `Result` from an optional. `nil` becomes `.failure(error)`.
    @inlinable
    static func fromOptional(_ optional: Success?, error: Failure) -> Result<Success, Failure> {
        if let value = optional {
            return .success(value)
        } else {
            return .failure(error)
        }
    }

    /// Creates a `Result` from an optional. `nil` becomes `.failure(onError())`.
    @inlinable
    static func fromOptional(_ optional: Success?, onError: () -> Failure) -> Result<
        Success, Failure
    > {
        if let value = optional {
            return .success(value)
        } else {
            return .failure(onError())
        }
    }

    /// Returns a function that turns an optional into a `Result`, with `error` for `nil`.
    @inlinable
    static func fromOptional(error: Failure) -> (Success?) -> Result<Success, Failure> {
        return { optional in
            if let value = optional {
                return .success(value)
            } else {
                return .failure(error)
            }
        }
    }

    /// Returns a function that turns an optional into a `Result`, with `onError()` for `nil`.
    @inlinable
    static func fromOptional(onError: @escaping () -> Failure) -> (Success?) -> Result<
        Success, Failure
    > {
        return { optional in
            if let value = optional {
                return .success(value)
            } else {
                return .failure(onError())
            }
        }
    }
}
