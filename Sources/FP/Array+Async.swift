public extension Array {
    /// Asynchronously maps each element to a new value.
    func mapAsync<T>(_ transform: (Element) async -> T) async -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            results.append(await transform(element))
        }
        return results
    }

    /// Asynchronously transforms each element to a sequence and flattens the result.
    func flatMapAsync<S: Sequence>(
        _ transform: (Element) async -> S
    ) async -> [S.Element] {
        var results: [S.Element] = []
        for element in self {
            results.append(contentsOf: await transform(element))
        }
        return results
    }

    /// Asynchronously transforms each element to a Result-wrapped sequence and flattens the result.
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

    /// Asynchronously maps each element to an optional value and filters out nil results.
    func compactMapAsync<T>(_ transform: (Element) async -> T?) async -> [T] {
        var results: [T] = []
        for element in self {
            if let transformed = await transform(element) {
                results.append(transformed)
            }
        }
        return results
    }

    /// Asynchronously maps each element to a Result containing an optional value and filters out nil results.
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
