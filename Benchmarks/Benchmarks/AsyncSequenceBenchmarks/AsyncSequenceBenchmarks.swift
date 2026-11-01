import Benchmark
import BenchmarkSupport
import FP

// `mapAsyncKeepOrder` and the Result operators on async sequences. The
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

        // MARK: mapAsyncKeepOrder

        for concurrency in [1, 8, 64] {
            let tags = ["n": "\(n)", "concurrency": "\(concurrency)"]

            Benchmark(
                "mapAsyncKeepOrder",
                configuration: .fp(tags, scaling: streamScaling)
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await drain(source.mapAsyncKeepOrder(concurrency: concurrency) { $0 &* 2 })
                    )
                }
            }
        }

        for concurrency in [1, 8] {
            let tags = ["n": "\(n)", "concurrency": "\(concurrency)"]

            Benchmark(
                "mapAsyncKeepOrder Result",
                configuration: .fp(tags, scaling: streamScaling)
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await drain(results.mapAsyncKeepOrder(concurrency: concurrency) { $0 &* 2 })
                    )
                }
            }

            Benchmark(
                "flatMapAsyncKeepOrder Result",
                configuration: .fp(tags, scaling: streamScaling)
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await drain(
                            results.flatMapAsyncKeepOrder(concurrency: concurrency) {
                                IntResult.success($0 &* 2)
                            }
                        )
                    )
                }
            }
        }

        // The consumer stops after 8 elements: the cost of tearing the
        // pipeline down while transforms are still in flight.
        Benchmark(
            "mapAsyncKeepOrder taking 8",
            configuration: .fp(["n": "\(n)", "concurrency": "8"], scaling: streamScaling)
        ) { benchmark in
            for _ in benchmark.scaledIterations {
                var taken = 0
                for await value in source.mapAsyncKeepOrder(concurrency: 8, { $0 &* 2 }) {
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
    }
}
