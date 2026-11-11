import Foundation
import Testing

@testable import FP

@Suite("AsyncSequence+Ordered Tests")
struct AsyncSequenceOrderedTests {
    enum TestError: Error, Equatable {
        case failed
        case other
    }

    // MARK: - mapAsyncOrdered

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered transforms each element")
    func transformsEachElement() async {
        let stream = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
            continuation.finish()
        }

        var values: [String] = []
        for await value in stream.mapAsyncOrdered({ "v\($0)" }) {
            values.append(value)
        }

        #expect(values == ["v1", "v2", "v3"])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered preserves source order even when later transforms finish first")
    func preservesOrderWithVariableLatency() async {
        let stream = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
            continuation.yield(4)
            continuation.finish()
        }

        var values: [Int] = []
        for await value in stream.mapAsyncOrdered(
            concurrency: .max,
            { element in
                // Earlier elements sleep longer. Without the order rule,
                // the output would be out of order.
                let nanos = UInt64((5 - element) * 20_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return element
            }
        ) {
            values.append(value)
        }

        #expect(values == [1, 2, 3, 4])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered runs transforms concurrently")
    func transformsRunConcurrently() async {
        let tracker = ConcurrencyTracker()
        let stream = AsyncStream<Int> { continuation in
            for value in 1...4 { continuation.yield(value) }
            continuation.finish()
        }

        var values: [Int] = []
        for await value in stream.mapAsyncOrdered(
            concurrency: .max,
            { element in
                await tracker.enter()
                try? await Task.sleep(for: .milliseconds(100))
                await tracker.exit()
                return element
            }
        ) {
            values.append(value)
        }

        let highWater = await tracker.highWater
        #expect(values == [1, 2, 3, 4])
        // Overlap is observed directly. These tests prove concurrency by the
        // high-water mark, never by a wall-clock upper bound: tests run in
        // parallel, so a busy machine can delay any of them by hundreds of
        // milliseconds.
        #expect(highWater >= 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered finishes when source is empty")
    func finishesOnEmptySource() async {
        let stream = AsyncStream<Int> { continuation in
            continuation.finish()
        }

        var values: [Int] = []
        for await value in stream.mapAsyncOrdered({ $0 * 2 }) {
            values.append(value)
        }

        #expect(values.isEmpty)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered invokes transform once per element")
    func invokesTransformOncePerElement() async {
        let stream = AsyncStream<Int> { continuation in
            for value in 1...5 { continuation.yield(value) }
            continuation.finish()
        }

        let counter = AsyncCounter()
        var values: [Int] = []
        for await value in stream.mapAsyncOrdered({ element in
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
    @Test("mapAsyncOrdered allows the consumer to break out early without hanging")
    func allowsEarlyTermination() async {
        let stream = AsyncStream<Int> { continuation in
            for value in 1...10 { continuation.yield(value) }
            continuation.finish()
        }

        let mapped = stream.mapAsyncOrdered({ $0 * 10 })

        var values: [Int] = []
        for await value in mapped {
            values.append(value)
            if values.count == 2 { break }
        }

        #expect(values == [10, 20])
    }

    // MARK: - mapAsyncOrdered (Result)

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered on Result transforms successes and preserves failures")
    func resultTransformsSuccessesPreservesFailures() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.yield(.failure(.other))
            continuation.finish()
        }

        var results: [Result<String, TestError>] = []
        for await result in stream.mapAsyncOrdered({ value in "v\(value)" }) {
            results.append(result)
        }

        #expect(results.count == 4)
        #expect(results[0] == .success("v1"))
        #expect(results[1] == .failure(.failed))
        #expect(results[2] == .success("v2"))
        #expect(results[3] == .failure(.other))
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered on Result preserves order with mixed successes and failures")
    func resultPreservesOrderWithVariableLatency() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.success(2))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(3))
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.mapAsyncOrdered(
            concurrency: .max,
            { (value: Int) -> Int in
                // Earlier successes sleep longer.
                let nanos = UInt64((4 - value) * 20_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return value
            }
        ) {
            results.append(result)
        }

        #expect(results.count == 4)
        #expect(results[0] == .success(1))
        #expect(results[1] == .success(2))
        #expect(results[2] == .failure(.failed))
        #expect(results[3] == .success(3))
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered on Result runs success transforms concurrently")
    func resultRunsTransformsConcurrently() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.success(2))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(3))
            continuation.yield(.success(4))
            continuation.finish()
        }

        let tracker = ConcurrencyTracker()
        var results: [Result<Int, TestError>] = []
        for await result in stream.mapAsyncOrdered(
            concurrency: .max,
            { (value: Int) -> Int in
                await tracker.enter()
                try? await Task.sleep(for: .milliseconds(100))
                await tracker.exit()
                return value
            }
        ) {
            results.append(result)
        }

        #expect(results.count == 5)
        // the success transforms overlap (see transformsRunConcurrently)
        #expect(await tracker.highWater >= 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered on Result skips transform for failures")
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
        for await result in stream.mapAsyncOrdered({ (value: Int) -> Int in
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
    @Test("mapAsyncOrdered on Result passes through all-failure stream untouched")
    func resultAllFailures() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.failure(.failed))
            continuation.yield(.failure(.other))
            continuation.finish()
        }

        var results: [Result<String, TestError>] = []
        for await result in stream.mapAsyncOrdered({ "v\($0)" }) {
            results.append(result)
        }

        #expect(results == [.failure(.failed), .failure(.other)])
    }

