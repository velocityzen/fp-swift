import Foundation

public extension Result {
    /// Returns `self` if it's a success; otherwise returns the alternative.
    /// The alternative is only evaluated on failure.
    ///
    /// The left-most success wins, but if both sides are failures the
    /// alternative's failure is returned.
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
    /// Unlike ``alt(_:)``, the recovery receives the failure value and can
    /// transform the error type.
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
    /// Unlike ``alt(_:)``, the fallback returns an unwrapped `Success` rather
    /// than another `Result`.
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

    /// Returns the success value, or prints the failure to stderr and exits
    /// the process. Designed for CLI entry points where any failure should
    /// terminate the program with a diagnostic line.
    ///
    /// On failure, writes `"<prefix><error>\n"` to stderr and calls
    /// `Foundation.exit(exitCode)`.
    ///
    /// ```swift
    /// let config = loadConfig().getOrExit()
    /// // failure prints: "Error: <error>\n" and exits with status 1
    /// ```
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

    /// Returns the success value, or prints a custom message to stderr and
    /// exits the process. The closure receives the failure and returns the
    /// full message — include any trailing newline yourself.
    ///
    /// ```swift
    /// let user = fetchUser(id: 1).getOrExit { error in
    ///     "could not load user: \(error)\n"
    /// }
    /// ```
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

    /// Exits the process on failure, ignoring the success value. Useful at
    /// the end of a pipeline that has already consumed the success (via
    /// ``tap(_:)-((Success)->Void)`` or similar) and just needs to terminate
    /// on error.
    ///
    /// On failure, writes `"<prefix><error>\n"` to stderr and calls
    /// `Foundation.exit(exitCode)`. On success, does nothing.
    ///
    /// ```swift
    /// runCommand(args)
    ///     .tap { output in print(output) }
    ///     .orExit()
    /// ```
    func orExit(
        prefix: String = "Error: ",
        exitCode: Int32 = 1
    ) {
        if case .failure(let error) = self {
            writeToStderr("\(prefix)\(error)\n")
            Foundation.exit(exitCode)
        }
    }

    /// Exits the process on failure with a custom message, ignoring the
    /// success value. The closure receives the failure and returns the full
    /// message — include any trailing newline yourself.
    ///
    /// ```swift
    /// runCommand(args).orExit { error in
    ///     "command failed: \(error)\n"
    /// }
    /// ```
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
