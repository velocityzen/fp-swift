import Foundation

extension Array {
    /// Asynchronously maps each element to an optional value and filters out nil results.
    public func compactMapAsync<T>(_ transform: (Element) async -> T?) async -> [T] {
        var results: [T] = []
        for element in self {
            if let transformed = await transform(element) {
                results.append(transformed)
            }
        }
        return results
    }

    /// Asynchronously maps each element to an optional value and filters out nil results.
    public func compactMapAsync<T>(_ transform: (Element) async throws -> T?) async rethrows -> [T]
    {
        var results: [T] = []
        for element in self {
            if let transformed = try await transform(element) {
                results.append(transformed)
            }
        }
        return results
    }
}
