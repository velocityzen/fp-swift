import Testing

@testable import FP

@Suite("AsyncStream+Result Tests")
struct AsyncStreamResultTests {
    enum TestError: Error, Equatable {
        case failed
        case other
    }

    // MARK: - success(_:)

    @Test("success yields a success result")
    func successYieldsResult() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.success(42)
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream {
            results.append(result)
        }

        #expect(results.count == 1)
        #expect(results[0] == .success(42))
    }

    @Test("success can yield multiple values")
    func successYieldsMultipleValues() async {
        let stream = AsyncStream<Result<String, TestError>> { continuation in
            continuation.success("first")
            continuation.success("second")
            continuation.success("third")
            continuation.finish()
        }

        var values: [String] = []
        for await result in stream {
            if case .success(let value) = result {
                values.append(value)
            }
        }

        #expect(values == ["first", "second", "third"])
    }

    // MARK: - failure(_:)

    @Test("failure yields a failure result")
    func failureYieldsResult() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.failure(TestError.failed)
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream {
            results.append(result)
        }

        #expect(results.count == 1)
        #expect(results[0] == .failure(.failed))
    }

    @Test("failure can yield multiple errors")
    func failureYieldsMultipleErrors() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.failure(TestError.failed)
            continuation.failure(TestError.other)
            continuation.finish()
        }

        var errors: [TestError] = []
        for await result in stream {
            if case .failure(let error) = result {
                errors.append(error)
            }
        }

        #expect(errors == [.failed, .other])
    }

    // MARK: - Mixed success and failure

    @Test("can interleave success and failure results")
    func mixedSuccessAndFailure() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.success(1)
            continuation.failure(TestError.failed)
            continuation.success(2)
            continuation.failure(TestError.other)
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream {
            results.append(result)
        }

        #expect(results.count == 4)
        #expect(results[0] == .success(1))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .success(2))
        #expect(results[3] == .failure(.other))
    }

    // MARK: - finishWithSuccess(_:)

    @Test("finishWithSuccess yields value and finishes stream")
    func finishWithSuccessYieldsAndFinishes() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.finishWithSuccess(100)
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream {
            results.append(result)
        }

        #expect(results.count == 1)
        #expect(results[0] == .success(100))
    }

    @Test("finishWithSuccess after other yields")
    func finishWithSuccessAfterYields() async {
        let stream = AsyncStream<Result<String, TestError>> { continuation in
            continuation.success("first")
            continuation.success("second")
            continuation.finishWithSuccess("final")
        }

        var values: [String] = []
        for await result in stream {
            if case .success(let value) = result {
                values.append(value)
            }
        }

        #expect(values == ["first", "second", "final"])
    }

    // MARK: - finishWithFailure(_:)

    @Test("finishWithFailure yields error and finishes stream")
    func finishWithFailureYieldsAndFinishes() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.finishWithFailure(TestError.failed)
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream {
            results.append(result)
        }

        #expect(results.count == 1)
        #expect(results[0] == .failure(.failed))
    }

    @Test("finishWithFailure after other yields")
    func finishWithFailureAfterYields() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.success(1)
            continuation.success(2)
            continuation.finishWithFailure(TestError.failed)
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream {
            results.append(result)
        }

        #expect(results.count == 3)
        #expect(results[0] == .success(1))
        #expect(results[1] == .success(2))
        #expect(results[2] == .failure(.failed))
    }

    // MARK: - YieldResult verification

    @Test("success returns YieldResult")
    func successReturnsYieldResult() async {
        var yieldResult: AsyncStream<Result<Int, TestError>>.Continuation.YieldResult?

        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            yieldResult = continuation.success(42)
            continuation.finish()
        }

        // Consume stream to trigger continuation
        for await _ in stream {}

        if case .enqueued = yieldResult {
            // Success - yielded value was enqueued
        } else {
            Issue.record("Expected .enqueued but got \(String(describing: yieldResult))")
        }
    }

    @Test("failure returns YieldResult")
    func failureReturnsYieldResult() async {
        var yieldResult: AsyncStream<Result<Int, TestError>>.Continuation.YieldResult?

        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            yieldResult = continuation.failure(TestError.failed)
            continuation.finish()
        }

        // Consume stream to trigger continuation
        for await _ in stream {}

        if case .enqueued = yieldResult {
            // Success - yielded value was enqueued
        } else {
            Issue.record("Expected .enqueued but got \(String(describing: yieldResult))")
        }
    }
}
