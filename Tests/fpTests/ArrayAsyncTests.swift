import Testing

@testable import FP

@Suite("Array+Async Tests")
struct ArrayAsyncTests {
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

    // MARK: - compactMapAsync (throwing)

    @Test("compactMapAsync throwing variant transforms with async operations")
    func compactMapAsyncThrowingFiltersNils() async throws {
        let numbers = [1, 2, 3, 4, 5]

        let result = try await numbers.compactMapAsync { number async throws -> String? in
            await Task.yield()
            return number.isMultiple(of: 2) ? "even-\(number)" : nil
        }

        #expect(result == ["even-2", "even-4"])
    }

    @Test("compactMapAsync throwing variant propagates errors from async operations")
    func compactMapAsyncThrowingPropagatesError() async {
        struct TestError: Error, Equatable {}
        let numbers = [1, 2, 3]

        await #expect(throws: TestError.self) {
            _ = try await numbers.compactMapAsync { number async throws -> Int? in
                await Task.yield()
                if number == 2 {
                    throw TestError()
                }
                return number
            }
        }
    }

    @Test("compactMapAsync throwing variant succeeds with async parsing")
    func compactMapAsyncThrowingSucceeds() async throws {
        let strings = ["1", "2", "invalid", "3"]

        let result = try await strings.compactMapAsync { string async throws -> Int? in
            await Task.yield()
            return Int(string)
        }

        #expect(result == [1, 2, 3])
    }

    @Test("compactMapAsync throwing variant handles empty array")
    func compactMapAsyncThrowingEmptyArray() async throws {
        let empty: [Int] = []

        let result = try await empty.compactMapAsync { number async throws -> String? in
            await Task.yield()
            return "\(number)"
        }

        #expect(result.isEmpty)
    }

    @Test("compactMapAsync throwing variant works with actor and can throw")
    func compactMapAsyncThrowingWithActor() async throws {
        struct ValidationError: Error {}
        let counter = AsyncCounter()
        let items = [1, 2, 3]

        let result = try await items.compactMapAsync { item async throws -> String? in
            let count = await counter.increment()
            if count > 10 {
                throw ValidationError()
            }
            return item.isMultiple(of: 2) ? nil : "item-\(count)"
        }

        #expect(result == ["item-1", "item-3"])
    }
}
