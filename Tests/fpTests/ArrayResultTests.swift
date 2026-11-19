import Testing

@testable import FP

@Suite("Array+Result Tests")
struct ArrayResultTests {
    enum TestError: Error, Equatable {
        case invalid
        case notFound
        case parseError(String)
    }

    // MARK: - traverse (synchronous)

    // MARK: - separate

    @Test("separate splits mixed results into successes and failures")
    func separateMixedResults() {
        let results: [Result<Int, TestError>] = [
            .success(1),
            .failure(.invalid),
            .success(2),
            .failure(.notFound),
            .success(3),
        ]

        let separated = results.separate()

        #expect(separated.successes == [1, 2, 3])
        #expect(separated.failures == [.invalid, .notFound])
    }

    @Test("separate returns only successes when no failures exist")
    func separateAllSuccesses() {
        let results: [Result<String, TestError>] = [
            .success("a"),
            .success("b"),
            .success("c"),
        ]

        let separated = results.separate()

        #expect(separated.successes == ["a", "b", "c"])
        #expect(separated.failures.isEmpty)
    }

    @Test("separate returns only failures when no successes exist")
    func separateAllFailures() {
        let results: [Result<Int, TestError>] = [
            .failure(.invalid),
            .failure(.notFound),
        ]

        let separated = results.separate()

        #expect(separated.successes.isEmpty)
        #expect(separated.failures == [.invalid, .notFound])
    }

    @Test("separate handles empty arrays")
    func separateEmptyArray() {
        let results: [Result<Int, TestError>] = []

        let separated = results.separate()

        #expect(separated.successes.isEmpty)
        #expect(separated.failures.isEmpty)
    }

    // MARK: - successes / failures

    @Test("successes returns only the success values, preserving order")
    func successesReturnsValues() {
        let results: [Result<Int, TestError>] = [
            .success(1),
            .failure(.invalid),
            .success(2),
            .failure(.notFound),
            .success(3),
        ]

        #expect(results.successes() == [1, 2, 3])
    }

    @Test("successes returns empty array when all failures")
    func successesAllFailures() {
        let results: [Result<Int, TestError>] = [
            .failure(.invalid),
            .failure(.notFound),
        ]

        #expect(results.successes().isEmpty)
    }

    @Test("successes returns empty array for empty input")
    func successesEmpty() {
        let results: [Result<Int, TestError>] = []

        #expect(results.successes().isEmpty)
    }

    @Test("failures returns only the failure errors, preserving order")
    func failuresReturnsErrors() {
        let results: [Result<Int, TestError>] = [
            .success(1),
            .failure(.invalid),
            .success(2),
            .failure(.notFound),
        ]

        #expect(results.failures() == [.invalid, .notFound])
    }

    @Test("failures returns empty array when all successes")
    func failuresAllSuccesses() {
        let results: [Result<Int, TestError>] = [
            .success(1),
            .success(2),
        ]

        #expect(results.failures().isEmpty)
    }

    @Test("failures returns empty array for empty input")
    func failuresEmpty() {
        let results: [Result<Int, TestError>] = []

        #expect(results.failures().isEmpty)
    }

    @Test("traverse succeeds when all transformations succeed")
    func traverseAllSuccess() {
        let numbers = [1, 2, 3, 4, 5]

        let result = numbers.traverse { number -> Result<String, TestError> in
            .success("num-\(number)")
        }

        #expect(result == .success(["num-1", "num-2", "num-3", "num-4", "num-5"]))
    }

    @Test("traverse fails with first error encountered")
    func traverseFailsOnFirstError() {
        let numbers = [1, 2, 3, 4, 5]

        let result = numbers.traverse { number -> Result<Int, TestError> in
            if number == 3 {
                return .failure(.invalid)
            }
            return .success(number * 2)
        }

        #expect(result == .failure(.invalid))
    }

    @Test("traverse stops processing after first failure")
    func traverseStopsAfterFailure() {
        var processedCount = 0
        let numbers = [1, 2, 3, 4, 5]

        let result = numbers.traverse { number -> Result<Int, TestError> in
            processedCount += 1
            if number == 3 {
                return .failure(.notFound)
            }
            return .success(number)
        }

        #expect(result == .failure(.notFound))
        #expect(processedCount == 3)
    }

    @Test("traverse handles empty array")
    func traverseEmptyArray() {
        let empty: [Int] = []

        let result = empty.traverse { number -> Result<String, TestError> in
            .success("\(number)")
        }

        #expect(result == .success([]))
    }

