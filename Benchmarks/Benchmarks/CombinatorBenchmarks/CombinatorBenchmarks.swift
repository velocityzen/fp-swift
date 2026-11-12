import Benchmark
import BenchmarkSupport
import FP

// `withAll`, `withAny` and `withTimeout`. Every operation returns at once,
// so the numbers are the combinator's own cost: a child task per operation
// and the coordination that decides when the call returns.

func succeed(_ value: Int) async -> IntResult {
    .success(value)
}

func succeedWide(_ value: Int) async -> Result<Wide, BenchError> {
    .success(Wide(value))
}

func fail() async -> IntResult {
    .failure(BenchError())
}

let benchmarks: @Sendable () -> Void = {
    // MARK: withAll

    Benchmark("async let (baseline)", configuration: .fp(["arity": "5"])) { benchmark in
        for _ in benchmark.scaledIterations {
            async let a = succeed(1)
            async let b = succeed(2)
            async let c = succeed(3)
            async let d = succeed(4)
            async let e = succeed(5)
            blackHole(flatten(await a, await b, await c, await d, await e))
        }
    }

    Benchmark("withAll", configuration: .fp(["arity": "2"])) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(await withAll(await succeed(1), await succeed(2)))
        }
    }

    Benchmark("withAll", configuration: .fp(["arity": "5"])) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(
                await withAll(
                    await succeed(1),
                    await succeed(2),
                    await succeed(3),
                    await succeed(4),
                    await succeed(5)
                )
            )
        }
    }

    Benchmark("withAll", configuration: .fp(["arity": "10"])) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(
                await withAll(
                    await succeed(1),
                    await succeed(2),
                    await succeed(3),
                    await succeed(4),
                    await succeed(5),
                    await succeed(6),
                    await succeed(7),
                    await succeed(8),
                    await succeed(9),
                    await succeed(10)
                )
            )
        }
    }

    // `Wide` does not fit an existential's inline buffer, so this allocates
    // more than `withAll` of `Int`s if values pass through `any Sendable`.
    Benchmark("withAll Wide", configuration: .fp(["arity": "5"])) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(
                await withAll(
                    await succeedWide(1),
                    await succeedWide(2),
                    await succeedWide(3),
                    await succeedWide(4),
                    await succeedWide(5)
                )
            )
        }
    }

    Benchmark("withAll failing", configuration: .fp(["arity": "5"])) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(
                await withAll(
                    await succeed(1),
                    await fail(),
                    await succeed(3),
                    await succeed(4),
                    await succeed(5)
                )
            )
        }
    }

    // MARK: withAny

    Benchmark("withAny", configuration: .fp(["arity": "2"])) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(await withAny(await succeed(1), await succeed(2)))
        }
    }

    Benchmark("withAny", configuration: .fp(["arity": "10"])) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(
                await withAny(
                    await succeed(1),
                    await succeed(2),
                    await succeed(3),
                    await succeed(4),
                    await succeed(5),
                    await succeed(6),
                    await succeed(7),
                    await succeed(8),
                    await succeed(9),
                    await succeed(10)
                )
            )
        }
    }

    Benchmark("withAny all failing", configuration: .fp(["arity": "5"])) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(
                await withAny(await fail(), await fail(), await fail(), await fail(), await fail())
            )
        }
    }

    let operations: [@concurrent @Sendable () async -> IntResult] = (0..<100).map { index in
        { await succeed(index) }
    }

    Benchmark("withAny array", configuration: .fp(["count": "100"], scaling: .one)) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(await withAny(operations))
        }
    }

    // MARK: withTimeout

    // The operation wins every time, so this is the cost of starting and
    // cancelling the timer task. Whether the timer task is already asleep
    // when it is cancelled is a race, and asleep costs one more retain,
    // release and malloc. On a single-thread pool it always is; the default
    // pool mixes the two by the machine's load, which has moved the median
    // by half a retain per call between runs of the same code on CI.
    let timerRace: [BenchmarkMetric: Int] = [
        .mallocCountTotal: 1,
        .retainCount: 1,
        .releaseCount: 1,
    ]
    Benchmark("withTimeout", configuration: .fp(raceSwing: timerRace)) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(
                await withTimeout(.seconds(60), failingWith: BenchError()) { await succeed(1) }
            )
        }
    }
}
