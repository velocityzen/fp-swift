import Benchmark
import BenchmarkSupport
import FP

// The concurrent maps and the Result operators on async sequences. The
// source never suspends or allocates, so the numbers are the operator's own;
// "(baseline)" entries are the floor to compare with.

/// Consumes `sequence` and returns how many elements it produced.
func drain<S: AsyncSequence>(_ sequence: S) async -> Int where S.Failure == Never {
    var count = 0
    for await _ in sequence {
        count += 1
    }
    return count
}

/// `toResult()` written by hand.
func toResultByHand(_ sequence: SuccessSequence) async -> Result<[Int], BenchError> {
    var values: [Int] = []
    for await element in sequence {
        switch element {
            case .success(let value): values.append(value)
            case .failure(let error): return .failure(error)
        }
    }
    return .success(values)
}

/// `toArray()` written by hand.
func toArrayByHand(_ sequence: SuccessSequence) async -> [IntResult] {
    var elements: [IntResult] = []
    for await element in sequence {
        elements.append(element)
    }
    return elements
}

/// `reduce(0, &+)` written by hand.
func sumByHand(_ sequence: SuccessSequence) async -> IntResult {
    var sum = 0
    for await element in sequence {
        switch element {
            case .success(let value): sum &+= value
            case .failure(let error): return .failure(error)
        }
    }
    return .success(sum)
}

/// `separate()` written by hand.
func separateByHand(_ sequence: ResultSequence) async -> ([Int], [BenchError]) {
    var successes: [Int] = []
    var failures: [BenchError] = []
    for await element in sequence {
        switch element {
            case .success(let value): successes.append(value)
            case .failure(let error): failures.append(error)
        }
    }
    return (successes, failures)
}

/// `lastSuccess()` written by hand.
func lastSuccessByHand(_ sequence: ResultSequence) async -> Int? {
    var last: Int?
    for await element in sequence {
        if case .success(let value) = element { last = value }
    }
    return last
}

/// `firstSuccessOrLastError()` written by hand.
func firstSuccessOrLastErrorByHand(_ sequence: FailureSequence) async -> IntResult? {
    var lastFailure: IntResult?
    for await element in sequence {
        if case .success = element { return element }
        lastFailure = element
    }
    return lastFailure
}

/// `failOnCancellation(with:)` and then `toResult()`, written by hand: check for cancellation
/// before each read and when the sequence ends. It reads with the caller's isolation, like
/// `for await` and the sinks do.
func failOnCancellationToResultByHand(
    _ sequence: SuccessSequence
) async -> Result<[Int], BenchError> {
    var values: [Int] = []
    var iterator = sequence.makeAsyncIterator()
    while !Task.isCancelled, let element = await iterator.next(isolation: #isolation) {
        switch element {
            case .success(let value): values.append(value)
            case .failure(let error): return .failure(error)
        }
    }
    return Task.isCancelled ? .failure(BenchError()) : .success(values)
}

/// `reduce(into: []) { $0.append($1 &* 2) }` written by hand.
func reduceIntoByHand(_ sequence: SuccessSequence) async -> Result<[Int], BenchError> {
    var values: [Int] = []
    for await element in sequence {
        switch element {
            case .success(let value): values.append(value &* 2)
            case .failure(let error): return .failure(error)
        }
    }
    return .success(values)
}

/// `asResults().toResult()` written by hand: every value, or the error the
/// sequence throws.
func asResultsToResultByHand(
    _ sequence: ThrowingCountingSequence
) async -> Result<[Int], BenchError> {
    var values: [Int] = []
    do throws(BenchError) {
        for try await value in sequence {
            values.append(value)
        }
    } catch {
        return .failure(error)
    }
    return .success(values)
}

