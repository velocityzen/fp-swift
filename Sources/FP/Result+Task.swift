public extension Result where Failure == Error, Success: Sendable {
    /// Creates a `Result` from the value or the error of a throwing task.
    @inlinable
    static func fromTask(
        _ task: Task<Success, Error>
    ) async -> Result<Success, Error> {
        do {
            let value = try await task.value
            return .success(value)
        } catch {
            return .failure(error)
        }
    }

    /// Creates a `Result` from a closure that returns a throwing task.
    @inlinable
    static func fromTask(
        _ task: () -> Task<Success, Error>
    ) async -> Result<Success, Error> {
        do {
            let value = try await task().value
            return .success(value)
        } catch {
            return .failure(error)
        }
    }
}

public extension Result where Failure == Error {
    /// Returns the `Result` of a task.
    @inlinable
    static func fromTask<S: Sendable>(
        _ task: Task<Result<S, Error>, Never>
    ) async -> Result<S, Error> {
        await task.value
    }

    /// Returns the `Result` of the task that a closure returns.
    @inlinable
    static func fromTask<S: Sendable>(
        _ task: () -> Task<Result<S, Error>, Never>
    ) async -> Result<S, Error> {
        await task().value
    }
}

public extension Result where Failure == Never, Success: Sendable {
    /// Creates a `Result` from the value of a task that cannot fail.
    @inlinable
    static func fromTask(
        _ task: Task<Success, Never>
    ) async -> Result<Success, Never> {
        let value = await task.value
        return .success(value)
    }

    /// Creates a `Result` from a closure that returns a task that cannot fail.
    @inlinable
    static func fromTask(
        _ task: () -> Task<Success, Never>
    ) async -> Result<Success, Never> {
        let value = await task().value
        return .success(value)
    }
}
