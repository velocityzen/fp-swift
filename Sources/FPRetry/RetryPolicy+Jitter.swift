import Synchronization

// MARK: - Jitter

public extension RetryPolicy {
    /// Multiplies each wait by a random number from `range`. Retries as
    /// often as before.
    ///
    /// Many clients often fail at the same time, for example when a server
    /// restarts. With the same policy, they also retry at the same time, and
    /// this can overload the server again. Jitter makes each wait random, so
    /// the retries spread out.
    ///
    /// ```swift
    /// let apiPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
    ///     .and(.limitRetries(5))
    ///     .capDelay(.seconds(2))
    ///     .jitter()
    /// // Random waits up to 200ms, 400ms, 800ms, 1.6s, 2s, then stops
    /// ```
    ///
    /// The range contains multipliers, not durations:
    /// - `0...1` (the default): from 0 to the full wait.
    /// - `0.5...1`: from half the wait to the full wait.
    /// - `0.8...1.2`: the wait, plus or minus 20%.
    ///
    /// Put jitter last, after ``capDelay(_:)``. Then a wait is never longer
    /// than the cap.
    ///
    /// The status records the real, random wait. A multiplier of zero or less
    /// means no wait.
    ///
    /// - Parameter range: The multipliers. The range must be finite.
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

    /// Multiplies each wait by a random number from `range`, made by
    /// `generator`. Retries as often as before.
    ///
    /// Use it in tests: with a seeded generator, the waits are the same on
    /// every run.
    ///
    /// ```swift
    /// let policy = RetryPolicy.exponentialBackoff(.seconds(1))
    ///     .and(.limitRetries(3))
    ///     .jitter(using: SeededGenerator(seed: 42))
    /// ```
    ///
    /// `SeededGenerator` is your own type. The standard library has no
    /// seeded generator, but SplitMix64 is only a few lines.
    ///
    /// The policy keeps the generator, and each use takes the next random
    /// numbers. To get the same numbers again, create the policy again with
    /// the same seed. Many tasks can use the policy at the same time.
    ///
    /// - Parameters:
    ///   - range: The multipliers. The range must be finite.
    ///   - generator: The random number generator.
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

/// A random number generator that many tasks can use at the same time.
/// A lock lets only one task use it at a time.
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
