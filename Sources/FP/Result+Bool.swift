public extension Result {
    /// Whether the result is a success.
    @inlinable
    var isSuccess: Bool {
        switch self {
            case .success:
                return true
            case .failure:
                return false
        }
    }

    /// Whether the result is a failure.
    @inlinable
    var isFailure: Bool {
        !isSuccess
    }
}