let benchmarks: @Sendable () -> Void = {
    for n in [16, 1024] {
        let tags = ["n": "\(n)"]
        let source = CountingSequence(n)
        let results = ResultSequence(n)
        // A stream that hops between tasks for every element takes tens of
        // microseconds or more at 1,024 elements, so it needs no inner loop.
        let streamScaling: BenchmarkScalingFactor = n > 64 ? .one : .kilo

        // MARK: Baselines

        Benchmark("for await (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await drain(source))
            }
        }

        Benchmark("AsyncMapSequence.map (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await drain(source.map { $0 &* 2 }))
            }
        }

        // MARK: mapAsyncOrdered

        for concurrency in [1, 8, 64] {
            let tags = ["n": "\(n)", "concurrency": "\(concurrency)"]

            let configuration = Benchmark.Configuration.fp(
                tags,
                scaling: streamScaling,
                concurrency: concurrency,
                elements: n
            )

            Benchmark("mapAsyncOrdered", configuration: configuration) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await drain(source.mapAsyncOrdered(concurrency: concurrency) { $0 &* 2 })
                    )
                }
            }
        }

        for concurrency in [1, 8] {
            let tags = ["n": "\(n)", "concurrency": "\(concurrency)"]

            let configuration = Benchmark.Configuration.fp(
                tags,
                scaling: streamScaling,
                concurrency: concurrency,
                elements: n
            )

            Benchmark("mapAsyncOrdered Result", configuration: configuration) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await drain(results.mapAsyncOrdered(concurrency: concurrency) { $0 &* 2 })
                    )
                }
            }

            Benchmark("flatMapAsyncOrdered Result", configuration: configuration) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await drain(
                            results.flatMapAsyncOrdered(concurrency: concurrency) {
                                IntResult.success($0 &* 2)
                            }
                        )
                    )
                }
            }

            // Every other element is dropped.
            Benchmark("compactMapAsyncOrdered", configuration: configuration) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await drain(
                            source.compactMapAsyncOrdered(concurrency: concurrency) {
                                $0 & 1 == 0 ? $0 : nil
                            }
                        )
                    )
                }
            }
        }

        // The consumer stops after 8 elements: the cost of tearing the
        // pipeline down while transforms are still in flight.
        Benchmark(
            "mapAsyncOrdered taking 8",
            configuration: .fp(
                ["n": "\(n)", "concurrency": "8"],
                scaling: streamScaling,
                concurrency: 8,
                elements: n
            )
        ) { benchmark in
            for _ in benchmark.scaledIterations {
                var taken = 0
                for await value in source.mapAsyncOrdered(concurrency: 8, { $0 &* 2 }) {
                    blackHole(value)
                    taken += 1
                    if taken == 8 { break }
                }
            }
        }

        // MARK: mapAsyncUnordered

        // The same job done by hand: a child task per element, at most 8
        // in flight, results in the order they finish.
        Benchmark(
            "withTaskGroup 8 at a time (baseline)",
            configuration: .fp(tags, scaling: streamScaling)
        ) { benchmark in
            for _ in benchmark.scaledIterations {
                let count = await withTaskGroup(of: Int.self) { group in
                    var inFlight = 0
                    var count = 0
                    for await value in source {
                        if inFlight == 8, let result = await group.next() {
                            blackHole(result)
                            count += 1
                            inFlight -= 1
                        }
                        group.addTask { value &* 2 }
                        inFlight += 1
                    }
                    for await result in group {
                        blackHole(result)
                        count += 1
                    }
                    return count
                }
                blackHole(count)
            }
        }

        for concurrency in [1, 8, 64] {
            let tags = ["n": "\(n)", "concurrency": "\(concurrency)"]

            let configuration = Benchmark.Configuration.fp(
                tags,
                scaling: streamScaling,
                concurrency: concurrency,
                elements: n
            )

            Benchmark("mapAsyncUnordered", configuration: configuration) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await drain(source.mapAsyncUnordered(concurrency: concurrency) { $0 &* 2 })
                    )
                }
            }
        }

        for concurrency in [1, 8] {
            let tags = ["n": "\(n)", "concurrency": "\(concurrency)"]

            let configuration = Benchmark.Configuration.fp(
                tags,
                scaling: streamScaling,
                concurrency: concurrency,
                elements: n
            )

            // Every other element is dropped.
            Benchmark("compactMapAsyncUnordered", configuration: configuration) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await drain(
                            source.compactMapAsyncUnordered(concurrency: concurrency) {
                                $0 & 1 == 0 ? $0 : nil
                            }
                        )
                    )
                }
            }

            Benchmark("mapAsyncUnordered Result", configuration: configuration) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await drain(results.mapAsyncUnordered(concurrency: concurrency) { $0 &* 2 })
                    )
                }
            }

            Benchmark("flatMapAsyncUnordered Result", configuration: configuration) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await drain(
                            results.flatMapAsyncUnordered(concurrency: concurrency) {
                                IntResult.success($0 &* 2)
                            }
                        )
                    )
                }
            }
        }

        Benchmark(
            "mapAsyncUnordered taking 8",
            configuration: .fp(
                ["n": "\(n)", "concurrency": "8"],
                scaling: streamScaling,
                concurrency: 8,
                elements: n
            )
        ) { benchmark in
            for _ in benchmark.scaledIterations {
                var taken = 0
                for await value in source.mapAsyncUnordered(concurrency: 8, { $0 &* 2 }) {
                    blackHole(value)
                    taken += 1
                    if taken == 8 { break }
                }
            }
        }

        // MARK: Result operators

        // The same jobs written with the standard library's operators, over
        // the same source of ready-made results.

        Benchmark("for await Results (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await drain(results))
            }
        }

        Benchmark("AsyncMapSequence.map Results (baseline)", configuration: .fp(tags)) {
            benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await drain(results.map { $0.map { $0 &* 2 } }))
            }
        }

        Benchmark(
            "AsyncCompactMapSequence.compactMap Results (baseline)",
            configuration: .fp(tags)
        ) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(
                    await drain(
                        results.compactMap { result -> Int? in
                            guard case .success(let value) = result else { return nil }
                            return value
                        }
                    )
                )
            }
        }

        Benchmark("Result map", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await drain(results.map { $0 &* 2 }))
            }
        }

        Benchmark("Result mapAsync", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await drain(results.mapAsync { $0 &* 2 }))
            }
        }

        Benchmark("Result flatMapAsync", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await drain(results.flatMapAsync { IntResult.success($0 &* 2) }))
            }
        }

        Benchmark("Result successes", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await drain(results.successes()))
            }
        }

        // MARK: Sinks

        // Reading a sequence of results into one value, against the same
        // loop written by hand. The source has no failures, so the sinks
        // that stop at the first failure read all of it.

        let successes = SuccessSequence(n)

        Benchmark("toResult loop (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await toResultByHand(successes))
            }
        }

        Benchmark("Result toResult", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await successes.toResult())
            }
        }

        Benchmark("toArray loop (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await toArrayByHand(successes))
            }
        }

        Benchmark("Result toArray", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await successes.toArray())
            }
        }

        Benchmark("reduce loop (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await sumByHand(successes))
            }
        }

        Benchmark("Result reduce", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await successes.reduce(0, &+))
            }
        }

        // These read to the end, so they read the source with failures in it.

        Benchmark("separate loop (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await separateByHand(results))
            }
        }

        Benchmark("Result separate", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await results.separate())
            }
        }

        Benchmark("lastSuccess loop (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await lastSuccessByHand(results))
            }
        }

        Benchmark("Result lastSuccess", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await results.lastSuccess())
            }
        }

        // With no success, it reads to the end and keeps the last failure.

        let failures = FailureSequence(n)

        Benchmark("firstSuccessOrLastError loop (baseline)", configuration: .fp(tags)) {
            benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await firstSuccessOrLastErrorByHand(failures))
            }
        }

        Benchmark("Result firstSuccessOrLastError", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await failures.firstSuccessOrLastError())
            }
        }

        Benchmark("reduce into loop (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await reduceIntoByHand(successes))
            }
        }

        Benchmark("Result reduce into", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await successes.reduce(into: [Int]()) { $0.append($1 &* 2) })
            }
        }

        // MARK: asResults

        // Every value, then the error the sequence throws where it would end.
        //
        // The operator comes out ahead: its loop inlines the source's
        // `next(isolation:)`, while the hand-written loop makes an async call
        // per read. Over typed-throwing sources both sides are sensitive to how
        // the source is declared and where it lives; this one implements
        // `next(isolation:)` itself, as the standard library's sequences do.

        let throwing = ThrowingCountingSequence(n)

        Benchmark("asResults toResult loop (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await asResultsToResultByHand(throwing))
            }
        }

        Benchmark("Result asResults toResult", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await throwing.asResults().toResult())
            }
        }

        // MARK: failOnCancellation

        // One cancellation check before each read and one at the end, in a
        // task that is not cancelled. The check is an opaque runtime call
        // inside the operator's `next(isolation:)`. The sinks read through a
        // loop with an explicit isolation parameter, so the compiler can
        // remove the operator's hop to the caller's actor; without that, it
        // costs one more executor switch per element.

        Benchmark("failOnCancellation loop (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await failOnCancellationToResultByHand(successes))
            }
        }

        Benchmark("Result failOnCancellation toResult", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await successes.failOnCancellation(with: BenchError()).toResult())
            }
        }

        // MARK: withRepeat

        // `n` pulls of an operation that only returns a number. With an
        // interval of zero the sequence never reads the clock, so the gap to
        // the baseline, which calls the operation in a loop, is the
        // sequence's own cost per pull.

        Benchmark("repeat loop (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                let operation: @Sendable () async -> Int = { n }
                var sum = 0
                for _ in 0..<n {
                    guard !Task.isCancelled else { break }
                    sum &+= await operation()
                }
                blackHole(sum)
            }
        }

        Benchmark("withRepeat", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                var sum = 0
                var count = 0
                for await value in withRepeat(interval: .zero, { n }) {
                    sum &+= value
                    count += 1
                    if count == n { break }
                }
                blackHole(sum)
            }
        }
    }
}
