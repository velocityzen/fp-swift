public extension Result where Failure == Error, Success: Sendable {
    /// Creates a Result from a Task that returns a value and may throw
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

    /// Creates a Result from a closure that returns a Task
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
    /// Creates a Result from a Task that returns a Result
    @inlinable
    static func fromTask<S: Sendable>(
        _ task: Task<Result<S, Error>, Never>
    ) async -> Result<S, Error> {
        await task.value
    }

    /// Creates a Result from a closure that returns a Task with Result
    @inlinable
    static func fromTask<S: Sendable>(
        _ task: () -> Task<Result<S, Error>, Never>
    ) async -> Result<S, Error> {
        await task().value
    }
}

public extension Result where Failure == Never, Success: Sendable {
    /// Creates a Result from a non-throwing Task
    @inlinable
    static func fromTask(
        _ task: Task<Success, Never>
    ) async -> Result<Success, Never> {
        let value = await task.value
        return .success(value)
    }

    /// Creates a Result from a closure that returns a non-throwing Task
    @inlinable
    static func fromTask(
        _ task: () -> Task<Success, Never>
    ) async -> Result<Success, Never> {
        let value = await task().value
        return .success(value)
    }
}
