import Testing

@testable import FP

@Suite("Result+match Tests")
struct ResultMatchTests {
    enum TestError: Error, Equatable {
        case invalid
        case notFound
    }

    // MARK: - match (sync)

    @Test("match transforms success value")
    func matchTransformsSuccess() {
        let result: Result<Int, TestError> = .success(42)

        let value = result.match(
            { "value-\($0)" },
            { _ in "failure" }
        )

        #expect(value == "value-42")
    }

    @Test("match transforms failure value")
    func matchTransformsFailure() {
        let result: Result<Int, TestError> = .failure(.invalid)

        let value = result.match(
            { _ in "success" },
            { error in "error-\(error)" }
        )

        #expect(value == "error-invalid")
    }

    @Test("match does not call other branch")
    func matchDoesNotCallOtherBranch() {
        var count = 0
        let result: Result<Int, TestError> = .success(1)

        let value = result.match(
            { value in
                count += value
                return "ok"
            },
            { _ in
                count += 10
                return "fail"
            }
        )

        #expect(value == "ok")
        #expect(count == 1)
    }

    // MARK: - match (autoclosure)

    @Test("match autoclosure uses success value")
    func matchAutoclosureSuccess() {
        let result: Result<Int, TestError> = .success(42)

        let value = result.match("ok", "fail")

        #expect(value == "ok")
    }

    @Test("match autoclosure uses failure value")
    func matchAutoclosureFailure() {
        let result: Result<Int, TestError> = .failure(.invalid)

        let value = result.match("ok", "fail")

        #expect(value == "fail")
    }

    @Test("match autoclosure does not evaluate other branch")
    func matchAutoclosureDoesNotEvaluateOtherBranch() {
        var count = 0

        func add(_ delta: Int) -> Int {
            count += delta
            return count
        }

        let result: Result<Int, TestError> = .success(0)
        let value = result.match(add(1), add(10))

        #expect(value == 1)
        #expect(count == 1)
    }

    @Test("match supports success closure with failure constant")
    func matchSuccessClosureFailureConstant() {
        let result: Result<Int, TestError> = .success(2)

        let value = result.match(
            { "\($0 * 2)" },
            "error"
        )

        #expect(value == "4")
    }

    @Test("match supports success constant with failure closure")
    func matchSuccessConstantFailureClosure() {
        let result: Result<Int, TestError> = .failure(.notFound)

        let value = result.match(
            "ok",
            { "error-\($0)" }
        )

        #expect(value == "error-notFound")
    }

    // MARK: - match (discardable result)

    @Test("match result can be discarded with closures")
    func matchDiscardableClosures() {
        var sideEffect = ""
        let result: Result<Int, TestError> = .success(42)

        result.match(
            { sideEffect = "success-\($0)" },
            { sideEffect = "failure-\($0)" }
        )

        #expect(sideEffect == "success-42")
    }

    @Test("match result can be discarded with autoclosures")
    func matchDiscardableAutoclosures() {
        let result: Result<Int, TestError> = .success(42)
        result.match("ok", "fail")
    }

    @Test("match result can be discarded with mixed closure and constant")
    func matchDiscardableMixed() {
        var sideEffect = ""
        let result: Result<Int, TestError> = .failure(.invalid)

        result.match(
            { value in
                sideEffect = "success-\(value)"
                return "ok"
            },
            "fail"
        )

        #expect(sideEffect == "")
    }

    // MARK: - matchAsync

    @Test("matchAsync transforms success value")
    func matchAsyncTransformsSuccess() async {
        let result: Result<Int, TestError> = .success(42)

        let value = await result.matchAsync(
            { value in
                await Task.yield()
                return "value-\(value)"
            },
            { _ in
                await Task.yield()
                return "failure"
            }
        )

        #expect(value == "value-42")
    }

    @Test("matchAsync transforms failure value")
    func matchAsyncTransformsFailure() async {
        let result: Result<Int, TestError> = .failure(.notFound)

        let value = await result.matchAsync(
            { _ in
                await Task.yield()
                return "success"
            },
            { error in
                await Task.yield()
                return "error-\(error)"
            }
        )

        #expect(value == "error-notFound")
    }

    @Test("matchAsync does not call other branch")
    func matchAsyncDoesNotCallOtherBranch() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .failure(.invalid)

        let value = await result.matchAsync(
            { _ in
                await counter.increment()
                return "success"
            },
            { _ in
                await Task.yield()
                return "failure"
            }
        )

        let count = await counter.count
        #expect(value == "failure")
        #expect(count == 0)
    }

    @Test("matchAsync supports success closure with failure constant")
    func matchAsyncSuccessClosureFailureConstant() async {
        let result: Result<Int, TestError> = .success(3)

        let value = await result.matchAsync(
            { value in
                await Task.yield()
                return "value-\(value)"
            },
            "error"
        )

        #expect(value == "value-3")
    }

    @Test("matchAsync supports success constant with failure closure")
    func matchAsyncSuccessConstantFailureClosure() async {
        let result: Result<Int, TestError> = .failure(.invalid)

        let value = await result.matchAsync(
            "ok",
            { error in
                await Task.yield()
                return "error-\(error)"
            }
        )

        #expect(value == "error-invalid")
    }

    // MARK: - matchAsync (discardable result)

    @Test("matchAsync result can be discarded with closures")
    func matchAsyncDiscardableClosures() async {
        var sideEffect = ""
        let result: Result<Int, TestError> = .success(42)

        await result.matchAsync(
            { value in
                await Task.yield()
                sideEffect = "success-\(value)"
            },
            { error in
                await Task.yield()
                sideEffect = "failure-\(error)"
            }
        )

        #expect(sideEffect == "success-42")
    }

    @Test("matchAsync result can be discarded with mixed closure and constant")
    func matchAsyncDiscardableMixed() async {
        var sideEffect = ""
        let result: Result<Int, TestError> = .failure(.invalid)

        await result.matchAsync(
            "ok",
            { error in
                await Task.yield()
                sideEffect = "failure-\(error)"
                return "fail"
            }
        )

        #expect(sideEffect == "failure-invalid")
    }
}
