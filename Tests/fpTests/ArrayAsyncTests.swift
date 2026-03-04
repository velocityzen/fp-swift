import Testing

@testable import FP

@Suite("Array+Async Tests")
struct ArrayAsyncTests {
    // MARK: - mapAsync (non-throwing)

    @Test("mapAsync transforms all elements with async operations")
    func mapAsyncTransformsElements() async {
        let numbers = [1, 2, 3]

        let result = await numbers.mapAsync { number -> String in
            await Task.yield()
            return "n-\(number)"
        }

        #expect(result == ["n-1", "n-2", "n-3"])
    }

    @Test("mapAsync handles empty array")
    func mapAsyncEmptyArray() async {
        let empty: [Int] = []

        let result = await empty.mapAsync { number -> String in
            await Task.yield()
            return "\(number)"
        }

        #expect(result.isEmpty)
    }

    @Test("mapAsync preserves order with async operations")
    func mapAsyncPreservesOrder() async {
        let numbers = [5, 1, 4, 2, 3]

        let result = await numbers.mapAsync { number -> Int in
            await Task.yield()
            return number * 10
        }

        #expect(result == [50, 10, 40, 20, 30])
    }

    @Test("mapAsync works with actor-isolated async calls")
    func mapAsyncWithActor() async {
        let counter = AsyncCounter()
        let items = ["a", "b", "c"]

        let result = await items.mapAsync { item -> String in
            let count = await counter.increment()
            return "\(item)-\(count)"
        }

        #expect(result == ["a-1", "b-2", "c-3"])
    }

    // MARK: - mapAsync (Result)

    @Test("mapAsync result variant transforms all elements with async operations")
    func mapAsyncResultTransformsElements() async {
        struct ParseError: Error, Equatable {}
        let strings = ["1", "2", "3"]

        let result = await strings.mapAsync { string -> Result<Int, ParseError> in
            await Task.yield()
            guard let value = Int(string) else {
                return .failure(ParseError())
            }
            return .success(value)
        }

        #expect(result == .success([1, 2, 3]))
    }

    @Test("mapAsync result variant returns first failure from async operations")
    func mapAsyncResultPropagatesError() async {
        struct TestError: Error, Equatable {}
        let numbers = [1, 2, 3]

        let result = await numbers.mapAsync { number -> Result<Int, TestError> in
            await Task.yield()
            if number == 2 {
                return .failure(TestError())
            }
            return .success(number)
        }

        #expect(result == .failure(TestError()))
    }

    @Test("mapAsync result variant handles empty array")
    func mapAsyncResultEmptyArray() async {
        struct TestError: Error, Equatable {}
        let empty: [Int] = []

        let result = await empty.mapAsync { number -> Result<String, TestError> in
            await Task.yield()
            return .success("\(number)")
        }

        #expect(result == .success([]))
    }

    // MARK: - flatMapAsync (non-throwing)

    @Test("flatMapAsync transforms and flattens async results")
    func flatMapAsyncFlattens() async {
        let numbers = [1, 2, 3]

        let result = await numbers.flatMapAsync { number -> [Int] in
            await Task.yield()
            return [number, number * 10]
        }

        #expect(result == [1, 10, 2, 20, 3, 30])
    }

    @Test("flatMapAsync handles empty array")
    func flatMapAsyncEmptyArray() async {
        let empty: [Int] = []

        let result = await empty.flatMapAsync { number -> [String] in
            await Task.yield()
            return ["\(number)"]
        }

        #expect(result.isEmpty)
    }

    @Test("flatMapAsync preserves flatten order with async operations")
    func flatMapAsyncPreservesOrder() async {
        let items = ["ab", "c", ""]

        let result = await items.flatMapAsync { item -> [Character] in
            await Task.yield()
            return Array(item)
        }

        #expect(result == ["a", "b", "c"])
    }

    // MARK: - flatMapAsync (Result)

    @Test("flatMapAsync result variant transforms and flattens async results")
    func flatMapAsyncResultFlattens() async {
        struct TestError: Error, Equatable {}
        let numbers = [1, 2, 3]

        let result = await numbers.flatMapAsync { number -> Result<[Int], TestError> in
            await Task.yield()
            return .success([number, number * 10])
        }

        #expect(result == .success([1, 10, 2, 20, 3, 30]))
    }

    @Test("flatMapAsync result variant returns first failure from async operations")
    func flatMapAsyncResultPropagatesError() async {
        struct TestError: Error, Equatable {}
        let numbers = [1, 2, 3]

        let result = await numbers.flatMapAsync { number -> Result<[Int], TestError> in
            await Task.yield()
            if number == 2 {
                return .failure(TestError())
            }
            return .success([number])
        }

        #expect(result == .failure(TestError()))
    }

