import Testing

@testable import FP

@Suite("AsyncSequence+Result Tests")
struct AsyncSequenceResultTests {
    enum TestError: Error, Equatable {
        case failed
        case other
    }

    // MARK: - successes()

    @Test("successes filters and unwraps success values")
    func successesFiltersSuccessValues() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.yield(.success(3))
            continuation.yield(.failure(.other))
            continuation.finish()
        }

        var values: [Int] = []
        for await value in stream.successes() {
            values.append(value)
        }

        #expect(values == [1, 2, 3])
    }

    @Test("successes returns empty for all failures")
    func successesEmptyForAllFailures() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.failure(.failed))
            continuation.yield(.failure(.other))
            continuation.finish()
        }

        var values: [Int] = []
        for await value in stream.successes() {
            values.append(value)
        }

        #expect(values.isEmpty)
    }

    // MARK: - failures()

    @Test("failures filters and unwraps failure errors")
    func failuresFiltersFailureErrors() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.yield(.failure(.other))
            continuation.finish()
        }

        var errors: [TestError] = []
        for await error in stream.failures() {
            errors.append(error)
        }

        #expect(errors == [.failed, .other])
    }

    @Test("failures returns empty for all successes")
    func failuresEmptyForAllSuccesses() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.success(2))
            continuation.finish()
        }

        var errors: [TestError] = []
        for await error in stream.failures() {
            errors.append(error)
        }

        #expect(errors.isEmpty)
    }

    // MARK: - map

    @Test("map transforms success values")
    func mapTransformsValues() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.finish()
        }

        var results: [Result<String, TestError>] = []
        for await result in stream.map({ "v\($0)" }) {
            results.append(result)
        }

        #expect(results.count == 3)
        #expect(results[0] == .success("v1"))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .success("v2"))
    }

    // MARK: - mapFailure

    @Test("mapFailure transforms failure errors")
    func mapFailureTransformsErrors() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.mapFailure({ _ in TestError.other }) {
            results.append(result)
        }

        #expect(results.count == 3)
        #expect(results[0] == .success(1))
        #expect(results[1] == .failure(.other))
        #expect(results[2] == .success(2))
    }

    // MARK: - flatMap

    @Test("flatMap transforms success values with Result-returning closure")
    func flatMapTransformsValues() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(0))
            continuation.finish()
        }

        var results: [Result<String, TestError>] = []
        for await result in stream.flatMap({ value in
            value > 0 ? .success("v\(value)") : .failure(.other)
        }) {
            results.append(result)
        }

        #expect(results.count == 3)
        #expect(results[0] == .success("v1"))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .failure(.other))
    }

    // MARK: - mapAsync

    @Test("mapAsync asynchronously transforms success values")
    func mapAsyncTransformsValues() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.finish()
        }

        var results: [Result<String, TestError>] = []
        for await result in stream.mapAsync({ value in
            await Task.yield()
            return "v\(value)"
        }) {
            results.append(result)
        }

        #expect(results.count == 3)
        #expect(results[0] == .success("v1"))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .success("v2"))
    }

    // MARK: - mapFailureAsync

    @Test("mapFailureAsync asynchronously transforms failure errors")
    func mapFailureAsyncTransformsErrors() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.mapFailureAsync({ _ in
            await Task.yield()
            return TestError.other
        }) {
            results.append(result)
        }

        #expect(results.count == 3)
        #expect(results[0] == .success(1))
        #expect(results[1] == .failure(.other))
        #expect(results[2] == .success(2))
    }

    // MARK: - flatMapAsync

    @Test("flatMapAsync asynchronously transforms success values with Result-returning closure")
    func flatMapAsyncTransformsValues() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(0))
            continuation.finish()
        }

        var results: [Result<String, TestError>] = []
        for await result in stream.flatMapAsync({ value in
            await Task.yield()
            return value > 0 ? .success("v\(value)") : .failure(.other)
        }) {
            results.append(result)
        }

        #expect(results.count == 3)
        #expect(results[0] == .success("v1"))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .failure(.other))
    }

    // MARK: - tap

    @Test("tap performs side effect on success values")
    func tapPerformsSideEffect() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.finish()
        }

        nonisolated(unsafe) var tapCount = 0
        var results: [Result<Int, TestError>] = []
        for await result in stream.tap({ _ in tapCount += 1 }) {
            results.append(result)
        }

        #expect(tapCount == 2)
        #expect(results.count == 3)
        #expect(results[0] == .success(1))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .success(2))
    }

    // MARK: - tapAsync

    @Test("tapAsync asynchronously performs side effect on success values")
    func tapAsyncPerformsSideEffect() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.finish()
        }

        let counter = AsyncCounter()
        var results: [Result<Int, TestError>] = []
        for await result in stream.tapAsync({ _ in await counter.increment() }) {
            results.append(result)
        }

        let count = await counter.count
        #expect(count == 2)
        #expect(results.count == 3)
        #expect(results[0] == .success(1))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .success(2))
    }

    // MARK: - tapError

    @Test("tapError performs side effect on failure errors")
    func tapErrorPerformsSideEffect() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.yield(.failure(.other))
            continuation.finish()
        }

        nonisolated(unsafe) var tapCount = 0
        var results: [Result<Int, TestError>] = []
        for await result in stream.tapError({ _ in tapCount += 1 }) {
            results.append(result)
        }

        #expect(tapCount == 2)
        #expect(results.count == 4)
        #expect(results[0] == .success(1))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .success(2))
        #expect(results[3] == .failure(.other))
    }

    // MARK: - tapErrorAsync

    @Test("tapErrorAsync asynchronously performs side effect on failure errors")
    func tapErrorAsyncPerformsSideEffect() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.yield(.failure(.other))
            continuation.finish()
        }

        let counter = AsyncCounter()
        var results: [Result<Int, TestError>] = []
        for await result in stream.tapErrorAsync({ _ in await counter.increment() }) {
            results.append(result)
        }

        let count = await counter.count
        #expect(count == 2)
        #expect(results.count == 4)
        #expect(results[0] == .success(1))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .success(2))
        #expect(results[3] == .failure(.other))
    }
}
