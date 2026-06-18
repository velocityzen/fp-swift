import Testing

@testable import FP

@Suite("Result+Race Tests")
struct ResultRaceTests {
    enum TestError: Error, Equatable {
        case failed
        case other
    }

    // MARK: - Autoclosure form (arity 2…10)

    @Test("returns the operation that succeeds first")
    func firstSuccessWins() async {
        let fast: @Sendable () async -> Result<Int, TestError> = { .success(1) }
        let slow: @Sendable () async -> Result<Int, TestError> = {
            try? await Task.sleep(nanoseconds: 100_000_000)
            return .success(2)
        }

        let result = await withAny(await fast(), await slow())

        #expect(result == .success(1))
    }

    @Test("a fast failure does not beat a slower success")
    func successBeatsFasterFailure() async {
        let failsFast: @Sendable () async -> Result<Int, TestError> = { .failure(.failed) }
        let succeedsSlow: @Sendable () async -> Result<Int, TestError> = {
            try? await Task.sleep(nanoseconds: 100_000_000)
            return .success(42)
        }

        let result = await withAny(await failsFast(), await succeedsSlow())

        #expect(result == .success(42))
    }

    @Test("races ten operations via the autoclosure form")
    func racesTenAutoclosure() async {
        let slow: @Sendable () async -> Result<Int, TestError> = {
            try? await Task.sleep(nanoseconds: 200_000_000)
            return .success(0)
        }
        let fast: @Sendable () async -> Result<Int, TestError> = { .success(7) }

        let result = await withAny(
            await slow(), await slow(), await slow(), await slow(), await slow(),
            await slow(), await fast(), await slow(), await slow(), await slow()
        )

        #expect(result == .success(7))
    }

    // MARK: - Array form (dynamic)

    @Test("array form: skips several fast failures and waits for a success")
    func arraySkipsFailuresForSuccess() async {
        let ops: [@Sendable () async -> Result<Int, TestError>] = [
            { .failure(.failed) },  // fast failure
            { .failure(.other) },  // fast failure
            {
                try? await Task.sleep(nanoseconds: 80_000_000)
                return .success(99)  // slower success — the winner
            },
            {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                return .failure(.failed)  // very slow, cancelled before it matters
            },
        ]

        let result = await withAny(ops)

        #expect(result == .success(99))
    }

    @Test("array form: returns the last failure when every operation fails")
    func arrayAllFailReturnsLastFailure() async {
        let ops: [@Sendable () async -> Result<Int, TestError>] = [
            { .failure(.failed) },  // fails immediately
            {
                try? await Task.sleep(nanoseconds: 100_000_000)
                return .failure(.other)  // fails last
            },
        ]

        let result = await withAny(ops)

        #expect(result == .failure(.other))
    }

    @Test("array form: a single operation returns its own result")
    func arraySingleOperation() async {
        let success: [@Sendable () async -> Result<Int, TestError>] = [{ .success(7) }]
        let failure: [@Sendable () async -> Result<Int, TestError>] = [{ .failure(.failed) }]

        let succeeded = await withAny(success)
        let failed = await withAny(failure)

        #expect(succeeded == .success(7))
        #expect(failed == .failure(.failed))
    }

    // MARK: - Concurrency & cancellation

    @Test("array form: runs the operations concurrently")
    func arrayRunsConcurrently() async {
        let tracker = ConcurrencyTracker()
        let ops: [@Sendable () async -> Result<Int, TestError>] = [
            {
                await tracker.enter()
                try? await Task.sleep(nanoseconds: 50_000_000)
                await tracker.exit()
                return .success(1)
            },
            {
                await tracker.enter()
                try? await Task.sleep(nanoseconds: 50_000_000)
                await tracker.exit()
                return .success(2)
            },
        ]

        let result = await withAny(ops)

        let highWater = await tracker.highWater
        #expect(result == .success(1) || result == .success(2))
        #expect(highWater >= 2)
    }

    @Test("array form: cancels the losing operations once a winner succeeds")
    func arrayCancelsLosersOnWin() async {
        let cancelled = AsyncCounter()
        let ops: [@Sendable () async -> Result<Int, TestError>] = [
            { .success(1) },  // immediate winner
            {
                // sleeps far longer than the test; throws immediately on cancellation
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled {
                    await cancelled.increment()
                }
                return .success(2)
            },
        ]

        let result = await withAny(ops)

        let cancelledCount = await cancelled.count
        #expect(result == .success(1))
        #expect(cancelledCount == 1)
    }
}
