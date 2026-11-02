import Foundation
import Synchronization
import Testing

@testable import FP

/// The numbers `0..<count`, afresh for every iterator.
private struct Numbers: AsyncSequence, Sendable {
    let count: Int

    func makeAsyncIterator() -> Iterator {
        Iterator(count: count)
    }

    struct Iterator: AsyncIteratorProtocol {
        let count: Int
        var current = 0

        mutating func next() async -> Int? {
            guard current < count else { return nil }
            defer { current += 1 }
            return current
        }
    }
}

@Suite("AsyncSequence+Unordered Tests")
struct AsyncSequenceUnorderedTests {
    enum TestError: Error, Equatable {
        case failed
        case other
    }

    // MARK: - mapAsyncUnordered

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncUnordered transforms each element")
    func transformsEachElement() async {
        let stream = AsyncStream<Int> { continuation in
            for value in 1...3 { continuation.yield(value) }
            continuation.finish()
        }

        var values: [String] = []
        for await value in stream.mapAsyncUnordered({ "v\($0)" }) {
            values.append(value)
        }

        // one at a time, completion order is source order
        #expect(values == ["v1", "v2", "v3"])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncUnordered emits later results while an earlier transform is still running")
    func emitsInCompletionOrder() async {
        let source = AsyncStream<Int> { continuation in
            for value in 1...4 { continuation.yield(value) }
            continuation.finish()
        }
        // Element 1 waits on this gate, so it stays unfinished until the
        // others are out, however slowly the runner schedules tasks.
        let (gate, gateCont) = AsyncStream.makeStream(of: Void.self)

        var values: [Int] = []
        for await value in source.mapAsyncUnordered(
            concurrency: 4,
            { element in
                if element == 1 {
                    for await _ in gate {}
                }
                return element
            }
        ) {
            values.append(value)
            if values.count == 3 {
                gateCont.finish()
            }
        }

        #expect(values.prefix(3).sorted() == [2, 3, 4])
        #expect(values.last == 1)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncUnordered runs transforms concurrently")
    func transformsRunConcurrently() async {
        let tracker = ConcurrencyTracker()
        let stream = AsyncStream<Int> { continuation in
            for value in 1...4 { continuation.yield(value) }
            continuation.finish()
        }

        var values: [Int] = []
        for await value in stream.mapAsyncUnordered(
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
        #expect(values.sorted() == [1, 2, 3, 4])
        // Overlap is observed directly, never by a wall-clock upper bound
        // (see the ordered tests' transformsRunConcurrently).
        #expect(highWater >= 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncUnordered finishes when source is empty", arguments: [1, 4])
    func finishesOnEmptySource(concurrency: Int) async {
        let stream = AsyncStream<Int> { continuation in
            continuation.finish()
        }

        var values: [Int] = []
        for await value in stream.mapAsyncUnordered(concurrency: concurrency, { $0 * 2 }) {
            values.append(value)
        }

        #expect(values.isEmpty)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncUnordered never exceeds the concurrency limit")
    func respectsConcurrencyLimit() async {
        let tracker = ConcurrencyTracker()
        let source = AsyncStream<Int> { continuation in
            for i in 1...10 { continuation.yield(i) }
            continuation.finish()
        }

        var results: [Int] = []
        for await value in source.mapAsyncUnordered(
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

        let highWater = await tracker.highWater
        #expect(results.sorted() == [2, 4, 6, 8, 10, 12, 14, 16, 18, 20])
        #expect(highWater <= 3)
        #expect(highWater >= 1)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncUnordered defaults to running transforms one at a time in order")
    func defaultIsSequential() async {
        let tracker = ConcurrencyTracker()
        let source = AsyncStream<Int> { continuation in
            for i in 1...5 { continuation.yield(i) }
            continuation.finish()
        }

        var results: [Int] = []
        for await value in source.mapAsyncUnordered({ element in
            await tracker.enter()
            // later elements finish faster, but none starts before the last ends
            try? await Task.sleep(for: .milliseconds(6 - element))
            await tracker.exit()
            return element
        }) {
            results.append(value)
        }

        let highWater = await tracker.highWater
        #expect(results == [1, 2, 3, 4, 5])
        #expect(highWater == 1)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncUnordered iterates its source afresh for every iterator", arguments: [1, 4])
    func iteratesAfresh(concurrency: Int) async {
        let mapped = Numbers(count: 5).mapAsyncUnordered(concurrency: concurrency, { $0 * 10 })

        var first: [Int] = []
        for await value in mapped {
            first.append(value)
        }
        var second: [Int] = []
        for await value in mapped {
            second.append(value)
        }

        #expect(first.sorted() == [0, 10, 20, 30, 40])
        #expect(second.sorted() == [0, 10, 20, 30, 40])
    }

    // MARK: - compactMapAsyncUnordered

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("compactMapAsyncUnordered drops nil results", arguments: [1, 3])
    func compactMapDropsNils(concurrency: Int) async {
        var values: [Int] = []
        for await value in Numbers(count: 10).compactMapAsyncUnordered(
            concurrency: concurrency,
            { $0.isMultiple(of: 2) ? $0 : nil }
        ) {
            values.append(value)
        }

        #expect(values.sorted() == [0, 2, 4, 6, 8])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("compactMapAsyncUnordered frees the slot of every dropped element", .hangGuard)
    func droppedElementsFreeTheirSlots() async {
        // Were a dropped element to keep its slot, the reader would stall
        // once `concurrency` of them had been dropped.
        var values: [Int] = []
        for await value in Numbers(count: 1_000).compactMapAsyncUnordered(
            concurrency: 2,
            { $0.isMultiple(of: 2) ? nil : $0 }
        ) {
            values.append(value)
        }

        #expect(values.sorted() == Array(stride(from: 1, to: 1_000, by: 2)))
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("compactMapAsyncUnordered ends when every element is dropped", arguments: [1, 4])
    func compactMapAllDropped(concurrency: Int) async {
        var values: [Int] = []
        for await value in Numbers(count: 20).compactMapAsyncUnordered(
            concurrency: concurrency,
            { (_: Int) -> Int? in nil }
        ) {
            values.append(value)
        }

        #expect(values.isEmpty)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("compactMapAsyncUnordered passthrough skips the transform", arguments: [1, 3])
    func passthroughSkipsTransform(concurrency: Int) async {
        let calls = AsyncCounter()

        var values: [Int] = []
        for await value in Numbers(count: 10).compactMapAsyncUnordered(
            concurrency: concurrency,
            passthrough: { $0.isMultiple(of: 3) ? -$0 : nil },
            { element in
                await calls.increment()
                return element
            }
        ) {
            values.append(value)
        }

        let count = await calls.count
        #expect(values.sorted() == [-9, -6, -3, 0, 1, 2, 4, 5, 7, 8])
        // 0, 3, 6 and 9 passed through
        #expect(count == 6)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("compactMapAsyncUnordered emits passed-through elements while every worker is busy")
    func passthroughDoesNotWaitForWorkers() async {
        let source = AsyncStream<Int> { continuation in
            for value in [1, -1, -2, -3] { continuation.yield(value) }
            continuation.finish()
        }
        let (gate, gateCont) = AsyncStream.makeStream(of: Void.self)

        var values: [Int] = []
        for await value in source.compactMapAsyncUnordered(
            concurrency: 2,
            passthrough: { $0 < 0 ? $0 : nil },
            { element in
                // the only transform, and it waits until the rest are out
                for await _ in gate {}
                return element
            }
        ) {
            values.append(value)
            if values.count == 3 {
                gateCont.finish()
            }
        }

        #expect(values == [-1, -2, -3, 1])
    }

    // MARK: - mapAsyncUnordered / flatMapAsyncUnordered (Result)

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "mapAsyncUnordered on Result transforms successes and passes failures through",
        arguments: [1, 3]
    )
    func resultTransformsSuccessesPassesFailures(concurrency: Int) async {
        let calls = AsyncCounter()
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.yield(.failure(.other))
            continuation.finish()
        }

        var successes: [Int] = []
        var failures: [TestError] = []
        for await result in stream.mapAsyncUnordered(
            concurrency: concurrency,
            { (value: Int) -> Int in
                await calls.increment()
                return value * 10
            }
        ) {
            switch result {
                case .success(let value): successes.append(value)
                case .failure(let error): failures.append(error)
            }
        }

        let count = await calls.count
        #expect(successes.sorted() == [10, 20])
        // failures are read, and so emitted, in source order
        #expect(failures == [.failed, .other])
        #expect(count == 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncUnordered on Result emits failures while every worker is busy")
    func resultFailuresDoNotWaitForWorkers() async {
        let source = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.failure(.other))
            continuation.finish()
        }
        let (gate, gateCont) = AsyncStream.makeStream(of: Void.self)

        var results: [Result<Int, TestError>] = []
        for await result in source.mapAsyncUnordered(
            concurrency: 2,
            { (value: Int) -> Int in
                for await _ in gate {}
                return value
            }
        ) {
            results.append(result)
            if results.count == 2 {
                gateCont.finish()
            }
        }

        #expect(results == [.failure(.failed), .failure(.other), .success(1)])
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "flatMapAsyncUnordered transform failures replace the success they came from",
        arguments: [1, 3]
    )
    func flatMapTransformFailureReplacesSuccess(concurrency: Int) async {
        let calls = AsyncCounter()
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.failed))
            continuation.yield(.success(2))
            continuation.finish()
        }

        var successes: [Int] = []
        var failures: [TestError] = []
        for await result in stream.flatMapAsyncUnordered(
            concurrency: concurrency,
            { (value: Int) -> Result<Int, TestError> in
                await calls.increment()
                return value.isMultiple(of: 2) ? .success(value * 10) : .failure(.other)
            }
        ) {
            switch result {
                case .success(let value): successes.append(value)
                case .failure(let error): failures.append(error)
            }
        }

        let count = await calls.count
        #expect(successes == [20])
        #expect(failures.sorted { "\($0)" < "\($1)" } == [.failed, .other])
        #expect(count == 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("flatMapAsyncUnordered forwards concurrency")
    func flatMapOverloadRespectsConcurrencyLimit() async {
        let tracker = ConcurrencyTracker()
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            for i in 1...6 { continuation.yield(.success(i)) }
            continuation.finish()
        }

        var count = 0
        for await _ in stream.flatMapAsyncUnordered(
            concurrency: 2,
            { (value: Int) -> Result<Int, TestError> in
                await tracker.enter()
                try? await Task.sleep(for: .milliseconds(20))
                await tracker.exit()
                return .success(value)
            }
        ) {
            count += 1
        }

        let highWater = await tracker.highWater
        #expect(count == 6)
        #expect(highWater <= 2)
        #expect(highWater >= 1)
    }

    // MARK: - backpressure

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncUnordered does not run ahead of a slow consumer")
    func backpressureBoundsWorkAheadOfConsumer() async {
        let started = AsyncCounter()
        let mapped = Numbers(count: 100).mapAsyncUnordered(
            concurrency: 3,
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
        #expect(first != nil)
        #expect(second != nil)
        // two consumed, plus at most `concurrency` running or waiting
        #expect(observedStarted <= 5)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("compactMapAsyncUnordered counts passed-through elements toward the bound")
    func backpressureBoundsPassthrough() async {
        let passed = Mutex(0)
        let mapped = Numbers(count: 100).compactMapAsyncUnordered(
            concurrency: 3,
            passthrough: { element in
                passed.withLock { $0 += 1 }
                return element
            },
            { $0 }
        )

        var iterator = mapped.makeAsyncIterator()
        let first = await iterator.next()
        try? await Task.sleep(for: .milliseconds(100))

        let observedPassed = passed.withLock { $0 }
        #expect(first == 0)
        // one consumed, plus at most `concurrency` waiting
        #expect(observedPassed <= 4)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncUnordered with concurrency 1 reads nothing ahead of the consumer")
    func sequentialReadsNothingAhead() async {
        let started = AsyncCounter()
        let mapped = Numbers(count: 10).mapAsyncUnordered({ (element: Int) -> Int in
            await started.increment()
            return element
        })

        var iterator = mapped.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        try? await Task.sleep(for: .milliseconds(50))

        let observedStarted = await started.count
        #expect(first == 0)
        #expect(second == 1)
        #expect(observedStarted == 2)
    }

    // MARK: - cancellation

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "mapAsyncUnordered cancels in-flight transforms when the consumer is cancelled",
        .hangGuard
    )
    func cancelsInFlightOnCancellation() async {
        let started = AsyncCounter()
        let cancelled = AsyncCounter()
        let source = AsyncStream<Int> { continuation in
            for i in 1...5 { continuation.yield(i) }
            continuation.finish()
        }

        let consumer = Task {
            for await _ in source.mapAsyncUnordered(
                concurrency: 2,
                { (element: Int) -> Int in
                    await started.increment()
                    await waitForCancellation()
                    await cancelled.increment()
                    return element
                }
            ) {}
        }

        // the window admits exactly two transforms; the rest stay unread
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

        let finalStarted = await started.count
        #expect(finalStarted == 2)
        #expect(observedCancelled == 2)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test("mapAsyncUnordered cancels in-flight transforms when the iterator is dropped", .hangGuard)
    func droppingTheIteratorCancelsInFlight() async {
        let started = AsyncCounter()
        let cancelled = AsyncCounter()
        let source = AsyncStream<Int> { continuation in
            for i in 1...3 { continuation.yield(i) }
            // never finishes
        }

        // The consumer stops without its task being cancelled; releasing
        // the iterator is the only signal the pipeline gets.
        func takeFirst() async -> Int? {
            let mapped = source.mapAsyncUnordered(
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
                // let elements 2 and 3 start before the iterator is dropped
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
        "compactMapAsyncUnordered delivers every element under contention",
        .hangGuard,
        arguments: [2, 3, 8, Int.max]
    )
    func deliversEveryElementUnderContention(concurrency: Int) async {
        let count = 500
        for _ in 0..<20 {
            var results: [Int] = []
            for await value in Numbers(count: count).compactMapAsyncUnordered(
                concurrency: concurrency,
                passthrough: { $0.isMultiple(of: 3) ? $0 : nil },
                { element in
                    // finish out of order: elements yield a varying number of times
                    for _ in 0..<(element % 4) {
                        await Task.yield()
                    }
                    return element.isMultiple(of: 5) ? nil : element
                }
            ) {
                results.append(value)
                // let workers run ahead of the consumer now and then
                if value.isMultiple(of: 7) {
                    await Task.yield()
                }
            }

            let expected = (0..<count).filter { $0.isMultiple(of: 3) || !$0.isMultiple(of: 5) }
            #expect(results.sorted() == expected)
        }
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "mapAsyncUnordered ends right after the consumer is cancelled at any point",
        .hangGuard,
        arguments: [1, 2, 8, Int.max]
    )
    func endsWhenCancelledAtAnyPoint(concurrency: Int) async {
        for stopAfter in 1...50 {
            let consumer = Task {
                var taken: [Int] = []
                for await value in Numbers(count: 100).mapAsyncUnordered(
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

            let taken = await consumer.value
            #expect(taken.count == stopAfter)
            #expect(Set(taken).count == stopAfter)
        }
    }

    // MARK: - The engine in source order

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "mapAsyncKeepOrder on Result keeps failures in place under contention",
        .hangGuard,
        arguments: [2, 8, Int.max]
    )
    func keepOrderPassthroughUnderContention(concurrency: Int) async {
        let source = Numbers(count: 300).map { (element: Int) -> Result<Int, TestError> in
            element.isMultiple(of: 3) ? .failure(.failed) : .success(element)
        }

        var results: [Result<Int, TestError>] = []
        for await result in source.mapAsyncKeepOrder(
            concurrency: concurrency,
            { (value: Int) -> Int in
                for _ in 0..<(value % 4) {
                    await Task.yield()
                }
                return value
            }
        ) {
            results.append(result)
        }

        let expected = (0..<300).map { (element: Int) -> Result<Int, TestError> in
            element.isMultiple(of: 3) ? .failure(.failed) : .success(element)
        }
        #expect(results == expected)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @Test(
        "the engine drops elements in source order without losing its place",
        .hangGuard,
        arguments: [1, 2, 8, Int.max]
    )
    func sourceOrderDropsElements(concurrency: Int) async {
        var results: [Int] = []
        for await value in Numbers(count: 300).keepOrderStream(
            concurrency: concurrency,
            passthrough: { $0.isMultiple(of: 7) ? -$0 : nil },
            { element in
                for _ in 0..<(element % 4) {
                    await Task.yield()
                }
                return element.isMultiple(of: 3) ? nil : element
            }
        ) {
            results.append(value)
        }

        let expected = (0..<300).compactMap { (element: Int) -> Int? in
            element.isMultiple(of: 7) ? -element : element.isMultiple(of: 3) ? nil : element
        }
        #expect(results == expected)
    }
}
