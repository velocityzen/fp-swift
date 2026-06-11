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
    /// Transforms run sequentially — each element awaits the previous one.
    /// Pass `concurrency:` to run them in parallel.
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
    /// Transforms run sequentially — each element awaits the previous one, and
    /// elements after a failure never run. Pass `concurrency:` to run them in
    /// parallel.
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

    /// Asynchronously traverses the array with up to `concurrency` transforms
    /// in flight at once. Results keep source order.
    ///
    /// - Parameters:
    ///   - concurrency: Maximum number of transforms in flight at once; must
    ///     be at least 1. `concurrency: 1` is equivalent to the sequential
    ///     variant.
    ///   - transform: An async closure that transforms each element
    /// - Returns: A Result containing an array of transformed values in
    ///   source order (never fails)
    func traverseAsync<Success: Sendable>(
        concurrency: Int,
        _ transform: @Sendable @escaping (Element) async -> Success
    ) async -> Result<[Success], Never> where Element: Sendable {
        precondition(concurrency >= 1, "concurrency must be at least 1")
        let values = await withTaskGroup(of: (index: Int, value: Success).self) { group in
            var slots = [Success?](repeating: nil, count: count)
            var nextIndex = 0
            var inFlight = 0

            while true {
                while inFlight < concurrency, nextIndex < count {
                    let index = nextIndex
                    let element = self[index]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask { (index, await transform(element)) }
                }
                guard inFlight > 0, let completed = await group.next() else { break }
                inFlight -= 1
                slots[completed.index] = completed.value
            }

            return slots.compactMap { $0 }
        }
        return .success(values)
    }

    /// Asynchronously traverses the array with up to `concurrency` transforms
    /// in flight at once. Results keep source order.
    ///
    /// Fails with the failure of the lowest-index failing element. Once a
    /// failure is observed, no further transforms start and in-flight ones
    /// are cancelled cooperatively — elements after a failure may have
    /// started (and been cancelled) or never run at all.
    ///
    /// For streaming results, endless sources, or failures kept in position,
    /// use `mapAsyncKeepOrder` on an async sequence instead.
    ///
    /// - Parameters:
    ///   - concurrency: Maximum number of transforms in flight at once; must
    ///     be at least 1. `concurrency: 1` is equivalent to the sequential
    ///     variant.
    ///   - transform: An async closure that transforms each element into a Result
    /// - Returns: A Result containing either an array of all successes in
    ///   source order, or the lowest-index failure
    func traverseAsync<Success: Sendable, Failure: Error>(
        concurrency: Int,
        _ transform: @Sendable @escaping (Element) async -> Result<Success, Failure>
    ) async -> Result<[Success], Failure> where Element: Sendable {
        precondition(concurrency >= 1, "concurrency must be at least 1")
        return await withTaskGroup(
            of: (index: Int, result: Result<Success, Failure>).self
        ) { group in
            var slots = [Success?](repeating: nil, count: count)
            var lowestFailureIndex = Int.max
            var lowestFailure: Failure? = nil
            var nextIndex = 0
            var inFlight = 0

            while true {
                while lowestFailure == nil, inFlight < concurrency, nextIndex < count {
                    let index = nextIndex
                    let element = self[index]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask { (index, await transform(element)) }
                }
                guard inFlight > 0, let completed = await group.next() else { break }
                inFlight -= 1
                switch completed.result {
                    case .success(let value):
                        slots[completed.index] = value
                    case .failure(let error):
                        if completed.index < lowestFailureIndex {
                            lowestFailureIndex = completed.index
                            lowestFailure = error
                        }
                        group.cancelAll()
                }
            }

            if let failure = lowestFailure {
                return .failure(failure)
            }
            return .success(slots.compactMap { $0 })
        }
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
