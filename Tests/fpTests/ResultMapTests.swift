import Testing

@testable import fp_swift

@Suite("Result+map Tests")
struct ResultMapTests {
    enum TestError: Error, Equatable {
        case invalid
        case notFound
    }

    // MARK: - mapAsync (non-throwing)

    @Test("mapAsync transforms success value with async operation")
    func mapAsyncTransformsSuccess() async {
        let result: Result<Int, TestError> = .success(42)

        let mapped = await result.mapAsync { value -> String in
            await Task.yield()
            return "value-\(value)"
        }

        #expect(mapped == .success("value-42"))
    }

    @Test("mapAsync preserves failure")
    func mapAsyncPreservesFailure() async {
        let result: Result<Int, TestError> = .failure(.invalid)

        let mapped = await result.mapAsync { value -> String in
            await Task.yield()
            return "value-\(value)"
        }

        #expect(mapped == .failure(.invalid))
    }

    @Test("mapAsync does not call transform for failure")
    func mapAsyncDoesNotCallTransformForFailure() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .failure(.notFound)

        _ = await result.mapAsync { value -> Int in
            await counter.increment()
            return value
        }

        let count = await counter.count
        #expect(count == 0)
    }

    @Test("mapAsync works with actor-isolated operations")
    func mapAsyncWithActor() async {
        let counter = AsyncCounter()
        let result: Result<String, TestError> = .success("test")

        let mapped = await result.mapAsync { value -> String in
            let count = await counter.increment()
            return "\(value)-\(count)"
        }

        #expect(mapped == .success("test-1"))
    }

    @Test("mapAsync can change success type")
    func mapAsyncChangesType() async {
        let result: Result<String, TestError> = .success("123")

        let mapped = await result.mapAsync { value -> Int? in
            await Task.yield()
            return Int(value)
        }

        #expect(mapped == .success(123))
    }

    // MARK: - mapAsync (throwing, where Failure == Error)

    @Test("mapAsync throwing transforms success value")
    func mapAsyncThrowingTransformsSuccess() async {
        let result: Result<Int, Error> = .success(42)

        let mapped = await result.mapAsync { value async throws -> String in
            await Task.yield()
            return "value-\(value)"
        }

        switch mapped {
            case .success(let value):
                #expect(value == "value-42")
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("mapAsync throwing preserves original failure")
    func mapAsyncThrowingPreservesFailure() async {
        let result: Result<Int, Error> = .failure(TestError.invalid)

        let mapped = await result.mapAsync { value async throws -> String in
            await Task.yield()
            return "value-\(value)"
        }

        switch mapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
    }

    @Test("mapAsync throwing captures thrown error")
    func mapAsyncThrowingCapturesError() async {
        let result: Result<Int, Error> = .success(42)

        let mapped = await result.mapAsync { _ async throws -> String in
            await Task.yield()
            throw TestError.notFound
        }

        switch mapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .notFound)
        }
    }

    @Test("mapAsync throwing does not call transform for failure")
    func mapAsyncThrowingDoesNotCallTransformForFailure() async {
        let counter = AsyncCounter()
        let result: Result<Int, Error> = .failure(TestError.invalid)

        _ = await result.mapAsync { value async throws -> Int in
            await counter.increment()
            return value
        }

        let count = await counter.count
        #expect(count == 0)
    }

    // MARK: - flatMapAsync

    @Test("flatMapAsync transforms success to new success")
    func flatMapAsyncTransformsToSuccess() async {
        let result: Result<Int, TestError> = .success(42)

        let mapped = await result.flatMapAsync { value -> Result<String, TestError> in
            await Task.yield()
            return .success("value-\(value)")
        }

        #expect(mapped == .success("value-42"))
    }

    @Test("flatMapAsync transforms success to failure")
    func flatMapAsyncTransformsToFailure() async {
        let result: Result<Int, TestError> = .success(42)

        let mapped = await result.flatMapAsync { _ -> Result<String, TestError> in
            await Task.yield()
            return .failure(.invalid)
        }

        #expect(mapped == .failure(.invalid))
    }

    @Test("flatMapAsync preserves original failure")
    func flatMapAsyncPreservesFailure() async {
        let result: Result<Int, TestError> = .failure(.notFound)

        let mapped = await result.flatMapAsync { value -> Result<String, TestError> in
            await Task.yield()
            return .success("value-\(value)")
        }

        #expect(mapped == .failure(.notFound))
    }

    @Test("flatMapAsync does not call transform for failure")
    func flatMapAsyncDoesNotCallTransformForFailure() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .failure(.invalid)

        _ = await result.flatMapAsync { value -> Result<Int, TestError> in
            await counter.increment()
            return .success(value)
        }

        let count = await counter.count
        #expect(count == 0)
    }

    @Test("flatMapAsync works with actor-isolated operations")
    func flatMapAsyncWithActor() async {
        let counter = AsyncCounter()
        let result: Result<String, TestError> = .success("test")

        let mapped = await result.flatMapAsync { value -> Result<String, TestError> in
            let count = await counter.increment()
            return .success("\(value)-\(count)")
        }

        #expect(mapped == .success("test-1"))
    }

    @Test("flatMapAsync chains multiple operations")
    func flatMapAsyncChaining() async {
        let result: Result<Int, TestError> = .success(10)

        let mapped =
            await result
            .flatMapAsync { value -> Result<Int, TestError> in
                await Task.yield()
                return .success(value * 2)
            }

        let final = await mapped.flatMapAsync { value -> Result<String, TestError> in
            await Task.yield()
            return .success("result: \(value)")
        }

        #expect(final == .success("result: 20"))
    }

    // MARK: - fromAsync

    @Test("fromAsync captures successful async operation")
    func fromAsyncCapturesSuccess() async {
        let result = await Result.fromAsync {
            await Task.yield()
            return 42
        }

        switch result {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("fromAsync captures thrown error")
    func fromAsyncCapturesError() async {
        let result: Result<Int, Error> = await Result.fromAsync {
            await Task.yield()
            throw TestError.invalid
        }

        switch result {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
    }

    @Test("fromAsync works with actor-isolated operations")
    func fromAsyncWithActor() async {
        let counter = AsyncCounter()

        let result = await Result.fromAsync {
            await counter.increment()
            await counter.increment()
            return await counter.count
        }

        switch result {
            case .success(let value):
                #expect(value == 2)
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("fromAsync with complex async operation")
    func fromAsyncComplexOperation() async {
        let result = await Result.fromAsync { () async throws -> String in
            await Task.yield()
            let part1 = "Hello"
            await Task.yield()
            let part2 = "World"
            return "\(part1) \(part2)"
        }

        switch result {
            case .success(let value):
                #expect(value == "Hello World")
            case .failure:
                Issue.record("Expected success")
        }
    }
}