    @Test("traverse preserves order of successful results")
    func traversePreservesOrder() {
        let numbers = [5, 4, 3, 2, 1]

        let result = numbers.traverse { number -> Result<Int, TestError> in
            .success(number * 10)
        }

        #expect(result == .success([50, 40, 30, 20, 10]))
    }

    @Test("traverse works with parsing scenario")
    func traverseParsingScenario() {
        let strings = ["1", "2", "3"]

        let result = strings.traverse { string -> Result<Int, TestError> in
            if let num = Int(string) {
                return .success(num)
            }
            return .failure(.parseError(string))
        }

        #expect(result == .success([1, 2, 3]))
    }

    @Test("traverse fails on invalid parse input")
    func traverseParsingFailure() {
        let strings = ["1", "not-a-number", "3"]

        let result = strings.traverse { string -> Result<Int, TestError> in
            if let num = Int(string) {
                return .success(num)
            }
            return .failure(.parseError(string))
        }

        #expect(result == .failure(.parseError("not-a-number")))
    }

    @Test("traverse with single element success")
    func traverseSingleElementSuccess() {
        let single = [42]

        let result = single.traverse { number -> Result<String, TestError> in
            .success("value-\(number)")
        }

        #expect(result == .success(["value-42"]))
    }

    @Test("traverse with single element failure")
    func traverseSingleElementFailure() {
        let single = [42]

        let result = single.traverse { _ -> Result<String, TestError> in
            .failure(.invalid)
        }

        #expect(result == .failure(.invalid))
    }

    // MARK: - traverseAsync

    @Test("traverseAsync succeeds when all async transformations succeed")
    func traverseAsyncAllSuccess() async {
        let numbers = [1, 2, 3, 4, 5]

        let result = await numbers.traverseAsync { number -> Result<String, TestError> in
            await Task.yield()
            return .success("num-\(number)")
        }

        #expect(result == .success(["num-1", "num-2", "num-3", "num-4", "num-5"]))
    }

    @Test("traverseAsync fails with first error encountered")
    func traverseAsyncFailsOnFirstError() async {
        let numbers = [1, 2, 3, 4, 5]

        let result = await numbers.traverseAsync { number -> Result<Int, TestError> in
            await Task.yield()
            if number == 3 {
                return .failure(.invalid)
            }
            return .success(number * 2)
        }

        #expect(result == .failure(.invalid))
    }

    @Test("traverseAsync stops processing after first failure")
    func traverseAsyncStopsAfterFailure() async {
        let counter = AsyncCounter()
        let numbers = [1, 2, 3, 4, 5]

        let result = await numbers.traverseAsync { number -> Result<Int, TestError> in
            await counter.increment()
            if number == 3 {
                return .failure(.notFound)
            }
            return .success(number)
        }

        let processedCount = await counter.count

        #expect(result == .failure(.notFound))
        #expect(processedCount == 3)
    }

    @Test("traverseAsync handles empty array")
    func traverseAsyncEmptyArray() async {
        let empty: [Int] = []

        let result = await empty.traverseAsync { number -> Result<String, TestError> in
            await Task.yield()
            return .success("\(number)")
        }

        #expect(result == .success([]))
    }

    @Test("traverseAsync preserves order with async operations")
    func traverseAsyncPreservesOrder() async {
        let numbers = [5, 4, 3, 2, 1]

        let result = await numbers.traverseAsync { number -> Result<Int, TestError> in
            await Task.yield()
            return .success(number * 10)
        }

        #expect(result == .success([50, 40, 30, 20, 10]))
    }

    @Test("traverseAsync works with actor-isolated operations")
    func traverseAsyncWithActor() async {
        let counter = AsyncCounter()
        let items = ["a", "b", "c"]

        let result = await items.traverseAsync { item -> Result<String, TestError> in
            let count = await counter.increment()
            return .success("\(item)-\(count)")
        }

        #expect(result == .success(["a-1", "b-2", "c-3"]))
    }

    @Test("traverseAsync simulates async validation")
    func traverseAsyncValidation() async {
        let userIds = [1, 2, 3]

        let result = await userIds.traverseAsync { userId -> Result<String, TestError> in
            await Task.yield()
            // Simulate async user lookup
            return .success("user-\(userId)")
        }

        #expect(result == .success(["user-1", "user-2", "user-3"]))
    }

