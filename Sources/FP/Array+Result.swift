public extension Array {
    /// Traverses the array, applying a transform function to each element.
    /// Returns a Result containing an array of transformed values.
    ///
    /// - Parameter transform: A closure that transforms each element
    /// - Returns: A Result containing an array of transformed values (never fails)
    func traverse<Success>(
        _ transform: (Element) -> Success
    ) -> Result<[Success], Never> {
        var results: [Success] = []
        results.reserveCapacity(count)

        for element in self {
            results.append(transform(element))
        }

        return .success(results)
    }

    /// Traverses the array, applying a transform function that returns a Result.
    /// If all transformations succeed, returns a Result containing an array of successes.
    /// If any transformation fails, returns the first failure encountered.
    ///
    /// - Parameter transform: A closure that transforms each element into a Result
    /// - Returns: A Result containing either an array of all successes or the first failure
    func traverse<Success, Failure: Error>(
        _ transform: (Element) -> Result<Success, Failure>
    ) -> Result<[Success], Failure> {
        var results: [Success] = []
        results.reserveCapacity(count)

        for element in self {
            switch transform(element) {
                case .success(let value):
                    results.append(value)
                case .failure(let error):
                    return .failure(error)
            }
        }

        return .success(results)
    }

    /// Asynchronously traverses the array, applying a transform function to each element.
    /// Returns a Result containing an array of transformed values.
    ///
    /// - Parameter transform: An async closure that transforms each element
    /// - Returns: A Result containing an array of transformed values (never fails)
    func traverseAsync<Success>(
        _ transform: (Element) async -> Success
    ) async -> Result<[Success], Never> {
        var results: [Success] = []
        results.reserveCapacity(count)

        for element in self {
            results.append(await transform(element))
        }

        return .success(results)
    }

    /// Asynchronously traverses the array, applying a transform function that returns a Result.
    /// If all transformations succeed, returns a Result containing an array of successes.
    /// If any transformation fails, returns the first failure encountered.
    ///
    /// - Parameter transform: An async closure that transforms each element into a Result
    /// - Returns: A Result containing either an array of all successes or the first failure
    func traverseAsync<Success, Failure: Error>(
        _ transform: (Element) async -> Result<Success, Failure>
    ) async -> Result<[Success], Failure> {
        var results: [Success] = []
        results.reserveCapacity(count)

        for element in self {
            switch await transform(element) {
                case .success(let value):
                    results.append(value)
                case .failure(let error):
                    return .failure(error)
            }
        }

        return .success(results)
    }

    /// Separates an array of Results into success and failure arrays.
    ///
    /// - Returns: A tuple containing all success values and all failure values
    func separate<Success, Failure>() -> (successes: [Success], failures: [Failure])
    where Element == Result<Success, Failure> {
        var successes: [Success] = []
        var failures: [Failure] = []
        successes.reserveCapacity(count)
        failures.reserveCapacity(count)

        for result in self {
            switch result {
                case .success(let value):
                    successes.append(value)
                case .failure(let error):
                    failures.append(error)
            }
        }

        return (successes: successes, failures: failures)
    }

    /// Returns just the success values from an array of `Result`.
    ///
    /// ```swift
    /// let results: [Result<Int, MyError>] = [.success(1), .failure(.bad), .success(2)]
    /// results.successes()  // [1, 2]
    /// ```
    func successes<Success, Failure>() -> [Success]
    where Element == Result<Success, Failure> {
        var values: [Success] = []
        values.reserveCapacity(count)
        for result in self {
            if case .success(let value) = result {
                values.append(value)
            }
        }
        return values
    }

    /// Returns just the failure errors from an array of `Result`.
    ///
    /// ```swift
    /// let results: [Result<Int, MyError>] = [.success(1), .failure(.bad), .success(2)]
    /// results.failures()  // [.bad]
    /// ```
    func failures<Success, Failure>() -> [Failure]
    where Element == Result<Success, Failure> {
        var errors: [Failure] = []
        for result in self {
            if case .failure(let error) = result {
                errors.append(error)
            }
        }
        return errors
    }
}
