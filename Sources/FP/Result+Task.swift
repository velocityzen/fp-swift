@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension Result where Failure == Error, Success: Sendable {
    /// Creates a Result from a Task that returns a value and may throw
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

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension Result where Failure == Error {
    /// Creates a Result from a Task that returns a Result
    static func fromTask<S: Sendable>(
        _ task: Task<Result<S, Error>, Never>
    ) async -> Result<S, Error> {
        await task.value
    }

    /// Creates a Result from a closure that returns a Task with Result
    static func fromTask<S: Sendable>(
        _ task: () -> Task<Result<S, Error>, Never>
    ) async -> Result<S, Error> {
        await task().value
    }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension Result where Failure == Never, Success: Sendable {
    /// Creates a Result from a non-throwing Task
    static func fromTask(
        _ task: Task<Success, Never>
    ) async -> Result<Success, Never> {
        let value = await task.value
        return .success(value)
    }

    /// Creates a Result from a closure that returns a non-throwing Task
    static func fromTask(
        _ task: () -> Task<Success, Never>
    ) async -> Result<Success, Never> {
        let value = await task().value
        return .success(value)
    }
}
