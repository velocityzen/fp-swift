import Benchmark
import BenchmarkSupport
import FPRetry

// `withRetry` against the loop it replaces. Every delay is `.zero`, so no
// call sleeps and the numbers are the cost of the retry loop and of asking
// the policy, not of a clock.

func succeed() async -> IntResult {
    .success(1)
}

func fail() async -> IntResult {
    .failure(BenchError())
}

/// The hand-written floor: run once, then retry at once up to `times` times.
func retryLoop(times: Int, _ action: () async -> IntResult) async -> IntResult {
    var result = await action()
    var retries = 0
    while case .failure = result, retries < times, !Task.isCancelled {
        retries += 1
        result = await action()
    }
    return result
}

let benchmarks: @Sendable () -> Void = {
    // MARK: First attempt succeeds

    Benchmark("retry succeeding (baseline)", configuration: .fp()) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(await retryLoop(times: 3, succeed))
        }
    }

    let limited = RetryPolicy.limitRetries(3)

    Benchmark("withRetry succeeding", configuration: .fp()) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(await withRetry(limited, succeed))
        }
    }

    // MARK: Every attempt fails

    for times in [3, 10] {
        let tags = ["retries": "\(times)"]
        let policy = RetryPolicy.limitRetries(times)

        Benchmark("retry failing (baseline)", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await retryLoop(times: times, fail))
            }
        }

        Benchmark("withRetry failing", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await withRetry(policy, fail))
            }
        }

        // Three modifiers deep: every retry asks each of them.
        let composed = RetryPolicy.exponentialBackoff(.zero)
            .and(.limitRetries(times))
            .capDelay(.seconds(1))
            .limitRetriesByCumulativeDelay(.seconds(60))

        Benchmark("withRetry failing composed", configuration: .fp(tags)) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(await withRetry(composed, fail))
            }
        }
    }
}
