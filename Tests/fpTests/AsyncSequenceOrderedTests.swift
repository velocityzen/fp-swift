import Foundation
import Testing

@testable import FP

@Suite("AsyncSequence+Ordered Tests")
struct AsyncSequenceOrderedTests {
    enum TestError: Error, Equatable {
        case failed
        case other
    }

    // MARK: - mapAsyncKeepOrder

    @Test("mapAsyncKeepOrder transforms each element")
    func transformsEachElement() async {
        let stream = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
            continuation.finish()
        }

        var values: [String] = []
        for await value in stream.mapAsyncKeepOrder({ "v\($0)" }) {
            values.append(value)
        }

        #expect(values == ["v1", "v2", "v3"])
    }

    @Test("mapAsyncKeepOrder preserves source order even when later transforms finish first")
    func preservesOrderWithVariableLatency() async {
        let stream = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
            continuation.yield(4)
            continuation.finish()
        }

        var values: [Int] = []
        for await value in stream.mapAsyncKeepOrder({ element in
            // Earlier elements sleep longer — without strict-order
            // emission, the output would be reordered.
            let nanos = UInt64((5 - element) * 20_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            return element
        }) {
            values.append(value)
        }

        #expect(values == [1, 2, 3, 4])
    }

    @Test("mapAsyncKeepOrder runs transforms concurrently")
    func transformsRunConcurrently() async {
        let total = 10

        let stream = AsyncStream<Int> { continuation in
            for value in 1...total { continuation.yield(value) }
            continuation.finish()
        }

        let perElementSleep: UInt64 = 100_000_000  // 100ms

        let start = ContinuousClock.now
        var values: [Int] = []
        for await value in stream.mapAsyncKeepOrder({ element in
            let sleepFor = UInt64(total - element) * perElementSleep
            try? await Task.sleep(nanoseconds: sleepFor)
            return element
        }) {
            values.append(value)
        }
        let elapsed = ContinuousClock.now - start

        #expect(values == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        // Sequential would be ~400ms; concurrent should be well under
        // 300ms even on a busy CI box.
        #expect(elapsed < Duration.nanoseconds(UInt64(total) * perElementSleep))
    }

    @Test("mapAsyncKeepOrder finishes when source is empty")
    func finishesOnEmptySource() async {
        let stream = AsyncStream<Int> { continuation in
            continuation.finish()
        }

        var values: [Int] = []
        for await value in stream.mapAsyncKeepOrder({ $0 * 2 }) {
            values.append(value)
        }

        #expect(values.isEmpty)
    }

    @Test("mapAsyncKeepOrder invokes transform once per element")
    func invokesTransformOncePerElement() async {
        let stream = AsyncStream<Int> { continuation in
            for value in 1...5 { continuation.yield(value) }
            continuation.finish()
        }

        let counter = AsyncCounter()
        var values: [Int] = []
        for await value in stream.mapAsyncKeepOrder({ element in
            await counter.increment()
            return element
        }) {
            values.append(value)
        }

        let count = await counter.count
        #expect(count == 5)
        #expect(values == [1, 2, 3, 4, 5])
    }

    @Test("mapAsyncKeepOrder allows the consumer to break out early without hanging")
    func allowsEarlyTermination() async {
        let stream = AsyncStream<Int> { continuation in
            for value in 1...10 { continuation.yield(value) }
            continuation.finish()
        }

        let mapped = stream.mapAsyncKeepOrder({ $0 * 10 })

        var values: [Int] = []
        for await value in mapped {
            values.append(value)
            if values.count == 2 { break }
        }

        #expect(values == [10, 20])
    }

    // MARK: - mapAsyncKeepOrder (Result)

    @Test("mapAsyncKeepOrder on Result transforms successes and preserves failures")
    func resultTransformsSuccessesPreservesFailures() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.yield(.failure(.other))
            continuation.finish()
        }

        var results: [Result<String, TestError>] = []
        for await result in stream.mapAsyncKeepOrder({ value in "v\(value)" }) {
            results.append(result)
        }

        #expect(results.count == 4)
        #expect(results[0] == .success("v1"))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .success("v2"))
        #expect(results[3] == .failure(.other))
    }

    @Test("mapAsyncKeepOrder on Result preserves order with mixed successes and failures")
    func resultPreservesOrderWithVariableLatency() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.success(2))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(3))
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.mapAsyncKeepOrder({ (value: Int) -> Int in
            // Earlier successes sleep longer.
            let nanos = UInt64((4 - value) * 20_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            return value
        }) {
            results.append(result)
        }

        #expect(results.count == 4)
        #expect(results[0] == .success(1))
        #expect(results[1] == .success(2))
        #expect(results[2] == .failure(.failed))
        #expect(results[3] == .success(3))
    }

    @Test("mapAsyncKeepOrder on Result runs success transforms concurrently")
    func resultRunsTransformsConcurrently() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.success(2))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(3))
            continuation.yield(.success(4))
            continuation.finish()
        }

        let perElementSleep: UInt64 = 100_000_000  // 100ms

        let start = ContinuousClock.now
        var results: [Result<Int, TestError>] = []
        for await result in stream.mapAsyncKeepOrder({ (value: Int) -> Int in
            try? await Task.sleep(nanoseconds: perElementSleep)
            return value
        }) {
            results.append(result)
        }
        let elapsed = ContinuousClock.now - start

        #expect(results.count == 5)
        // 4 successes sequential would be ~400ms.
        #expect(elapsed < .milliseconds(300))
    }

    @Test("mapAsyncKeepOrder on Result skips transform for failures")
    func resultSkipsTransformForFailures() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.failure(.failed))
            continuation.yield(.success(1))
            continuation.yield(.failure(.other))
            continuation.yield(.success(2))
            continuation.finish()
        }

        let counter = AsyncCounter()
        var results: [Result<Int, TestError>] = []
        for await result in stream.mapAsyncKeepOrder({ (value: Int) -> Int in
            await counter.increment()
            return value * 10
        }) {
            results.append(result)
        }

        let count = await counter.count
        #expect(count == 2)
        #expect(results.count == 4)
        #expect(results[0] == .failure(.failed))
        #expect(results[1] == .success(10))
        #expect(results[2] == .failure(.other))
        #expect(results[3] == .success(20))
    }

    @Test("mapAsyncKeepOrder on Result passes through all-failure stream untouched")
    func resultAllFailures() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.failure(.failed))
            continuation.yield(.failure(.other))
            continuation.finish()
        }

        var results: [Result<String, TestError>] = []
        for await result in stream.mapAsyncKeepOrder({ "v\($0)" }) {
            results.append(result)
        }

        #expect(results == [.failure(.failed), .failure(.other)])
    }

    // MARK: - flatMapAsyncKeepOrder (Result)

    @Test("flatMapAsyncKeepOrder transforms successes, preserves source failures")
    func flatMapTransformsAndPreserves() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.finish()
        }

        var results: [Result<String, TestError>] = []
        for await result in stream.flatMapAsyncKeepOrder({ value -> Result<String, TestError> in
            .success("v\(value)")
        }) {
            results.append(result)
        }

        #expect(results.count == 3)
        #expect(results[0] == .success("v1"))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .success("v2"))
    }

    @Test("flatMapAsyncKeepOrder transform failure replaces success it came from")
    func flatMapTransformFailureReplacesSuccess() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.success(2))
            continuation.yield(.success(3))
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.flatMapAsyncKeepOrder({ value -> Result<Int, TestError> in
            value == 2 ? .failure(.failed) : .success(value * 10)
        }) {
            results.append(result)
        }

        #expect(results == [.success(10), .failure(.failed), .success(30)])
    }

    @Test("flatMapAsyncKeepOrder distinguishes source vs transform failures by error")
    func flatMapDistinguishesFailureSources() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.failure(.failed))   // source failure
            continuation.yield(.success(1))         // transform will fail with .other
            continuation.yield(.success(2))         // transform succeeds
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.flatMapAsyncKeepOrder({ value -> Result<Int, TestError> in
            value == 1 ? .failure(.other) : .success(value * 10)
        }) {
            results.append(result)
        }

        #expect(results == [.failure(.failed), .failure(.other), .success(20)])
    }

    @Test("flatMapAsyncKeepOrder preserves order when later transforms finish first")
    func flatMapPreservesOrderWithVariableLatency() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.success(2))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(3))
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.flatMapAsyncKeepOrder({ (value: Int) -> Result<Int, TestError> in
            // Earlier successes sleep longer.
            let nanos = UInt64((4 - value) * 20_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            return .success(value)
        }) {
            results.append(result)
        }

        #expect(results == [.success(1), .success(2), .failure(.failed), .success(3)])
    }

    @Test("flatMapAsyncKeepOrder runs successful transforms concurrently")
    func flatMapRunsTransformsConcurrently() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.success(2))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(3))
            continuation.yield(.success(4))
            continuation.finish()
        }

        let perElementSleep: UInt64 = 100_000_000  // 100ms

        let start = ContinuousClock.now
        var results: [Result<Int, TestError>] = []
        for await result in stream.flatMapAsyncKeepOrder({ (value: Int) -> Result<Int, TestError> in
            try? await Task.sleep(nanoseconds: perElementSleep)
            return .success(value)
        }) {
            results.append(result)
        }
        let elapsed = ContinuousClock.now - start

        #expect(results.count == 5)
        // 4 successes sequential would be ~400ms.
        #expect(elapsed < .milliseconds(300))
    }

    @Test("flatMapAsyncKeepOrder skips transform for source failures")
    func flatMapSkipsTransformForSourceFailures() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.failure(.failed))
            continuation.yield(.success(1))
            continuation.yield(.failure(.other))
            continuation.yield(.success(2))
            continuation.finish()
        }

        let counter = AsyncCounter()
        var results: [Result<Int, TestError>] = []
        for await result in stream.flatMapAsyncKeepOrder({ (value: Int) -> Result<Int, TestError> in
            await counter.increment()
            return .success(value * 10)
        }) {
            results.append(result)
        }

        let count = await counter.count
        #expect(count == 2)
        #expect(results == [.failure(.failed), .success(10), .failure(.other), .success(20)])
    }
}
