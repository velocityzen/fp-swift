// Saturating arithmetic for retry delays. A delay or a sum of delays never
// leaves `.zero...RetryPolicy.maximumDelay`, so long backoffs and long
// cumulative waits saturate instead of trapping on overflow, and every delay
// can be slept: a clock traps when its deadline does not fit in `Int64`
// seconds.
//
// `Duration`'s comparisons, `+` and `.zero` are calls into the standard
// library rather than inlined arithmetic, so these helpers make as few of
// them as they can.

extension Duration {
    /// The delay clamped to `.zero...RetryPolicy.maximumDelay`.
    @inlinable
    var clampedToRetryDelay: Duration {
        min(max(self, .zero), RetryPolicy.maximumDelay)
    }

    /// The sum of two delays, both already within
    /// `.zero...RetryPolicy.maximumDelay`, saturating at the maximum.
    ///
    /// Their sum is at most twice the maximum, so it cannot overflow.
    @inlinable
    func addingRetryDelay(_ delay: Duration) -> Duration {
        min(self + delay, RetryPolicy.maximumDelay)
    }

    /// The delay times `factor`, saturating at `RetryPolicy.maximumDelay`;
    /// `.zero` for a factor or a delay that is not positive.
    @inlinable
    func scaledForRetry(by factor: Double) -> Duration {
        let base = clampedToRetryDelay
        guard factor > 0, base > .zero else { return .zero }
        // Past this factor the product is longer than the maximum, and far
        // enough past it, too long for a `Duration`.
        guard factor < RetryPolicy.maximumDelay / base else {
            return RetryPolicy.maximumDelay
        }
        return base * factor
    }

    /// The delay times `2^exponent`, saturating at
    /// `RetryPolicy.maximumDelay`; `.zero` for a delay that is not positive.
    @inlinable
    func doubled(times exponent: Int) -> Duration {
        let base = clampedToRetryDelay
        guard base > .zero else { return .zero }
        // 2^62 is the largest power of two an `Int` holds; past it any
        // positive delay saturates anyway.
        guard exponent < Int.bitWidth - 2 else { return RetryPolicy.maximumDelay }
        let factor = 1 << max(exponent, 0)
        return base > RetryPolicy.maximumDelay / factor
            ? RetryPolicy.maximumDelay
            : base * factor
    }
}
