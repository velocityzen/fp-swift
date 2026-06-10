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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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
        for await value in stream.mapAsyncKeepOrder(maxConcurrency: .max, { element in
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncKeepOrder runs transforms concurrently")
    func transformsRunConcurrently() async {
        let tracker = ConcurrencyTracker()
        let stream = AsyncStream<Int> { continuation in
            for value in 1...4 { continuation.yield(value) }
            continuation.finish()
        }

        let start = ContinuousClock.now
        var values: [Int] = []
        for await value in stream.mapAsyncKeepOrder(maxConcurrency: .max, { element in
            await tracker.enter()
            try? await Task.sleep(for: .milliseconds(100))
            await tracker.exit()
            return element
        }) {
            values.append(value)
        }
        let elapsed = ContinuousClock.now - start

        let highWater = await tracker.highWater
        #expect(values == [1, 2, 3, 4])
        // overlap observed directly,
        #expect(highWater >= 2)
        // and confirmed by wall-clock: sequential would take at least 400ms
        #expect(elapsed < .milliseconds(400))
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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
        for await result in stream.mapAsyncKeepOrder(maxConcurrency: .max, { (value: Int) -> Int in
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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
        for await result in stream.mapAsyncKeepOrder(maxConcurrency: .max, { (value: Int) -> Int in
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("flatMapAsyncKeepOrder distinguishes source vs transform failures by error")
    func flatMapDistinguishesFailureSources() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.failure(.failed))  // source failure
            continuation.yield(.success(1))  // transform will fail with .other
            continuation.yield(.success(2))  // transform succeeds
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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
        for await result in stream.flatMapAsyncKeepOrder(maxConcurrency: .max, { (value: Int) -> Result<Int, TestError> in
            // Earlier successes sleep longer.
            let nanos = UInt64((4 - value) * 20_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            return .success(value)
        }) {
            results.append(result)
        }

        #expect(results == [.success(1), .success(2), .failure(.failed), .success(3)])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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
        for await result in stream.flatMapAsyncKeepOrder(maxConcurrency: .max, { (value: Int) -> Result<Int, TestError> in
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

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
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

    // MARK: - maxConcurrency

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncKeepOrder never runs more than maxConcurrency transforms at once")
    func respectsMaxConcurrency() async {
        let tracker = ConcurrencyTracker()
        let source = AsyncStream<Int> { continuation in
            for i in 1...10 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        let start = ContinuousClock.now
        var results: [Int] = []
        for await value in source.mapAsyncKeepOrder(
            maxConcurrency: 3,
            { element in
                await tracker.enter()
                try? await Task.sleep(for: .milliseconds(20))
                await tracker.exit()
                return element * 2
            })
        {
            results.append(value)
        }
        let elapsed = ContinuousClock.now - start

        let highWater = await tracker.highWater
        #expect(results == [2, 4, 6, 8, 10, 12, 14, 16, 18, 20])
        #expect(highWater <= 3)
        #expect(highWater >= 1)
        // 10 sleeps of 20ms with at most 3 in flight can never finish
        // faster than 200ms / 3 — the cap must cost wall-clock time
        #expect(elapsed >= .milliseconds(66))
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncKeepOrder with maxConcurrency 1 runs transforms one at a time in order")
    func maxConcurrencyOneIsSequential() async {
        let tracker = ConcurrencyTracker()
        let source = AsyncStream<Int> { continuation in
            for i in 1...5 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        var results: [Int] = []
        for await value in source.mapAsyncKeepOrder(
            maxConcurrency: 1,
            { element in
                await tracker.enter()
                // later elements finish faster; order must still hold
                try? await Task.sleep(for: .milliseconds(6 - element))
                await tracker.exit()
                return element
            })
        {
            results.append(value)
        }

        let highWater = await tracker.highWater
        #expect(results == [1, 2, 3, 4, 5])
        #expect(highWater == 1)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncKeepOrder preserves order with bounded concurrency under variable latency")
    func boundedConcurrencyPreservesOrder() async {
        let source = AsyncStream<Int> { continuation in
            for i in 1...6 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        var results: [Int] = []
        for await value in source.mapAsyncKeepOrder(
            maxConcurrency: 2,
            { element in
                // earlier elements are slower than later ones
                try? await Task.sleep(for: .milliseconds((7 - element) * 10))
                return element
            })
        {
            results.append(value)
        }

        #expect(results == [1, 2, 3, 4, 5, 6])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncKeepOrder cancels in-flight transforms when the consumer stops early")
    func cancelsInFlightOnEarlyTermination() async {
        let started = AsyncCounter()
        let cancelled = AsyncCounter()
        let source = AsyncStream<Int> { continuation in
            for i in 1...3 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        let consumer = Task {
            for await _ in source.mapAsyncKeepOrder(maxConcurrency: .max, { (element: Int) -> Int in
                await started.increment()
                // sleeps far longer than the test; throws immediately on cancellation
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled {
                    await cancelled.increment()
                }
                return element
            }) {}
        }

        // let all three transforms start, then walk away
        var observedStarted = 0
        for _ in 0..<100 {
            observedStarted = await started.count
            if observedStarted == 3 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        consumer.cancel()
        await consumer.value

        // every in-flight transform observes cancellation
        var observedCancelled = 0
        for _ in 0..<100 {
            observedCancelled = await cancelled.count
            if observedCancelled == 3 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observedStarted == 3)
        #expect(observedCancelled == 3)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncKeepOrder with a cap stops reading the source when the consumer stops early")
    func cancellationWithCapStopsReadingSource() async {
        let started = AsyncCounter()
        let cancelled = AsyncCounter()
        let source = AsyncStream<Int> { continuation in
            for i in 1...5 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        let consumer = Task {
            for await _ in source.mapAsyncKeepOrder(
                maxConcurrency: 2,
                { (element: Int) -> Int in
                    await started.increment()
                    try? await Task.sleep(for: .seconds(10))
                    if Task.isCancelled {
                        await cancelled.increment()
                    }
                    return element
                })
            {}
        }

        // the window admits exactly two transforms; the rest stay queued
        var observedStarted = 0
        for _ in 0..<100 {
            observedStarted = await started.count
            if observedStarted == 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        consumer.cancel()
        await consumer.value

        var observedCancelled = 0
        for _ in 0..<100 {
            observedCancelled = await cancelled.count
            if observedCancelled == 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        // elements 3-5 must never have started; the two in flight were cancelled
        let finalStarted = await started.count
        #expect(finalStarted == 2)
        #expect(observedCancelled == 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncKeepOrder timing: unlimited overlaps sleeps, maxConcurrency 1 serializes them")
    func timingParallelVsSequential() async {
        func run(maxConcurrency: Int) async -> Duration {
            let source = AsyncStream<Int> { continuation in
                for i in 1...4 {
                    continuation.yield(i)
                }
                continuation.finish()
            }
            let start = ContinuousClock.now
            for await _ in source.mapAsyncKeepOrder(
                maxConcurrency: maxConcurrency,
                { (element: Int) -> Int in
                    try? await Task.sleep(for: .milliseconds(50))
                    return element
                })
            {}
            return ContinuousClock.now - start
        }

        let sequential = await run(maxConcurrency: 1)
        let parallel = await run(maxConcurrency: .max)

        // four 50ms sleeps one at a time can never beat their 200ms sum
        #expect(sequential >= .milliseconds(200))
        // overlapped, they finish in ~50ms — well under the sum
        #expect(parallel < .milliseconds(200))
        #expect(parallel < sequential)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncKeepOrder terminates cleanly when the source never finishes")
    func earlyTerminationWithUnfinishedSource() async {
        let source = AsyncStream<Int> { continuation in
            for i in 1...3 {
                continuation.yield(i)
            }
            // never calls finish() — like a long-lived SSE stream
        }

        var values: [Int] = []
        for await value in source.mapAsyncKeepOrder({ $0 * 2 }) {
            values.append(value)
            if values.count == 2 { break }
        }

        #expect(values == [2, 4])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncKeepOrder on Result forwards maxConcurrency")
    func resultOverloadRespectsMaxConcurrency() async {
        let tracker = ConcurrencyTracker()
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            for i in 1...6 {
                continuation.yield(.success(i))
            }
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.mapAsyncKeepOrder(
            maxConcurrency: 2,
            { (value: Int) -> Int in
                await tracker.enter()
                try? await Task.sleep(for: .milliseconds(20))
                await tracker.exit()
                return value * 10
            })
        {
            results.append(result)
        }

        let highWater = await tracker.highWater
        #expect(
            results == [
                .success(10), .success(20), .success(30), .success(40), .success(50), .success(60),
            ])
        #expect(highWater <= 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("flatMapAsyncKeepOrder forwards maxConcurrency")
    func flatMapOverloadRespectsMaxConcurrency() async {
        let tracker = ConcurrencyTracker()
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            for i in 1...6 {
                continuation.yield(.success(i))
            }
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.flatMapAsyncKeepOrder(
            maxConcurrency: 2,
            { (value: Int) -> Result<Int, TestError> in
                await tracker.enter()
                try? await Task.sleep(for: .milliseconds(20))
                await tracker.exit()
                return value.isMultiple(of: 2) ? .success(value * 10) : .failure(.other)
            })
        {
            results.append(result)
        }

        let highWater = await tracker.highWater
        #expect(
            results == [
                .failure(.other), .success(20), .failure(.other), .success(40), .failure(.other),
                .success(60),
            ])
        #expect(highWater <= 2)
    }
}
