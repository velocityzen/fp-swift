import Synchronization

// MARK: - Jitter

public extension RetryPolicy {
    /// Multiplies every delay by a random factor drawn from `range`,
    /// retrying exactly as often as before.
    ///
    /// When many clients fail at the same moment — a server restarts, a
    /// network blips — the same policy has them all retry at the same moments
    /// too, and the bursts can keep the server down. Jitter spreads their
    /// retries out. Add it to any policy that more than one client runs.
    ///
    /// ```swift
    /// let apiPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
    ///     .and(.limitRetries(5))
    ///     .capDelay(.seconds(2))
    ///     .jitter()
    /// // Random delays up to 200ms, 400ms, 800ms, 1.6s, 2s, then gives up
    /// ```
    ///
    /// The range is of factors, not durations:
    /// - `0...1`, the default, is *full jitter*: anywhere from no delay up to
    ///   the policy's own. It spreads retries out the most.
    /// - `0.5...1` is *equal jitter*: at least half the policy's delay, so a
    ///   retry never comes too soon.
    /// - `0.8...1.2` is ±20% around the policy's delay.
    ///
    /// Add jitter last, after ``capDelay(_:)``: the cap then bounds the delay
    /// jitter draws from, so full jitter waits up to the cap at most. A
    /// factor above `1` can take a delay past an earlier cap.
    ///
    /// The status records the delay actually waited, so
    /// ``RetryStatus/cumulativeDelay`` and
    /// ``limitRetriesByCumulativeDelay(_:)`` see the jittered delays. A
    /// non-positive factor retries at once, and a delay saturates at
    /// ``maximumDelay``.
    ///
    /// The random factors come from the system's random number generator;
    /// ``jitter(_:using:)`` takes a seeded one, for delays a test can predict.
    ///
    /// - Parameter range: The factors to draw from. Its width must be finite.
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

    /// Multiplies every delay by a random factor drawn from `range` with
    /// `generator`, retrying exactly as often as before.
    ///
    /// The same as ``jitter(_:)``, with the factors drawn from `generator` —
    /// a seeded one makes the delays reproducible:
    ///
    /// ```swift
    /// let policy = RetryPolicy.exponentialBackoff(.seconds(1))
    ///     .and(.limitRetries(3))
    ///     .jitter(using: SeededGenerator(seed: 42))
    /// ```
    ///
    /// `SeededGenerator` stands for a seeded `RandomNumberGenerator` of your
    /// own, such as SplitMix64: the standard library has none.
    ///
    /// The policy owns the generator, so every use of it — each `withRetry`
    /// call and each ``dryRun()`` — draws the next numbers from it. To repeat
    /// a sequence of delays, build the policy again with the same seed.
    /// Draws are serialized by a lock, so the policy can be shared between
    /// tasks.
    ///
    /// - Parameters:
    ///   - range: The factors to draw from. Its width must be finite.
    ///   - generator: The random number generator to draw the factors with.
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

/// A random number generator that a `@Sendable` policy can draw from on any
/// task: a lock serializes the draws.
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
