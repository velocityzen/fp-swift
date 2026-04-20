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

    @Test("orElse returns self when self is some, regardless of alternative")
    func orElseSomeKeepsSelf() {
        let some: Int? = 1

        let altSome = some.orElse(2)
        let altNil = some.orElse(nil)

        #expect(altSome == 1)
        #expect(altNil == 1)
    }

    @Test("orElse returns alternative when self is nil")
    func orElseNilReturnsAlternative() {
        let none: Int? = nil

        let result = none.orElse(99)

        #expect(result == 99)
    }

    @Test("orElse chains through multiple nils")
    func orElseChainsThroughNils() {
        let first: String? = nil
        let second: String? = nil
        let third: String? = "found"

        let result = first.orElse(second).orElse(third)

        #expect(result == "found")
    }

    @Test("orElse does not evaluate alternative when self is some")
    func orElseDoesNotEvaluateOnSome() {
        let some: Int? = 1
        nonisolated(unsafe) var evaluated = false

        _ = some.orElse({
            evaluated = true
            return 2
        }())

        #expect(evaluated == false)
    }

    // MARK: - orElseAsync

    @Test("orElseAsync returns self when self is some")
    func orElseAsyncSomeKeepsSelf() async {
        let some: Int? = 1

        @Sendable func alt() async -> Int? {
            await Task.yield()
            return 2
        }

        let result = await some.orElseAsync(await alt())

        #expect(result == 1)
    }

    @Test("orElseAsync returns alternative when self is nil")
    func orElseAsyncNilReturnsAlternative() async {
        let none: Int? = nil

        @Sendable func alt() async -> Int? {
            await Task.yield()
            return 99
        }

        let result = await none.orElseAsync(await alt())

        #expect(result == 99)
    }

    @Test("orElseAsync does not evaluate alternative when self is some")
    func orElseAsyncDoesNotEvaluateOnSome() async {
        let some: Int? = 1
        let counter = AsyncCounter()

        @Sendable func alt(_ counter: AsyncCounter) async -> Int? {
            await counter.increment()
            return 2
        }

        _ = await some.orElseAsync(await alt(counter))

        let count = await counter.count
        #expect(count == 0)
    }

    // MARK: - getOrElse

    @Test("getOrElse returns wrapped value when self is some")
    func getOrElseSomeReturnsValue() {
        let some: Int? = 42

        let result = some.getOrElse(0)

        #expect(result == 42)
    }

    @Test("getOrElse returns default when self is nil")
    func getOrElseNilReturnsDefault() {
        let none: Int? = nil

        let result = none.getOrElse(99)

        #expect(result == 99)
    }

    @Test("getOrElse does not evaluate default when self is some")
    func getOrElseDoesNotEvaluateOnSome() {
        let some: Int? = 42
        nonisolated(unsafe) var evaluated = false

        _ = some.getOrElse({
            evaluated = true
            return 0
        }())

        #expect(evaluated == false)
    }

    // MARK: - getOrElseAsync

    @Test("getOrElseAsync returns wrapped value when self is some")
    func getOrElseAsyncSomeReturnsValue() async {
        let some: Int? = 42

        @Sendable func fallback() async -> Int {
            await Task.yield()
            return 0
        }

        let result = await some.getOrElseAsync(await fallback())

        #expect(result == 42)
    }

    @Test("getOrElseAsync awaits default when self is nil")
    func getOrElseAsyncNilAwaitsDefault() async {
        let none: Int? = nil

        @Sendable func fallback() async -> Int {
            await Task.yield()
            return 99
        }

        let result = await none.getOrElseAsync(await fallback())

        #expect(result == 99)
    }

    @Test("getOrElseAsync does not evaluate default when self is some")
    func getOrElseAsyncDoesNotEvaluateOnSome() async {
        let some: Int? = 42
        let counter = AsyncCounter()

        @Sendable func fallback(_ counter: AsyncCounter) async -> Int {
            await counter.increment()
            return 0
        }

        _ = await some.getOrElseAsync(await fallback(counter))

        let count = await counter.count
        #expect(count == 0)
    }
}
