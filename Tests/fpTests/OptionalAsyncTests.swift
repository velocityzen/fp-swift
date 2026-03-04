import Testing

@testable import FP

@Suite("Optional+Async Tests")
struct OptionalAsyncTests {
    // MARK: - mapAsync (non-throwing)

    @Test("mapAsync transforms some value with async operation")
    func mapAsyncTransformsSome() async {
        let optional: Int? = 42

        let result = await optional.mapAsync { value -> String in
            await Task.yield()
            return "value-\(value)"
        }

        #expect(result == "value-42")
    }

    @Test("mapAsync returns nil for none")
    func mapAsyncReturnsNilForNone() async {
        let optional: Int? = nil

        let result = await optional.mapAsync { value -> String in
            await Task.yield()
            return "value-\(value)"
        }

        #expect(result == nil)
    }

    @Test("mapAsync works with actor-isolated operations")
    func mapAsyncWithActor() async {
        let counter = AsyncCounter()
        let optional: String? = "test"

        let result = await optional.mapAsync { value -> String in
            let count = await counter.increment()
            return "\(value)-\(count)"
        }

        #expect(result == "test-1")
    }

    @Test("mapAsync does not call transform for nil")
    func mapAsyncDoesNotCallTransformForNil() async {
        let counter = AsyncCounter()
        let optional: Int? = nil

        _ = await optional.mapAsync { value -> Int in
            await counter.increment()
            return value
        }

        let count = await counter.count
        #expect(count == 0)
    }

    @Test("mapAsync can change type")
    func mapAsyncChangesType() async {
        let optional: String? = "123"

        let result = await optional.mapAsync { value -> Int? in
            await Task.yield()
            return Int(value)
        }

        #expect(result == 123)
    }

    // MARK: - flatMapAsync (non-throwing)

    @Test("flatMapAsync transforms some value with async optional operation")
    func flatMapAsyncTransformsSome() async {
        let optional: String? = "123"

        let result = await optional.flatMapAsync { value -> Int? in
            await Task.yield()
            return Int(value)
        }

        #expect(result == 123)
    }

    @Test("flatMapAsync returns nil for none")
    func flatMapAsyncReturnsNilForNone() async {
        let optional: Int? = nil

        let result = await optional.flatMapAsync { value -> String? in
            await Task.yield()
            return "value-\(value)"
        }

        #expect(result == nil)
    }

    @Test("flatMapAsync does not call transform for nil")
    func flatMapAsyncDoesNotCallTransformForNil() async {
        let counter = AsyncCounter()
        let optional: Int? = nil

        _ = await optional.flatMapAsync { value -> Int? in
            await counter.increment()
            return value
        }

        let count = await counter.count
        #expect(count == 0)
    }

    @Test("flatMapAsync works with actor-isolated operations")
    func flatMapAsyncWithActor() async {
        let counter = AsyncCounter()
        let optional: String? = "test"

        let result = await optional.flatMapAsync { value -> String? in
            let count = await counter.increment()
            return "\(value)-\(count)"
        }

        #expect(result == "test-1")
    }

    // MARK: - orElse

    @Test("orElse returns default value for nil")
    func orElseReturnsDefaultForNil() {
        let optional: Int? = nil

        let result = optional.orElse(99)

        #expect(result == 99)
    }

    @Test("orElse returns nil for some value")
    func orElseReturnsNilForSome() {
        let optional: Int? = 42

        let result = optional.orElse(99)

        #expect(result == nil)
    }

    @Test("orElse with string type")
    func orElseWithString() {
        let optional: String? = nil

        let result = optional.orElse("default")

        #expect(result == "default")
    }

    @Test("orElse returns nil when value exists")
    func orElseNilWhenValueExists() {
        let optional: String? = "exists"

        let result = optional.orElse("default")

        #expect(result == nil)
    }
}
