import Foundation

extension Array {
    /// Traverses the array, applying a transform function that returns a Result.
    /// If all transformations succeed, returns a Result containing an array of successes.
    /// If any transformation fails, returns the first failure encountered.
    ///
    /// - Parameter transform: A closure that transforms each element into a Result
    /// - Returns: A Result containing either an array of all successes or the first failure
    func traverse<Success, Failure: Error>(
        _ transform: (Element) throws -> Result<Success, Failure>
    ) rethrows -> Result<[Success], Failure> {
        var results: [Success] = []
        results.reserveCapacity(count)

        for element in self {
            switch try transform(element) {
                case .success(let value):
                    results.append(value)
                case .failure(let error):
                    return .failure(error)
            }
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
        _ transform: (Element) async throws -> Result<Success, Failure>
    ) async rethrows -> Result<[Success], Failure> {
        var results: [Success] = []
        results.reserveCapacity(count)

        for element in self {
            switch try await transform(element) {
                case .success(let value):
                    results.append(value)
                case .failure(let error):
                    return .failure(error)
            }
        }

        return .success(results)
    }
}
