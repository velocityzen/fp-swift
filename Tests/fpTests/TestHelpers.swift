import Foundation

/// Helper actor for async tests that tracks call counts
actor AsyncCounter {
    private(set) var count = 0

    @discardableResult
    func increment() -> Int {
        count += 1
        return count
    }
}
