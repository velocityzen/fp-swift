# Benchmarks

Performance benchmarks for FP, built on [ordo-one/benchmark](https://github.com/ordo-one/benchmark). They live in their own package so the library never depends on the benchmark package.

Every benchmark records wall clock and CPU time, instructions, malloc count and bytes, bytes not freed, object allocations, and retain and release counts. All values are **per call** of the API under test.

## Suites

| Target | Covers |
| --- | --- |
| `ArrayBenchmarks` | `traverse`, sequential and concurrent `traverseAsync`, `mapAsync`, `compactMapAsync`, `flatMapAsync`, `separate`, `successes`, `failures` |
| `AsyncSequenceBenchmarks` | `mapAsyncOrdered`, `compactMapAsyncOrdered`, `mapAsyncUnordered`, `compactMapAsyncUnordered` and their `Result` variants at several concurrency levels, early termination, and the `Result` operators on async sequences |
| `CombinatorBenchmarks` | `withAll`, `withAny`, `withTimeout` |
| `RetryBenchmarks` | `withRetry` with a first-attempt success, with every attempt failing, with a composed policy, and with failures that ask for a wait, all with `.zero` delays |

Most benchmarks run at `n: 16` and `n: 1024` elements, to separate the fixed cost of a call from its cost per element, and the concurrent ones at several `concurrency` levels. Transforms are trivial (`$0 &* 2`), so the numbers are the operator's own overhead rather than the work it runs.

Entries marked `(baseline)` are the hand-written floor for the same job (`Array.map`, a plain `for await`, the standard library's async `map` and `compactMap`, a raw `withTaskGroup`, `async let`). The gap between a baseline and the FP operator next to it is what an optimization can win back.

## Running

Requires Swift 6.3 or later. Malloc statistics come from the benchmark package's malloc interposer, so there is nothing to install.

Run everything from this directory:

```bash
swift package benchmark
```

Run one suite, or the benchmarks whose names match a regular expression. The expression must match the whole name without its `(n: …, concurrency: …)` tags, so a filter selects every size of a benchmark:

```bash
swift package benchmark --target ArrayBenchmarks
```

```bash
swift package benchmark --filter "traverseAsync.*"
```

List the benchmarks without running them:

```bash
swift package benchmark list
```

## Comparing before and after a change

Record a baseline, make the change, then compare the new code against it:

```bash
swift package --allow-writing-to-package-directory benchmark baseline update main
```

```bash
swift package benchmark baseline compare main
```

Baselines are saved in `.benchmarkBaselines/`, which is not committed: they are only comparable on the machine that recorded them.

Malloc, object-allocation and ARC counts are stable from run to run, so they are the numbers to watch first. The exceptions race: the concurrent maps above `concurrency: 1` start workers as they need them, so their counts move with how many workers a call starts, and `withTimeout`'s move with how often its timer task is asleep before it is cancelled. Times move with the machine's load; close other work before comparing them.

`baseline check` fails only when one of those four counts gets worse; times and the other metrics are reported by `compare` but never fail a check. A count may move by 5% at the median (`checkedTolerance` in [BenchmarkSupport.swift](Sources/BenchmarkSupport/BenchmarkSupport.swift)). The racing benchmarks move with the machine's load by more than any percentage that would still catch a regression, so they get an absolute allowance instead: the concurrent maps by the workers their pool can start (`workerPoolAllowance`), and `withTimeout` by the difference between its two paths plus half a call (`raceSwing`). `baseline check` prints raw samples, each the total of 1,000 calls at `scaling: .kilo`, so its counts and allowances there are 1,000 times a call's.

```bash
swift package benchmark baseline check main
```

## Continuous integration

The [Benchmarks workflow](../.github/workflows/benchmarks.yml) benchmarks every push to `main` against the commit it was pushed on top of, and every pull request against its base branch. The job summary lists every metric's change, and the job fails when an allocation or ARC count regresses; the job log shows every count that crossed its threshold. A check takes its thresholds from the baseline it compares with, so a change to the thresholds applies from the commit after it.

## Finding where allocations come from

Print the call stacks behind each benchmark's allocations, most frequent first:

```bash
swift package benchmark --target ArrayBenchmarks --filter "traverseAsync\(concurrency:\).*" --allocation-stacks
```

## Profiling

Each suite is an ordinary executable that runs all of its benchmarks when launched on its own, so it can be profiled in Instruments or debugged in lldb:

```bash
swift build -c release --product ArrayBenchmarks
```
