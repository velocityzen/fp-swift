import Testing

@testable import FP

@Suite("Optional+match Tests")
struct OptionalMatchTests {

    // MARK: - match

    @Test("match calls onSome for some value")
    func matchCallsOnSomeForSome() {
        let optional: Int? = 42

        let result = optional.match(
            { "value: \($0)" },
            "none"
        )

        #expect(result == "value: 42")
    }

    @Test("match returns onNone for nil")
    func matchReturnsOnNoneForNil() {
        let optional: Int? = nil

        let result = optional.match(
            { "value: \($0)" },
            "none"
        )

        #expect(result == "none")
    }

    @Test("match works for side effects")
    func matchWorksForSideEffects() {
        var called = false
        let optional: Int? = 42

        optional.match(
            { _ in called = true },
            ()
        )

        #expect(called == true)
    }

    @Test("match does not call onSome for nil")
    func matchDoesNotCallOnSomeForNil() {
        var called = false
        let optional: Int? = nil

        optional.match(
            { _ in called = true },
            ()
        )

        #expect(called == false)
    }

    // MARK: - matchAsync

    @Test("matchAsync calls onSome for some value")
    func matchAsyncCallsOnSomeForSome() async {
        let optional: Int? = 42

        let result = await optional.matchAsync(
            { value async -> String in
                await Task.yield()
                return "value: \(value)"
            },
            "none"
        )

        #expect(result == "value: 42")
    }

    @Test("matchAsync returns onNone for nil")
    func matchAsyncReturnsOnNoneForNil() async {
        let optional: Int? = nil

        let result = await optional.matchAsync(
            { value async -> String in
                await Task.yield()
                return "value: \(value)"
            },
            "none"
        )

        #expect(result == "none")
    }

    @Test("matchAsync does not call onSome for nil")
    func matchAsyncDoesNotCallOnSomeForNil() async {
        let counter = AsyncCounter()
        let optional: Int? = nil

        _ = await optional.matchAsync(
            { _ async -> Int in
                await counter.increment()
            },
            0
        )

        let count = await counter.count
        #expect(count == 0)
    }
}
