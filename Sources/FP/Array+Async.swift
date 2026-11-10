public extension Array {
    /// Transforms each element with an async closure, one at a time.
    ///
    /// To run the transforms at the same time, use `traverseAsync(concurrency:_:)`.
    @inlinable
    func mapAsync<T>(_ transform: (Element) async -> T) async -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            results.append(await transform(element))
        }
        return results
    }

    /// Transforms each element into a sequence with an async closure, one at a
    /// time, and joins the results.
    @inlinable
    func flatMapAsync<S: Sequence>(
        _ transform: (Element) async -> S
    ) async -> [S.Element] {
        var results: [S.Element] = []
        for element in self {
            results.append(contentsOf: await transform(element))
        }
        return results
    }

    /// Transforms each element into a sequence with an async closure that can
    /// fail, one at a time, and joins the results.
    ///
    /// The first failure stops the work and is returned.
    @inlinable
    func flatMapAsync<S: Sequence, Failure: Error>(
        _ transform: (Element) async -> Result<S, Failure>
    ) async -> Result<[S.Element], Failure> {
        var results: [S.Element] = []
        for element in self {
            switch await transform(element) {
                case .success(let sequence):
                    results.append(contentsOf: sequence)
                case .failure(let error):
                    return .failure(error)
            }
        }
        return .success(results)
    }

    /// Transforms each element with an async closure, one at a time, and drops
    /// nil results.
    @inlinable
    func compactMapAsync<T>(_ transform: (Element) async -> T?) async -> [T] {
        var results: [T] = []
        for element in self {
            if let transformed = await transform(element) {
                results.append(transformed)
            }
        }
        return results
    }

    /// Transforms each element with an async closure that can fail, one at a
    /// time, and drops nil results.
    ///
    /// The first failure stops the work and is returned.
    @inlinable
    func compactMapAsync<T, Failure: Error>(
        _ transform: (Element) async -> Result<T?, Failure>
    ) async -> Result<[T], Failure> {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            switch await transform(element) {
                case .success(let transformed):
                    if let transformed {
                        results.append(transformed)
                    }
                case .failure(let error):
                    return .failure(error)
            }
        }
        return .success(results)
    }
}
