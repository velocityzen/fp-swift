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

/// Helper actor that records the high-water mark of concurrent executions
actor ConcurrencyTracker {
    private var current = 0
    private(set) var highWater = 0

    func enter() {
        current += 1
        highWater = max(highWater, current)
    }

    func exit() {
        current -= 1
    }
}
