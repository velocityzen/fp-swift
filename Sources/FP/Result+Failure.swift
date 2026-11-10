import Foundation

public extension Result {
    /// Returns `self` if it is a success, or `alternative()` if it is a failure.
    ///
    /// `alternative` runs only on failure. If both fail, you get the failure from
    /// `alternative`.
    ///
    /// ```swift
    /// fetchUser(id: 1).alt { fetchUserFromCache(id: 1) }
    /// ```
    @inlinable
    func alt(_ alternative: () -> Result<Success, Failure>) -> Result<Success, Failure> {
        switch self {
            case .success:
                return self
            case .failure:
                return alternative()
        }
    }

    /// Async version of ``alt(_:)``.
    @inlinable
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

    /// Returns `self` if it is a success, or a new `Result` made from the error.
    ///
    /// Unlike ``alt(_:)``, `onFailure` gets the error and can change the error type.
    ///
    /// ```swift
    /// fetchUser(id: 1).orElse { error in
    ///     error is Timeout ? fetchUser(id: 1) : .failure(AppError.wrap(error))
    /// }
    /// ```
    @inlinable
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

    /// Async version of ``orElse(_:)``.
    @inlinable
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

    /// Returns the success value, or makes one from the error.
    @inlinable
    func getOrElse(_ onFailure: (Failure) -> Success) -> Success {
        switch self {
            case .success(let value):
                return value
            case .failure(let error):
                return onFailure(error)
        }
    }

    /// Returns the success value, or `defaultValue` on failure.
    ///
    /// `defaultValue` is evaluated only on failure.
    @inlinable
    func getOrElse(_ defaultValue: @autoclosure () -> Success) -> Success {
        switch self {
            case .success(let value):
                return value
            case .failure:
                return defaultValue()
        }
    }

    /// Async version of ``getOrElse(_:)-((Failure)->Success)``.
    @inlinable
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

    /// Returns the success value, or awaits `defaultValue` on failure.
    ///
    /// `defaultValue` is evaluated only on failure.
    ///
    /// ```swift
    /// let user = await fetchUser(id: 1).getOrElseAsync(await loadGuestUser())
    /// ```
    @inlinable
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

    /// Returns the success value, or prints the error to stderr and exits the process.
    ///
    /// On failure, it writes `"<prefix><error>\n"` to stderr and calls
    /// `Foundation.exit(exitCode)`.
    func getOrExit(
        prefix: String = "Error: ",
        exitCode: Int32 = 1
    ) -> Success {
        switch self {
            case .success(let value):
                return value
            case .failure(let error):
                writeToStderr("\(prefix)\(error)\n")
                Foundation.exit(exitCode)
        }
    }

    /// Returns the success value, or prints a custom message to stderr and exits the process.
    ///
    /// `message` gets the error and returns the full text. Add the trailing newline yourself.
    func getOrExit(
        exitCode: Int32 = 1,
        message: (Failure) -> String
    ) -> Success {
        switch self {
            case .success(let value):
                return value
            case .failure(let error):
                writeToStderr(message(error))
                Foundation.exit(exitCode)
        }
    }

    /// Exits the process on failure, and does nothing on success.
    ///
    /// On failure, it writes `"<prefix><error>\n"` to stderr and calls
    /// `Foundation.exit(exitCode)`. Use it at the end of a chain that already used the value.
    func orExit(
        prefix: String = "Error: ",
        exitCode: Int32 = 1
    ) {
        if case .failure(let error) = self {
            writeToStderr("\(prefix)\(error)\n")
            Foundation.exit(exitCode)
        }
    }

    /// Exits the process with a custom message on failure, and does nothing on success.
    ///
    /// `message` gets the error and returns the full text. Add the trailing newline yourself.
    func orExit(
        exitCode: Int32 = 1,
        message: (Failure) -> String
    ) {
        if case .failure(let error) = self {
            writeToStderr(message(error))
            Foundation.exit(exitCode)
        }
    }
}

private func writeToStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}