    @Test("flatMapAsync result variant handles empty array")
    func flatMapAsyncResultEmptyArray() async {
        struct TestError: Error, Equatable {}
        let empty: [Int] = []

        let result = await empty.flatMapAsync { number -> Result<[String], TestError> in
            await Task.yield()
            return .success(["\(number)"])
        }

        #expect(result == .success([]))
    }

    // MARK: - compactMapAsync (non-throwing)

    @Test("compactMapAsync transforms and filters nil values with async operations")
    func compactMapAsyncFiltersNils() async {
        let numbers = [1, 2, 3, 4, 5]

        let result = await numbers.compactMapAsync { number -> String? in
            await Task.yield()
            return number.isMultiple(of: 2) ? "even-\(number)" : nil
        }

        #expect(result == ["even-2", "even-4"])
    }

    @Test("compactMapAsync returns empty array when all transforms return nil")
    func compactMapAsyncAllNil() async {
        let numbers = [1, 2, 3]

        let result = await numbers.compactMapAsync { _ -> Int? in
            await Task.yield()
            return nil
        }

        #expect(result.isEmpty)
    }

    @Test("compactMapAsync returns all elements when none are nil")
    func compactMapAsyncNoNils() async {
        let numbers = [1, 2, 3]

        let result = await numbers.compactMapAsync { number -> Int? in
            await Task.yield()
            return number * 2
        }

        #expect(result == [2, 4, 6])
    }

    @Test("compactMapAsync handles empty array")
    func compactMapAsyncEmptyArray() async {
        let empty: [Int] = []

        let result = await empty.compactMapAsync { number -> String? in
            await Task.yield()
            return "\(number)"
        }

        #expect(result.isEmpty)
    }

    @Test("compactMapAsync preserves order with async operations")
    func compactMapAsyncPreservesOrder() async {
        let numbers = [5, 4, 3, 2, 1]

        let result = await numbers.compactMapAsync { number -> Int? in
            await Task.yield()
            return number
        }

        #expect(result == [5, 4, 3, 2, 1])
    }

    @Test("compactMapAsync works with actor-isolated async calls")
    func compactMapAsyncWithActor() async {
        let counter = AsyncCounter()
        let items = ["a", "b", "c"]

        let result = await items.compactMapAsync { item -> String? in
            let count = await counter.increment()
            return "\(item)-\(count)"
        }

        #expect(result == ["a-1", "b-2", "c-3"])
    }

    @Test("compactMapAsync handles mixed nil results from async operations")
    func compactMapAsyncMixedResults() async {
        let urls = ["https://valid.com", "", "https://another.com", "   "]

        let result = await urls.compactMapAsync { urlString -> String? in
            await Task.yield()
            let trimmed = urlString.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }

        #expect(result == ["https://valid.com", "https://another.com"])
    }

    // MARK: - compactMapAsync (Result)

    @Test("compactMapAsync result variant transforms with async operations")
    func compactMapAsyncResultFiltersNils() async {
        struct TestError: Error, Equatable {}
        let numbers = [1, 2, 3, 4, 5]

        let result = await numbers.compactMapAsync { number -> Result<String?, TestError> in
            await Task.yield()
            return .success(number.isMultiple(of: 2) ? "even-\(number)" : nil)
        }

        #expect(result == .success(["even-2", "even-4"]))
    }

    @Test("compactMapAsync result variant returns first failure from async operations")
    func compactMapAsyncResultPropagatesError() async {
        struct TestError: Error, Equatable {}
        let numbers = [1, 2, 3]

        let result = await numbers.compactMapAsync { number -> Result<Int?, TestError> in
            await Task.yield()
            if number == 2 {
                return .failure(TestError())
            }
            return .success(number)
        }

        #expect(result == .failure(TestError()))
    }

    @Test("compactMapAsync result variant succeeds with async parsing")
    func compactMapAsyncResultSucceeds() async {
        struct TestError: Error, Equatable {}
        let strings = ["1", "2", "invalid", "3"]

        let result = await strings.compactMapAsync { string -> Result<Int?, TestError> in
            await Task.yield()
            return .success(Int(string))
        }

        #expect(result == .success([1, 2, 3]))
    }

    @Test("compactMapAsync result variant handles empty array")
    func compactMapAsyncResultEmptyArray() async {
        struct TestError: Error, Equatable {}
        let empty: [Int] = []

        let result = await empty.compactMapAsync { number -> Result<String?, TestError> in
            await Task.yield()
            return .success("\(number)")
        }

        #expect(result == .success([]))
    }

    @Test("compactMapAsync result variant works with actor and typed failures")
    func compactMapAsyncResultWithActor() async {
        struct ValidationError: Error, Equatable {}
        let counter = AsyncCounter()
        let items = [1, 2, 3]

        let result = await items.compactMapAsync { item -> Result<String?, ValidationError> in
            let count = await counter.increment()
            if count > 10 {
                return .failure(ValidationError())
            }
            return .success(item.isMultiple(of: 2) ? nil : "item-\(count)")
        }

        #expect(result == .success(["item-1", "item-3"]))
    }
}
