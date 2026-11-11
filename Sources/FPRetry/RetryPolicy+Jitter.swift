import Synchronization

// MARK: - Jitter

public extension RetryPolicy {
    /// Multiplies each wait by a random number from `range`. Retries as often as before.
    ///
    /// Use it when many clients share a policy, so they do not all retry at the same time.
    ///
    /// - `0...1` (the default): from zero to the full wait.
    /// - `0.5...1`: from half the wait to the full wait.
    /// - `0.8...1.2`: the wait, plus or minus 20%.
    ///
    /// Put jitter after ``capDelay(_:)`` and before ``requestedDelay``, so the random wait never
    /// shortens a wait the failure asked for. A multiplier of zero or less means no wait. The
    /// status records the random wait.
    ///
    /// - Parameter range: The multipliers, not durations. Must be finite.
    @inlinable
    func jitter(_ range: ClosedRange<Double> = 0...1) -> RetryPolicy {
        precondition(
            (range.upperBound - range.lowerBound).isFinite,
            "The jitter range must be finite"
        )
        return RetryPolicy { status in
            self(status).map { $0.scaledForRetry(by: Double.random(in: range)) }
        }
    }

    /// Multiplies each wait by a random number from `range`, made by `generator`.
    ///
    /// Use it in tests: with a seeded generator, the waits are the same on every run. The policy
    /// keeps the generator, so each use takes the next numbers. To start again, create the
    /// policy again. Otherwise it works like ``jitter(_:)``.
    @inlinable
    func jitter<Generator: RandomNumberGenerator & Sendable>(
        _ range: ClosedRange<Double> = 0...1,
        using generator: Generator
    ) -> RetryPolicy {
        precondition(
            (range.upperBound - range.lowerBound).isFinite,
            "The jitter range must be finite"
        )
        let shared = SharedRandomNumberGenerator(generator)
        return RetryPolicy { status in
            self(status).map { $0.scaledForRetry(by: shared.random(in: range)) }
        }
    }
}

/// A random number generator that many tasks can share, behind a lock.
@usableFromInline
final class SharedRandomNumberGenerator<Generator: RandomNumberGenerator & Sendable>: Sendable {
    @usableFromInline
    let generator: Mutex<Generator>

    @inlinable
    init(_ generator: Generator) {
        self.generator = Mutex(generator)
    }

    @inlinable
    func random(in range: ClosedRange<Double>) -> Double {
        generator.withLock { Double.random(in: range, using: &$0) }
    }
}
