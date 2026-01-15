import Foundation

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
}