    @Test("traverseAsync fails on async validation error")
    func traverseAsyncValidationFailure() async {
        let userIds = [1, 2, -1, 4]

        let result = await userIds.traverseAsync { userId -> Result<String, TestError> in
            await Task.yield()
            if userId < 0 {
                return .failure(.invalid)
            }
            return .success("user-\(userId)")
        }

        #expect(result == .failure(.invalid))
    }

    // MARK: - traverse (plain transform, Never failure)

    @Test("traverse with a plain transform always succeeds")
    func traversePlainTransform() {
        let numbers = [1, 2, 3]

        let result: Result<[Int], Never> = numbers.traverse { $0 * 2 }

        #expect(result == .success([2, 4, 6]))
    }

    @Test("traverseAsync with a plain transform always succeeds")
    func traverseAsyncPlainTransform() async {
        let numbers = [1, 2, 3]

        let result: Result<[String], Never> = await numbers.traverseAsync { n in
            await Task.yield()
            return "v\(n)"
        }

        #expect(result == .success(["v1", "v2", "v3"]))
    }

    // MARK: - traverseAsync (parallel)

    @Test("parallel traverseAsync preserves source order")
    func parallelTraversePreservesOrder() async {
        let numbers = [1, 2, 3, 4, 5, 6]

        let result = await numbers.traverseAsync(concurrency: .max) { n -> Result<Int, TestError> in
            // earlier elements are slower; order must still hold
            try? await Task.sleep(nanoseconds: UInt64((7 - n) * 10_000_000))
            return .success(n * 10)
        }

        #expect(result == .success([10, 20, 30, 40, 50, 60]))
    }

    @Test("parallel traverseAsync never exceeds the concurrency limit")
    func parallelTraverseRespectsConcurrencyLimit() async {
        let tracker = ConcurrencyTracker()
        let numbers = Array(1...10)

        let result = await numbers.traverseAsync(concurrency: 3) { n -> Result<Int, TestError> in
            await tracker.enter()
            try? await Task.sleep(nanoseconds: 20_000_000)
            await tracker.exit()
            return .success(n)
        }

        let highWater = await tracker.highWater
        #expect(result == .success(Array(1...10)))
        #expect(highWater <= 3)
    }

    @Test("parallel traverseAsync overlaps transforms")
    func parallelTraverseOverlaps() async {
        let tracker = ConcurrencyTracker()
        let numbers = [1, 2, 3, 4]

        let result = await numbers.traverseAsync(concurrency: .max) { n -> Result<Int, TestError> in
            await tracker.enter()
            try? await Task.sleep(nanoseconds: 50_000_000)
            await tracker.exit()
            return .success(n)
        }

        let highWater = await tracker.highWater
        #expect(result == .success([1, 2, 3, 4]))
        #expect(highWater >= 2)
    }

    @Test("parallel traverseAsync with concurrency 1 runs sequentially")
    func parallelTraverseConcurrencyOneIsSequential() async {
        let tracker = ConcurrencyTracker()
        let numbers = [1, 2, 3, 4]

        let result = await numbers.traverseAsync(concurrency: 1) { n -> Result<Int, TestError> in
            await tracker.enter()
            try? await Task.sleep(nanoseconds: 5_000_000)
            await tracker.exit()
            return .success(n)
        }

        let highWater = await tracker.highWater
        #expect(result == .success([1, 2, 3, 4]))
        #expect(highWater == 1)
    }

    @Test("parallel traverseAsync returns the lowest-index failure")
    func parallelTraverseReturnsLowestIndexFailure() async {
        let numbers = [0, 1, 2]

        let result = await numbers.traverseAsync(concurrency: 3) { n -> Result<Int, TestError> in
            if n == 0 {
                // slow failure at the lowest index
                try? await Task.sleep(nanoseconds: 60_000_000)
                return .failure(.invalid)
            }
            if n == 1 {
                // fast failure at a higher index
                return .failure(.notFound)
            }
            return .success(n)
        }

        #expect(result == .failure(.invalid))
    }