    // MARK: - flatMapAsyncOrdered (Result)

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("flatMapAsyncOrdered transforms successes, preserves source failures")
    func flatMapTransformsAndPreserves() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.finish()
        }

        var results: [Result<String, TestError>] = []
        for await result in stream.flatMapAsyncOrdered({ value -> Result<String, TestError> in
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
    @Test("flatMapAsyncOrdered transform failure replaces success it came from")
    func flatMapTransformFailureReplacesSuccess() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.success(2))
            continuation.yield(.success(3))
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.flatMapAsyncOrdered({ value -> Result<Int, TestError> in
            value == 2 ? .failure(.failed) : .success(value * 10)
        }) {
            results.append(result)
        }

        #expect(results == [.success(10), .failure(.failed), .success(30)])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("flatMapAsyncOrdered distinguishes source vs transform failures by error")
    func flatMapDistinguishesFailureSources() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.failure(.failed))  // source failure
            continuation.yield(.success(1))  // transform will fail with .other
            continuation.yield(.success(2))  // transform succeeds
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.flatMapAsyncOrdered({ value -> Result<Int, TestError> in
            value == 1 ? .failure(.other) : .success(value * 10)
        }) {
            results.append(result)
        }

        #expect(results == [.failure(.failed), .failure(.other), .success(20)])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("flatMapAsyncOrdered preserves order when later transforms finish first")
    func flatMapPreservesOrderWithVariableLatency() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.success(2))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(3))
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.flatMapAsyncOrdered(
            concurrency: .max,
            { (value: Int) -> Result<Int, TestError> in
                // Earlier successes sleep longer.
                let nanos = UInt64((4 - value) * 20_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return .success(value)
            }
        ) {
            results.append(result)
        }

        #expect(results == [.success(1), .success(2), .failure(.failed), .success(3)])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("flatMapAsyncOrdered runs successful transforms concurrently")
    func flatMapRunsTransformsConcurrently() async {
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.success(2))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(3))
            continuation.yield(.success(4))
            continuation.finish()
        }

        let tracker = ConcurrencyTracker()
        var results: [Result<Int, TestError>] = []
        for await result in stream.flatMapAsyncOrdered(
            concurrency: .max,
            { (value: Int) -> Result<Int, TestError> in
                await tracker.enter()
                try? await Task.sleep(for: .milliseconds(100))
                await tracker.exit()
                return .success(value)
            }
        ) {
            results.append(result)
        }

        #expect(results.count == 5)
        // the success transforms overlap (see transformsRunConcurrently)
        #expect(await tracker.highWater >= 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("flatMapAsyncOrdered skips transform for source failures")
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
        for await result in stream.flatMapAsyncOrdered({ (value: Int) -> Result<Int, TestError> in
            await counter.increment()
            return .success(value * 10)
        }) {
            results.append(result)
        }

        let count = await counter.count
        #expect(count == 2)
        #expect(results == [.failure(.failed), .success(10), .failure(.other), .success(20)])
    }

    // MARK: - concurrency

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered never exceeds the concurrency limit")
    func respectsConcurrencyLimit() async {
        let tracker = ConcurrencyTracker()
        let source = AsyncStream<Int> { continuation in
            for i in 1...10 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        let start = ContinuousClock.now
        var results: [Int] = []
        for await value in source.mapAsyncOrdered(
            concurrency: 3,
            { element in
                await tracker.enter()
                try? await Task.sleep(for: .milliseconds(20))
                await tracker.exit()
                return element * 2
            }
        ) {
            results.append(value)
        }
        let elapsed = ContinuousClock.now - start

        let highWater = await tracker.highWater
        #expect(results == [2, 4, 6, 8, 10, 12, 14, 16, 18, 20])
        #expect(highWater <= 3)
        #expect(highWater >= 1)
        // 10 sleeps of 20ms with at most 3 in flight can never finish
        // faster than 200ms / 3, so the cap must cost wall-clock time.
        #expect(elapsed >= .milliseconds(66))
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered with concurrency 1 runs transforms one at a time in order")
    func concurrencyOneIsSequential() async {
        let tracker = ConcurrencyTracker()
        let source = AsyncStream<Int> { continuation in
            for i in 1...5 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        var results: [Int] = []
        for await value in source.mapAsyncOrdered(
            concurrency: 1,
            { element in
                await tracker.enter()
                // later elements finish faster; order must still hold
                try? await Task.sleep(for: .milliseconds(6 - element))
                await tracker.exit()
                return element
            }
        ) {
            results.append(value)
        }

        let highWater = await tracker.highWater
        #expect(results == [1, 2, 3, 4, 5])
        #expect(highWater == 1)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered preserves order with bounded concurrency under variable latency")
    func boundedConcurrencyPreservesOrder() async {
        let source = AsyncStream<Int> { continuation in
            for i in 1...6 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        var results: [Int] = []
        for await value in source.mapAsyncOrdered(
            concurrency: 2,
            { element in
                // earlier elements are slower than later ones
                try? await Task.sleep(for: .milliseconds((7 - element) * 10))
                return element
            }
        ) {
            results.append(value)
        }

        #expect(results == [1, 2, 3, 4, 5, 6])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "mapAsyncOrdered cancels in-flight transforms when the consumer stops early",
        .hangGuard
    )
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
            for await _ in source.mapAsyncOrdered(
                concurrency: .max,
                { (element: Int) -> Int in
                    await started.increment()
                    await waitForCancellation()
                    await cancelled.increment()
                    return element
                }
            ) {}
        }

        // let all three transforms start, then walk away
        var observedStarted = 0
        for _ in 0..<200 {
            observedStarted = await started.count
            if observedStarted == 3 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        consumer.cancel()
        await consumer.value

        // every in-flight transform observes cancellation
        var observedCancelled = 0
        for _ in 0..<200 {
            observedCancelled = await cancelled.count
            if observedCancelled == 3 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observedStarted == 3)
        #expect(observedCancelled == 3)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "mapAsyncOrdered with a cap stops reading the source when the consumer stops early",
        .hangGuard
    )
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
            for await _ in source.mapAsyncOrdered(
                concurrency: 2,
                { (element: Int) -> Int in
                    await started.increment()
                    await waitForCancellation()
                    await cancelled.increment()
                    return element
                }
            ) {}
        }

        // the window admits exactly two transforms; the rest stay queued
        var observedStarted = 0
        for _ in 0..<200 {
            observedStarted = await started.count
            if observedStarted == 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        consumer.cancel()
        await consumer.value

        var observedCancelled = 0
        for _ in 0..<200 {
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
    @Test("mapAsyncOrdered timing: unlimited overlaps sleeps, concurrency 1 serializes them")
    func timingParallelVsSequential() async {
        func run(concurrency: Int) async -> (elapsed: Duration, highWater: Int) {
            let tracker = ConcurrencyTracker()
            let source = AsyncStream<Int> { continuation in
                for i in 1...4 {
                    continuation.yield(i)
                }
                continuation.finish()
            }
            let start = ContinuousClock.now
            for await _ in source.mapAsyncOrdered(
                concurrency: concurrency,
                { (element: Int) -> Int in
                    await tracker.enter()
                    try? await Task.sleep(for: .milliseconds(50))
                    await tracker.exit()
                    return element
                }
            ) {}
            let elapsed = ContinuousClock.now - start
            return (elapsed, await tracker.highWater)
        }

        let sequential = await run(concurrency: 1)
        let parallel = await run(concurrency: .max)

        // one at a time, four 50ms sleeps can never beat their 200ms sum,
        #expect(sequential.highWater == 1)
        #expect(sequential.elapsed >= .milliseconds(200))
        // while unlimited overlaps them (see transformsRunConcurrently for why
        // there is no wall-clock upper bound on the parallel run).
        #expect(parallel.highWater >= 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered defaults to sequential execution")
    func defaultIsSequential() async {
        let tracker = ConcurrencyTracker()
        let source = AsyncStream<Int> { continuation in
            for i in 1...4 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        let start = ContinuousClock.now
        var results: [Int] = []
        for await value in source.mapAsyncOrdered({ element in
            await tracker.enter()
            try? await Task.sleep(for: .milliseconds(30))
            await tracker.exit()
            return element
        }) {
            results.append(value)
        }
        let elapsed = ContinuousClock.now - start

        let highWater = await tracker.highWater
        #expect(results == [1, 2, 3, 4])
        // no overlap by default,
        #expect(highWater == 1)
        // and four 30ms sleeps one at a time can never beat their 120ms sum
        #expect(elapsed >= .milliseconds(120))
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered terminates cleanly when the source never finishes")
    func earlyTerminationWithUnfinishedSource() async {
        let source = AsyncStream<Int> { continuation in
            for i in 1...3 {
                continuation.yield(i)
            }
            // Never calls finish(), like a long-lived SSE stream.
        }

        var values: [Int] = []
        for await value in source.mapAsyncOrdered({ $0 * 2 }) {
            values.append(value)
            if values.count == 2 { break }
        }

        #expect(values == [2, 4])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered on Result forwards concurrency")
    func resultOverloadRespectsConcurrencyLimit() async {
        let tracker = ConcurrencyTracker()
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            for i in 1...6 {
                continuation.yield(.success(i))
            }
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.mapAsyncOrdered(
            concurrency: 2,
            { (value: Int) -> Int in
                await tracker.enter()
                try? await Task.sleep(for: .milliseconds(20))
                await tracker.exit()
                return value * 10
            }
        ) {
            results.append(result)
        }

        let highWater = await tracker.highWater
        #expect(
            results == [
                .success(10), .success(20), .success(30), .success(40), .success(50), .success(60),
            ]
        )
        #expect(highWater <= 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("flatMapAsyncOrdered forwards concurrency")
    func flatMapOverloadRespectsConcurrencyLimit() async {
        let tracker = ConcurrencyTracker()
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            for i in 1...6 {
                continuation.yield(.success(i))
            }
            continuation.finish()
        }

        var results: [Result<Int, TestError>] = []
        for await result in stream.flatMapAsyncOrdered(
            concurrency: 2,
            { (value: Int) -> Result<Int, TestError> in
                await tracker.enter()
                try? await Task.sleep(for: .milliseconds(20))
                await tracker.exit()
                return value.isMultiple(of: 2) ? .success(value * 10) : .failure(.other)
            }
        ) {
            results.append(result)
        }

        let highWater = await tracker.highWater
        #expect(
            results == [
                .failure(.other), .success(20), .failure(.other), .success(40), .failure(.other),
                .success(60),
            ]
        )
        #expect(highWater <= 2)
    }

    // MARK: - backpressure

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered does not run ahead of a slow consumer", .hangGuard)
    func backpressureBoundsWorkAheadOfConsumer() async {
        let concurrency = 3
        // Early results take no slot, so without a limit a worker slow to
        // hand over its result lets the others run ahead. Transforms that
        // finish in source order do not prevent that: workers hand results
        // over in the order they take the lock, not the order they finish.
        let bufferLimit = concurrency
        let started = AsyncCounter()
        let source = AsyncStream<Int> { continuation in
            for i in 1...100 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        let mapped = source.mapAsyncOrdered(
            concurrency: concurrency,
            bufferLimit: bufferLimit,
            { (element: Int) -> Int in
                await started.increment()
                return element
            }
        )
        var iterator = mapped.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        // Every transform is instant, so without backpressure all 100 would
        // run while the consumer is idle.
        try? await Task.sleep(for: .milliseconds(100))

        let observedStarted = await started.count
        #expect(first == 1)
        #expect(second == 2)
        // two consumed, plus at most `concurrency` running or waiting and
        // `bufferLimit` early results
        #expect(observedStarted <= 2 + concurrency + bufferLimit)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered transforms later elements while an early one is slow", .hangGuard)
    func workersRunPastSlowElement() async {
        let started = AsyncCounter()
        let source = AsyncStream<Int> { continuation in
            for i in 1...100 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        // Element 1 waits on this gate, so it stays unfinished until the
        // test has looked, however slowly the runner schedules tasks.
        let (gate, gateCont) = AsyncStream.makeStream(of: Void.self)

        let consumer = Task {
            var values: [Int] = []
            for await value in source.mapAsyncOrdered(
                concurrency: 3,
                { (element: Int) -> Int in
                    await started.increment()
                    if element == 1 {
                        for await _ in gate {}
                    }
                    return element
                }
            ) {
                values.append(value)
            }
            return values
        }

        // Element 1 holds back the results after it, but not the work: the
        // other two workers transform all 99 later elements meanwhile.
        var startedWhileBlocked = 0
        for _ in 0..<500 {
            startedWhileBlocked = await started.count
            if startedWhileBlocked == 100 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        gateCont.finish()
        let values = await consumer.value

        #expect(startedWhileBlocked == 100)
        #expect(values == Array(1...100))
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered bufferLimit caps results waiting behind a slow element", .hangGuard)
    func bufferLimitCapsResultsWaitingBehindSlowElement() async {
        let started = AsyncCounter()
        let source = AsyncStream<Int> { continuation in
            for i in 1...100 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        let (gate, gateCont) = AsyncStream.makeStream(of: Void.self)

        let consumer = Task {
            var values: [Int] = []
            for await value in source.mapAsyncOrdered(
                concurrency: 3,
                bufferLimit: 4,
                { (element: Int) -> Int in
                    await started.increment()
                    if element == 1 {
                        for await _ in gate {}
                    }
                    return element
                }
            ) {
                values.append(value)
            }
            return values
        }

        // element 1, then the four whose results may wait for it
        var startedWhileBlocked = 0
        for _ in 0..<200 {
            startedWhileBlocked = await started.count
            if startedWhileBlocked >= 5 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        // give a pipeline that ignores the limit time to start more
        try? await Task.sleep(for: .milliseconds(50))
        startedWhileBlocked = await started.count
        gateCont.finish()
        let values = await consumer.value

        #expect(startedWhileBlocked == 5)
        #expect(values == Array(1...100))
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "mapAsyncOrdered bufferLimit below concurrency - 1 lowers transforms in flight",
        arguments: [0, 1, 2]
    )
    func bufferLimitLowersTransformsInFlight(bufferLimit: Int) async {
        let tracker = ConcurrencyTracker()
        let source = AsyncStream<Int> { continuation in
            for i in 1...12 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        var results: [Int] = []
        for await value in source.mapAsyncOrdered(
            concurrency: 8,
            bufferLimit: bufferLimit,
            { element in
                await tracker.enter()
                try? await Task.sleep(for: .milliseconds(10))
                await tracker.exit()
                return element
            }
        ) {
            results.append(value)
        }

        let highWater = await tracker.highWater
        #expect(results == Array(1...12))
        // every transform after the first unfinished one may finish first,
        // so at most `bufferLimit` of them run beside it
        #expect(highWater <= bufferLimit + 1)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered with concurrency 1 reads nothing ahead of the consumer")
    func sequentialReadsNothingAhead() async {
        let started = AsyncCounter()
        let source = AsyncStream<Int> { continuation in
            for i in 1...10 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        let mapped = source.mapAsyncOrdered({ (element: Int) -> Int in
            await started.increment()
            return element
        })
        var iterator = mapped.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        try? await Task.sleep(for: .milliseconds(50))

        let observedStarted = await started.count
        #expect(first == 1)
        #expect(second == 2)
        #expect(observedStarted == 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncOrdered cancels in-flight transforms when the stream is dropped", .hangGuard)
    func droppingTheStreamCancelsInFlight() async {
        let started = AsyncCounter()
        let cancelled = AsyncCounter()
        let source = AsyncStream<Int> { continuation in
            for i in 1...3 {
                continuation.yield(i)
            }
            // never finishes
        }

        // The consumer stops without its task being cancelled; releasing
        // the stream is the only signal the pipeline gets.
        func takeFirst() async -> Int? {
            let mapped = source.mapAsyncOrdered(
                concurrency: 3,
                { (element: Int) -> Int in
                    await started.increment()
                    if element > 1 {
                        await waitForCancellation()
                        await cancelled.increment()
                    }
                    return element
                }
            )
            for await value in mapped {
                // let elements 2 and 3 start before the stream is dropped
                for _ in 0..<200 {
                    if await started.count == 3 { break }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                return value
            }
            return nil
        }

        let first = await takeFirst()

        var observedCancelled = 0
        for _ in 0..<200 {
            observedCancelled = await cancelled.count
            if observedCancelled == 2 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(first == 1)
        #expect(observedCancelled == 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "mapAsyncOrdered delivers every element in order under contention",
        .hangGuard,
        arguments: [2, 3, 8, Int.max]
    )
    func deliversEveryElementUnderContention(concurrency: Int) async {
        let count = 500
        for _ in 0..<20 {
            let source = AsyncStream<Int> { continuation in
                for i in 0..<count {
                    continuation.yield(i)
                }
                continuation.finish()
            }

            var results: [Int] = []
            for await value in source.mapAsyncOrdered(
                concurrency: concurrency,
                { element in
                    // finish out of order: elements yield a varying number of times
                    for _ in 0..<(element % 4) {
                        await Task.yield()
                    }
                    return element
                }
            ) {
                results.append(value)
                // let workers run ahead of the consumer now and then
                if value.isMultiple(of: 7) {
                    await Task.yield()
                }
            }

            #expect(results == Array(0..<count))
        }
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "compactMapAsyncOrdered with a bufferLimit delivers every element in order under contention",
        .hangGuard,
        arguments: zip([2, 3, 8, 8, Int.max], [0, 1, 2, 16, 4])
    )
    func deliversEveryElementWithBufferLimit(concurrency: Int, bufferLimit: Int) async {
        let count = 500
        for _ in 0..<20 {
            let source = AsyncStream<Int> { continuation in
                for i in 0..<count {
                    continuation.yield(i)
                }
                continuation.finish()
            }

            var results: [Int] = []
            for await value in source.compactMapAsyncOrdered(
                concurrency: concurrency,
                bufferLimit: bufferLimit,
                passthrough: { $0.isMultiple(of: 5) ? -$0 : nil },
                { element in
                    for _ in 0..<(element % 4) {
                        await Task.yield()
                    }
                    return element.isMultiple(of: 3) ? nil : element
                }
            ) {
                results.append(value)
                if value.isMultiple(of: 7) {
                    await Task.yield()
                }
            }

            let expected = (0..<count).compactMap { (element: Int) -> Int? in
                element.isMultiple(of: 5) ? -element : element.isMultiple(of: 3) ? nil : element
            }
            #expect(results == expected)
        }
    }

    // MARK: - compactMapAsyncOrdered

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("compactMapAsyncOrdered drops nil results and keeps passed-through ones in place")
    func compactMapDropsAndPassesThroughInOrder() async {
        let stream = AsyncStream<Int> { continuation in
            for value in 1...8 { continuation.yield(value) }
            continuation.finish()
        }
        let counter = AsyncCounter()

        var values: [String] = []
        for await value in stream.compactMapAsyncOrdered(
            concurrency: 4,
            passthrough: { $0.isMultiple(of: 4) ? "cached \($0)" : nil },
            { element in
                await counter.increment()
                // earlier elements are slower than later ones
                try? await Task.sleep(for: .milliseconds((9 - element) * 5))
                return element.isMultiple(of: 3) ? nil : "v\(element)"
            }
        ) {
            values.append(value)
        }

        #expect(values == ["v1", "v2", "cached 4", "v5", "v7", "cached 8"])
        // passed-through elements never reach the transform
        #expect(await counter.count == 6)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("compactMapAsyncOrdered with concurrency 1 runs transforms one at a time")
    func compactMapSequential() async {
        let tracker = ConcurrencyTracker()
        let stream = AsyncStream<Int> { continuation in
            for value in 1...6 { continuation.yield(value) }
            continuation.finish()
        }

        var values: [Int] = []
        for await value in stream.compactMapAsyncOrdered({ (element: Int) -> Int? in
            await tracker.enter()
            try? await Task.sleep(for: .milliseconds(5))
            await tracker.exit()
            return element.isMultiple(of: 2) ? element : nil
        }) {
            values.append(value)
        }

        #expect(values == [2, 4, 6])
        #expect(await tracker.highWater == 1)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "mapAsyncOrdered ends right after the consumer is cancelled at any point",
        .hangGuard,
        arguments: [2, 8, Int.max]
    )
    func endsWhenCancelledAtAnyPoint(concurrency: Int) async {
        for stopAfter in 1...50 {
            let source = AsyncStream<Int> { continuation in
                for i in 0..<100 {
                    continuation.yield(i)
                }
                continuation.finish()
            }

            let consumer = Task {
                var taken: [Int] = []
                for await value in source.mapAsyncOrdered(
                    concurrency: concurrency,
                    { element in
                        for _ in 0..<(element % 3) {
                            await Task.yield()
                        }
                        return element
                    }
                ) {
                    taken.append(value)
                    if taken.count == stopAfter {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
                return taken
            }

            #expect(await consumer.value == Array(0..<stopAfter))
        }
    }
}
