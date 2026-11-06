// Safe math for retry waits. A wait, or a sum of waits, always stays
// between zero and `RetryPolicy.maximumDelay`. Without this, a long backoff
// could overflow, and a clock crashes when its deadline does not fit in
// `Int64` seconds.
//
// `Duration` comparisons, `+` and `.zero` are calls into the standard
// library, not inlined math, so these helpers use as few as they can.

extension Duration {
    /// The wait, kept between zero and `RetryPolicy.maximumDelay`.
    @inlinable
    var clampedToRetryDelay: Duration {
        min(max(self, .zero), RetryPolicy.maximumDelay)
    }

    /// The sum of two waits, at most `RetryPolicy.maximumDelay`. Both waits
    /// must already be between zero and the maximum.
    ///
    /// The sum is at most twice the maximum, so it cannot overflow.
    @inlinable
    func addingRetryDelay(_ delay: Duration) -> Duration {
        min(self + delay, RetryPolicy.maximumDelay)
    }

    /// The wait times `factor`, at most `RetryPolicy.maximumDelay`. Zero
    /// when the factor or the wait is zero or less.
    @inlinable
    func scaledForRetry(by factor: Double) -> Duration {
        let base = clampedToRetryDelay
        guard factor > 0, base > .zero else { return .zero }
        // Above this factor, the result is longer than the maximum. Far
        // above it, the result does not fit in a `Duration`.
        guard factor < RetryPolicy.maximumDelay / base else {
            return RetryPolicy.maximumDelay
        }
        return base * factor
    }

    /// The wait times `2^exponent`, at most `RetryPolicy.maximumDelay`. Zero
    /// when the wait is zero or less.
    @inlinable
    func doubled(times exponent: Int) -> Duration {
        let base = clampedToRetryDelay
        guard base > .zero else { return .zero }
        // 2^62 is the largest power of two in an `Int`. Above it, any
        // positive wait reaches the maximum anyway.
        guard exponent < Int.bitWidth - 2 else { return RetryPolicy.maximumDelay }
        let factor = 1 << max(exponent, 0)
        return base > RetryPolicy.maximumDelay / factor
            ? RetryPolicy.maximumDelay
            : base * factor
    }
}
