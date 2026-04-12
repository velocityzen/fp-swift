import Foundation

// MARK: - AsyncStream Static Factories for Result

public extension AsyncStream {
    /// Creates a stream that emits a single success value and finishes.
    static func success<Success: Sendable, Failure: Sendable>(
        _ value: Success
    ) -> AsyncStream<Result<Success, Failure>> where Element == Result<Success, Failure> {
        AsyncStream<Result<Success, Failure>> { continuation in
            continuation.finishWithSuccess(value)
        }
    }

    /// Creates a stream that emits a single failure error and finishes.
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
    /// Yields a success value wrapped in Result
    @discardableResult
    func success<Success: Sendable, Failure: Sendable>(
        _ value: Success
    ) -> YieldResult where Element == Result<Success, Failure> {
        yield(.success(value))
    }

    /// Yields a failure error wrapped in Result
    @discardableResult
    func failure<Success: Sendable, Failure: Sendable>(
        _ error: Failure
    ) -> YieldResult where Element == Result<Success, Failure> {
        yield(.failure(error))
    }

    /// Yields a success value and finishes the stream
    func finishWithSuccess<Success: Sendable, Failure: Sendable>(
        _ value: Success
    ) where Element == Result<Success, Failure> {
        yield(.success(value))
        finish()
    }

    /// Yields a failure error and finishes the stream
    func finishWithFailure<Success: Sendable, Failure: Sendable>(
        _ error: Failure
    ) where Element == Result<Success, Failure> {
        yield(.failure(error))
        finish()
    }
}
