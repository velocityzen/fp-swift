import Testing

@testable import FPRetry

/// SplitMix64: a small seeded generator, so jittered delays are
/// reproducible.
struct SeededGenerator: RandomNumberGenerator, Sendable {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("RetryPolicy.jitter")
struct JitterTests {
    /// The delays a policy waits, ending with `nil` where it gives up.
    func delays(_ policy: RetryPolicy) -> [Duration?] {
        policy.dryRun().map(\.previousDelay)
    }

    let manyRetries = RetryPolicy.constantDelay(.seconds(1)).and(.limitRetries(1_000))

    @Test("jitter() waits anywhere from zero up to the policy's delay")
    func fullJitter() throws {
        let delays = try delays(manyRetries.jitter()).dropLast().map { try #require($0) }

        #expect(delays.allSatisfy { $0 >= .zero && $0 <= .seconds(1) })
        // 1,000 draws all on one side of the middle would be a broken jitter.
        #expect(delays.contains { $0 < .milliseconds(500) })
        #expect(delays.contains { $0 > .milliseconds(500) })
    }

    @Test("jitter(range) scales each delay by a factor in the range")
    func rangeJitter() throws {
        let delays = try delays(manyRetries.jitter(0.8...1.2)).dropLast().map { try #require($0) }

        #expect(delays.allSatisfy { $0 >= .milliseconds(800) && $0 <= .milliseconds(1_200) })
        #expect(delays.contains { $0 < .seconds(1) })
        #expect(delays.contains { $0 > .seconds(1) })
    }

    @Test("jitter gives up exactly when the policy it wraps does")
    func keepsLimit() {
        let policy = RetryPolicy.exponentialBackoff(.seconds(1)).and(.limitRetries(3))
        let delays = delays(policy.jitter())

        #expect(delays.count == 4)
        #expect(delays.dropLast().allSatisfy { $0 != nil })
        #expect(delays.last == .some(nil))
    }

    @Test("jitter(1...1) leaves the delays as they are")
    func identity() {
        let policy = RetryPolicy.exponentialBackoff(.milliseconds(100)).and(.limitRetries(5))

        #expect(delays(policy.jitter(1...1)) == delays(policy))
    }

    @Test("the same seed gives the same delays, another seed other delays")
    func seeded() {
        func jittered(seed: UInt64) -> RetryPolicy {
            manyRetries.jitter(using: SeededGenerator(seed: seed))
        }

        #expect(delays(jittered(seed: 42)) == delays(jittered(seed: 42)))
        #expect(delays(jittered(seed: 42)) != delays(jittered(seed: 7)))
    }

    @Test("a seeded policy draws the next numbers on every use")
    func seededPolicyAdvances() {
        let policy = manyRetries.jitter(using: SeededGenerator(seed: 42))

        #expect(delays(policy) != delays(policy))
    }

    @Test("withRetry waits the jittered delays")
    func withRetryWaitsJitteredDelays() async {
        let clock = TestClock()
        let policy = RetryPolicy.exponentialBackoff(.milliseconds(100)).and(.limitRetries(4))
        let expected = policy.jitter(using: SeededGenerator(seed: 1)).dryRun()
            .compactMap(\.previousDelay)

        let _: Result<Int, TestError> = await withRetry(
            policy.jitter(using: SeededGenerator(seed: 1)),
            clock: clock
        ) {
            .failure(.fatal)
        }

        #expect(clock.sleeps == expected)
    }

    @Test("the cumulative delay adds up the jittered delays")
    func cumulativeDelay() {
        let statuses = Array(manyRetries.jitter().dryRun().prefix(10))
        let total = statuses.compactMap(\.previousDelay).reduce(.zero, +)

        #expect(statuses.last?.cumulativeDelay == total)
    }

    @Test("a factor that is not positive retries at once")
    func nonPositiveFactor() {
        let policy = RetryPolicy.constantDelay(.seconds(1)).and(.limitRetries(3))

        #expect(delays(policy.jitter(-1 ... -0.5)) == [.zero, .zero, .zero, nil])
        #expect(delays(policy.jitter(0...0)) == [.zero, .zero, .zero, nil])
    }

    @Test("a jittered delay saturates at maximumDelay instead of overflowing")
    func saturates() {
        let huge = RetryPolicy.constantDelay(.seconds(1)).jitter(1e30...1e30)
        let atMaximum = RetryPolicy.constantDelay(RetryPolicy.maximumDelay).jitter(2...2)
        let pastMaximum = RetryPolicy.constantDelay(.seconds(Int64.max)).jitter(1...1)

        #expect(huge(.initial) == RetryPolicy.maximumDelay)
        #expect(atMaximum(.initial) == RetryPolicy.maximumDelay)
        #expect(pastMaximum(.initial) == RetryPolicy.maximumDelay)
    }

    @Test("a seeded policy can be shared between tasks")
    func sharedBetweenTasks() async {
        let policy = manyRetries.jitter(using: SeededGenerator(seed: 3))

        let counts = await withTaskGroup(of: Int.self) { group in
            for _ in 0..<8 {
                group.addTask { Array(policy.dryRun().prefix(100)).count }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(counts == Array(repeating: 100, count: 8))
    }
}
