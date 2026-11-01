import Benchmark
import BenchmarkSupport
import FP

// Array traversals: the synchronous and sequential forms, and the
// concurrent `traverseAsync(concurrency:)`. Transforms are trivial so the
// numbers are the traversal's own overhead; "(baseline)" entries are the
// hand-written floor to compare with.

let benchmarks: @Sendable () -> Void = {
    for n in [16, 1024] {
        let input = Array(0..<n)
        let failAt = n / 2
        let tags = ["n": "\(n)"]
        // A call that starts a child task per element takes about a
        // millisecond at 1,024 elements, so it needs no inner loop.
        let taskScaling: BenchmarkScalingFactor = n > 64 ? .one : .kilo

        // MARK: Synchronous

        Benchmark("Array.map (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(input.map { $0 &* 2 })
            }
        }

        Benchmark("traverse", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(input.traverse { $0 &* 2 })
            }
        }

        Benchmark("traverse Result", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(input.traverse { IntResult.success($0 &* 2) })
            }
        }

        // MARK: Sequential async

        Benchmark("traverseAsync", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await input.traverseAsync { $0 &* 2 })
            }
        }

        Benchmark("traverseAsync Result", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await input.traverseAsync { IntResult.success($0 &* 2) })
            }
        }

        Benchmark("traverseAsync Result failing at n/2", configuration: .fp(tags)) {
            benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(
                    await input.traverseAsync { (value: Int) -> IntResult in
                        value == failAt ? .failure(BenchError()) : .success(value)
                    }
                )
            }
        }

        Benchmark("mapAsync", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await input.mapAsync { $0 &* 2 })
            }
        }

        Benchmark("compactMapAsync", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await input.compactMapAsync { $0.isMultiple(of: 2) ? $0 : nil })
            }
        }

        Benchmark("flatMapAsync", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await input.flatMapAsync { CollectionOfOne($0) })
            }
        }

        // MARK: Concurrent

        Benchmark("withTaskGroup (baseline)", configuration: .fp(tags, scaling: taskScaling)) {
            benchmark in
            for _ in benchmark.scaledIterations {
                let values = await withTaskGroup(of: (Int, Int).self) { group in
                    for (index, element) in input.enumerated() {
                        group.addTask { (index, element &* 2) }
                    }
                    var values = [Int](repeating: 0, count: input.count)
                    for await (index, value) in group {
                        values[index] = value
                    }
                    return values
                }
                blackHole(values)
            }
        }

        for (label, concurrency) in [("1", 1), ("8", 8), ("max", Int.max)] {
            let tags = ["n": "\(n)", "concurrency": label]

            Benchmark(
                "traverseAsync(concurrency:)",
                configuration: .fp(tags, scaling: taskScaling)
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(await input.traverseAsync(concurrency: concurrency) { $0 &* 2 })
                }
            }

            Benchmark(
                "traverseAsync(concurrency:) Result",
                configuration: .fp(tags, scaling: taskScaling)
            ) { benchmark in
                for _ in benchmark.scaledIterations {
                    blackHole(
                        await input.traverseAsync(concurrency: concurrency) {
                            IntResult.success($0 &* 2)
                        }
                    )
                }
            }
        }

        Benchmark(
            "traverseAsync(concurrency:) Result failing at n/2",
            configuration: .fp(["n": "\(n)", "concurrency": "8"], scaling: taskScaling)
        ) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(
                    await input.traverseAsync(concurrency: 8) { (value: Int) -> IntResult in
                        value == failAt ? .failure(BenchError()) : .success(value)
                    }
                )
            }
        }

        // MARK: Splitting Results

        let results = input.map { value in
            value.isMultiple(of: 3) ? IntResult.failure(BenchError()) : .success(value)
        }

        Benchmark("separate", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(results.separate())
            }
        }

        Benchmark("successes", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(results.successes())
            }
        }

        Benchmark("failures", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(results.failures())
            }
        }
    }
}
