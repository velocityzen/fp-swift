// MARK: - AsyncStream Static Factories for Result

public extension AsyncStream {
    /// Creates a stream that gives one success value and then finishes.
    @inlinable
    static func success<Success: Sendable, Failure: Sendable>(
        _ value: Success
    ) -> AsyncStream<Result<Success, Failure>> where Element == Result<Success, Failure> {
        AsyncStream<Result<Success, Failure>> { continuation in
            continuation.finishWithSuccess(value)
        }
    }

    /// Creates a stream that gives one failure and then finishes.
    @inlinable
    static func failure<Success: Sendable, Failure: Sendable>(
        _ error: Failure
    ) -> AsyncStream<Result<Success, Failure>> where Element == Result<Success, Failure> {
        AsyncStream<Result<Success, Failure>> { continuation in
            continuation.finishWithFailure(error)
        }
    }
}

// MARK: - AsyncStream.Continuation Extensions for Result

public extension AsyncStream.Continuation {
    /// Sends `.success(value)` to the stream.
    @discardableResult
    @inlinable
    func success<Success: Sendable, Failure: Sendable>(
        _ value: Success
    ) -> YieldResult where Element == Result<Success, Failure> {
        yield(.success(value))
    }

    /// Sends `.failure(error)` to the stream.
    @discardableResult
    @inlinable
    func failure<Success: Sendable, Failure: Sendable>(
        _ error: Failure
    ) -> YieldResult where Element == Result<Success, Failure> {
        yield(.failure(error))
    }

    /// Sends `.success(value)` to the stream, and finishes it.
    @inlinable
    func finishWithSuccess<Success: Sendable, Failure: Sendable>(
        _ value: Success
    ) where Element == Result<Success, Failure> {
        yield(.success(value))
        finish()
    }

    /// Sends `.failure(error)` to the stream, and finishes it.
    @inlinable
    func finishWithFailure<Success: Sendable, Failure: Sendable>(
        _ error: Failure
    ) where Element == Result<Success, Failure> {
        yield(.failure(error))
        finish()
    }
}