    @Test(
        "parallel traverseAsync stops starting transforms and cancels in flight on failure",
        .hangGuard
    )
    func parallelTraverseCancelsOnFailure() async {
        let started = AsyncCounter()
        let cancelled = AsyncCounter()
        let numbers = Array(0..<5)

        let result = await numbers.traverseAsync(concurrency: 2) { n -> Result<Int, TestError> in
            await started.increment()
            if n == 0 {
                return .failure(.invalid)
            }
            await waitForCancellation()
            await cancelled.increment()
            return .success(n)
        }

        let startedCount = await started.count
        let cancelledCount = await cancelled.count
        #expect(result == .failure(.invalid))
        // window of 2: elements 0 and 1 start; the failure stops the rest
        #expect(startedCount == 2)
        #expect(cancelledCount == 1)
    }

    @Test("parallel traverseAsync handles an empty array")
    func parallelTraverseEmptyArray() async {
        let empty: [Int] = []

        let result = await empty.traverseAsync(concurrency: 4) { n -> Result<Int, TestError> in
            .success(n)
        }

        #expect(result == .success([]))
    }

    @Test("parallel traverseAsync with a plain transform preserves order")
    func parallelTraversePlainTransform() async {
        let numbers = [1, 2, 3, 4]

        let result: Result<[String], Never> = await numbers.traverseAsync(concurrency: .max) { n in
            try? await Task.sleep(nanoseconds: UInt64((5 - n) * 10_000_000))
            return "v\(n)"
        }

        #expect(result == .success(["v1", "v2", "v3", "v4"]))
    }

    // MARK: - Long arrays

    // From 64 elements (128 for `separate`) the synchronous helpers write into the new array's
    // buffer, and skip elements without a branch when their values are trivial.

    /// A trivial error, so trivial results take the branchless path.
    enum Code: Error, Equatable {
        case even, odd
    }

    @Test(
        "successes, failures and separate keep every value in order at every size",
        arguments: [63, 64, 65, 127, 128, 129, 1_000]
    )
    func splittingLongArrays(count: Int) {
        let indices = 0..<count
        let failing = { (index: Int) in index.isMultiple(of: 3) }
        let codes = indices.map { index -> Result<Int, Code> in
            failing(index) ? .failure(index.isMultiple(of: 2) ? .even : .odd) : .success(index)
        }
        let strings = indices.map { index -> Result<String, TestError> in
            failing(index) ? .failure(.parseError("\(index)")) : .success("\(index)")
        }
        let successes = indices.filter { !failing($0) }
        let failures = indices.filter(failing)

        #expect(codes.successes() == successes)
        #expect(codes.failures() == failures.map { $0.isMultiple(of: 2) ? .even : .odd })
        #expect(codes.separate().successes == codes.successes())
        #expect(codes.separate().failures == codes.failures())

        #expect(strings.successes() == successes.map { "\($0)" })
        #expect(strings.failures() == failures.map { .parseError("\($0)") })
        #expect(strings.separate().successes == strings.successes())
        #expect(strings.separate().failures == strings.failures())
    }

    @Test("successes and failures of a long array with nothing on that side are empty")
    func splittingLongArraysWithOneSide() {
        let successes = [Result<Int, Code>](repeating: .success(1), count: 200)
        let failures = [Result<Int, Code>](repeating: .failure(.odd), count: 200)

        #expect(successes.failures().isEmpty)
        #expect(failures.successes().isEmpty)
        #expect(successes.separate().failures.isEmpty)
        #expect(failures.separate().successes.isEmpty)
    }

    @Test("traverse stops at a failure past 64 elements and releases the values made before it")
    func traverseLongArrayReleasesValuesBeforeAFailure() {
        final class Tracked {
            nonisolated(unsafe) static var live = 0
            init() { Self.live += 1 }
            deinit { Self.live -= 1 }
        }

        var calls = 0
        let result = Array(0..<200).traverse { index -> Result<Tracked, Code> in
            calls += 1
            return index == 150 ? .failure(.even) : .success(Tracked())
        }

        #expect(result.map(\.count) == .failure(.even))
        #expect(calls == 151)
        #expect(Tracked.live == 0)
    }

    @Test("traverse keeps every value in order at every size", arguments: [63, 64, 65, 1_000])
    func traverseLongArrays(count: Int) {
        let numbers = Array(0..<count)

        #expect(numbers.traverse { $0 &* 2 } == .success(numbers.map { $0 &* 2 }))
        #expect(
            numbers.traverse { Result<String, Code>.success("\($0)") }
                == .success(numbers.map { "\($0)" })
        )
        #expect(
            numbers.traverse { $0 == count - 1 ? .failure(Code.odd) : .success($0) }
                == .failure(.odd)
        )
    }
}
