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
}
