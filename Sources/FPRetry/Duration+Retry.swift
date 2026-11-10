// Safe math for retry waits. Every result stays between zero and `RetryPolicy.maximumDelay`.
// Without this, a long backoff could overflow, and a clock crashes when its deadline does not
// fit in `Int64` seconds. `Duration` comparisons, `+` and `.zero` are not inlined, so these
// helpers use as few as they can.

extension Duration {
    /// The wait, kept between zero and `RetryPolicy.maximumDelay`.
    @inlinable
    var clampedToRetryDelay: Duration {
        min(max(self, .zero), RetryPolicy.maximumDelay)
    }

    /// The sum of two waits, at most the maximum. Both must already be in range, so the sum
    /// cannot overflow.
    @inlinable
    func addingRetryDelay(_ delay: Duration) -> Duration {
        min(self + delay, RetryPolicy.maximumDelay)
    }

    /// The wait times `factor`, at most the maximum. Zero when the factor or the wait is zero
    /// or less.
    @inlinable
    func scaledForRetry(by factor: Double) -> Duration {
        let base = clampedToRetryDelay
        guard factor > 0, base > .zero else { return .zero }
        // Above this factor, the result is past the maximum and may not fit in a `Duration`.
        guard factor < RetryPolicy.maximumDelay / base else {
            return RetryPolicy.maximumDelay
        }
        return base * factor
    }

    /// The wait times `2^exponent`, at most the maximum. Zero when the wait is zero or less.
    @inlinable
    func doubled(times exponent: Int) -> Duration {
        let base = clampedToRetryDelay
        guard base > .zero else { return .zero }
        // Keeps `1 << exponent` inside an `Int`. After this many doublings, even a 1ns wait is
        // years long.
        guard exponent < Int.bitWidth - 2 else { return RetryPolicy.maximumDelay }
        let factor = 1 << max(exponent, 0)
        return base > RetryPolicy.maximumDelay / factor
            ? RetryPolicy.maximumDelay
            : base * factor
    }
}
