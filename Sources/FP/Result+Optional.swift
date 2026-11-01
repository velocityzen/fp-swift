public extension Result {
    /// Creates a Result from an optional, using the given error if nil.
    @inlinable
    static func fromOptional(_ optional: Success?, error: Failure) -> Result<Success, Failure> {
        if let value = optional {
            return .success(value)
        } else {
            return .failure(error)
        }
    }

    /// Creates a Result from an optional, lazily evaluating the error closure if nil.
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

    /// Returns a function that converts an optional to a Result with the given error.
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

    /// Returns a function that converts an optional to a Result with a lazily evaluated error.
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
