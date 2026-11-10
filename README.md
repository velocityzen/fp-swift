# fp-swift

[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fvelocityzen%2Ffp-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/velocityzen/fp-swift)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fvelocityzen%2Ffp-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/velocityzen/fp-swift)
[![Documentation](https://img.shields.io/badge/documentation-DocC-purple)](https://swiftpackageindex.com/velocityzen/fp-swift/documentation/fp)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

fp-swift adds functional helpers to Swift's own `Result`, `Optional` and `Array` types, for sync and async code. Chain steps that can fail, recover from errors, run work in parallel, and retry. Swift has no higher-kinded types yet, so this is a set of helpers, not a full functional programming library.

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Pipe operators](#pipe-operators)
- [Working with results](#working-with-results)
- [Recovering from failures](#recovering-from-failures)
- [Optionals](#optionals)
- [Do notation](#do-notation)
- [Async results](#async-results)
- [Arrays](#arrays)
- [Combining results](#combining-results)
- [Racing and timeouts](#racing-and-timeouts)
- [Async sequences of results](#async-sequences-of-results)
- [Concurrent mapping](#concurrent-mapping)
  - [Keeping the source order](#keeping-the-source-order)
  - [In the order they finish](#in-the-order-they-finish)
- [Retrying](#retrying)
  - [Retry only some failures](#retry-only-some-failures)
  - [Use the retry status](#use-the-retry-status)
  - [Built-in policies](#built-in-policies)
  - [Jitter](#jitter)
  - [Write your own policy](#write-your-own-policy)
  - [Check a policy](#check-a-policy)
  - [Clock, cancellation and actors](#clock-cancellation-and-actors)
- [API reference](#api-reference)
- [Benchmarks](#benchmarks)
- [License](#license)

## Installation

Requirements:

- Swift 6.3 or later
- macOS, iOS, tvOS, watchOS or visionOS 26 or later, or Linux

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/velocityzen/fp-swift.git",
        from: "4.3.0"
    ),
],
```

Then add the products your target uses:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "FP", package: "fp-swift"),
        // Only if you need retries:
        .product(name: "FPRetry", package: "fp-swift"),
    ]
),
```

`FPRetry` does not depend on `FP`, so a target that only retries can use it alone.

## Quick start

```swift
import FP

enum AppError: Error {
    case notANumber(String)
}

func parse(_ text: String) -> Result<Int, AppError> {
    .fromOptional(Int(text), error: .notANumber(text))
}

let doubled = parse("21")
    .tap { n in print("parsed", n) }  // prints "parsed 21"
    .map { n in n * 2 }
    .getOrElse(0)                     // 42
```

`Result` is Swift's own type. fp-swift adds methods like `tap` and `getOrElse` to it. A failure skips the steps that change values, so `parse("x")` gives 0.

## Pipe operators

`x |> f` calls `f(x)`. A chain of them reads in the order the steps run:

```swift
func double(_ n: Int) -> Int { n * 2 }
func label(_ n: Int) -> String { "#\(n)" }

let text = 5 |> double |> label  // "#10"
```

`|>>` passes the value as the second argument, and `|>>>` as the third:

```swift
func add(_ a: Int, _ b: Int) -> Int { a + b }

let sum = 2 |>> (add, 10)  // add(10, 2), so 12
```

The operators also take `async` functions. A chain becomes `async` when one of its steps is:

```swift
let page = await id
    |> normalize  // sync
    |> loadUser   // async
    |> render     // sync
```

The operators bind looser than arithmetic and `??`, but tighter than comparisons and `&&`. So the whole expression on the left goes into the function:

```swift
1 + 2 |> double   // double(3), not 1 + double(2)
x |> double == 6  // (x |> double) == 6
```

## Working with results

fp-swift adds these methods to `Result`:

| Method                        | What it does                                                 |
| ----------------------------- | ------------------------------------------------------------ |
| `tap { value in … }`          | Runs a side effect on a success. The result does not change. |
| `tapError { error in … }`     | Runs a side effect on a failure.                             |
| `finally { … }`               | Runs a side effect in both cases.                            |
| `as(value)`                   | Replaces the success value with `value`.                     |
| `asUnit()`                    | Replaces the success value with `()`.                        |
| `isSuccess`, `isFailure`      | `true` for a success, or for a failure.                      |
| `match(onSuccess, onFailure)` | Turns both cases into one value.                             |

```swift
let greeting = fetchUser(id: 1)
    .tap { user in cache.save(user) }
    .tapError { error in log(error) }
    .match(
        { user in "Hello, \(user.name)" },
        { error in "Error: \(error)" }
    )
```

`match` also takes plain values: `result.match("ok", "error")`.

`tap` and `tapError` also take a closure that throws, or one that returns a `Result`. Then an error from the closure becomes the failure.

## Recovering from failures

| Method                       | Gives                                                                     |
| ---------------------------- | ------------------------------------------------------------------------- |
| `alt { otherResult }`        | `self` if it is a success, or else the other `Result`.                    |
| `orElse { error in result }` | Like `alt`, but the closure gets the error and can change its type.       |
| `getOrElse(value)`           | The success value, or `value`.                                            |
| `getOrElse { error in … }`   | The success value, or a value made from the error.                        |
| `getOrExit()`                | The success value, or prints the error and exits. For command-line tools. |
| `orExit()`                   | Nothing, or prints the error and exits.                                   |

```swift
let user = fetchUser(id: 1)
    .alt { fetchCachedUser(id: 1) }
    .getOrElse(.guest)
```

In a command-line tool:

```swift
let config = loadConfig().getOrExit()
// On a failure, prints "Error: <error>" to stderr and exits with 1.
```

`getOrExit(prefix:exitCode:)` and `getOrExit { error in message }` change the message and the exit code. `orExit` takes the same arguments.

## Optionals

`Result.fromOptional` turns an `Optional` into a `Result`:

```swift
let result: Result<User, AppError> =
    .fromOptional(cachedUser, error: .notFound)
```

To make the error only when it is needed, pass a closure: `.fromOptional(cachedUser) { .notFound }`.

fp-swift also adds a few methods to `Optional`:

```swift
let name: String? = nil

name.match({ n in "Hi, \(n)" }, "Hi, guest")  // "Hi, guest"
name.orElse(nickname)     // the first value that is not nil
name.getOrElse("guest")   // like ??
```

`mapAsync`, `flatMapAsync`, `orElseAsync` and `getOrElseAsync` take async closures. `finally` runs a side effect in both cases.

## Do notation

`ResultDo` chains steps that need the values of the steps before them. `bind` adds a step that returns a `Result`, and `let` adds a plain value. Each closure gets all the values so far. The chain stops at the first failure.

```swift
func order(userID: Int, itemID: Int) -> Result<Order, AppError> {
    ResultDo<AppError>()
        .bind { fetchUser(id: userID) }
        .bind { user in fetchItem(id: itemID) }
        .let { user, item in item.price * user.discount }
        .map { user, item, price in
            Order(user: user, item: item, price: price)
        }
}
```

`bindAsync` and `letAsync` take async closures. You can mix them with `bind` and `let` in one chain. A chain holds up to 10 values.

## Async results

`mapAsync`, `flatMapAsync`, `mapErrorAsync`, `tapAsync`, `tapErrorAsync`, `altAsync` and the other `Async` methods take async closures:

```swift
func profile(id: Int) async -> Result<Profile, AppError> {
    await fetchUser(id: id)
        .tapAsync { user in await analytics.track(user) }
        .flatMapAsync { user in await loadProfile(of: user) }
}
```

To call async code that throws, use `Result.fromAsync`. The failure type is then `any Error`:

```swift
let data = await Result.fromAsync {
    try await loadData()
}
```

`Result.fromTask(task)` waits for a `Task` and turns its value or error into a `Result`.

## Arrays

| Method                                        | What it does                                                                |
| --------------------------------------------- | --------------------------------------------------------------------------- |
| `traverse { element in result }`              | Turns each element into a `Result`. Gives all values, or the first failure. |
| `traverseAsync { … }`                         | The same with an async closure, one element at a time.                      |
| `traverseAsync(concurrency: n) { … }`         | Runs up to `n` closures at the same time. See below.                        |
| `separate()`                                  | Splits `[Result]` into `(successes, failures)`.                             |
| `successes()`, `failures()`                   | One side of `[Result]`.                                                     |
| `compact()`                                   | Removes the `nil` elements of `[T?]`.                                       |
| `sequence()`                                  | Turns `[T?]` into `[T]?`. It is `nil` if any element is `nil`.              |
| `mapAsync`, `flatMapAsync`, `compactMapAsync` | `map`, `flatMap` and `compactMap` with an async closure.                    |

```swift
let ids = [1, 2, 3]

let users = ids.traverse { id in fetchUser(id: id) }
// .success([User]), or the first failure

let loaded = await ids.traverseAsync(concurrency: 4) { id in
    await loadUser(id: id)
}
```

With `concurrency:`, the values keep the array order. When elements fail, it gives the failure of the first one in the array, and cancels the closures that still run.

## Combining results

`flatten` combines up to 10 results into one result of a tuple. It gives the first failure, if there is one:

```swift
let both = flatten(fetchUser(id: 1), fetchSettings(id: 1))
// Result<(User, Settings), AppError>
```

`withAll` does the same with async calls, and runs them at the same time. The first failure returns at once and cancels the other calls:

```swift
let home = await withAll(
    await loadUser(id: 1),
    await loadMessages(id: 1)
)
// Result<(User, [Message]), AppError>
```

## Racing and timeouts

`withAny` runs async calls at the same time and gives the first success. A failure does not win: the other calls keep running. The winner cancels the rest. When all fail, it gives the last failure.

```swift
let data = await withAny(
    await download(from: primary),
    await download(from: backup)
)
```

For a number of calls known only at run time, pass an array of closures. It must not be empty.

`withTimeout` gives the result of an async call, or a failure when the time runs out. Then it cancels the call. A failure that comes in time is returned as it is.

```swift
let profile = await withTimeout(.seconds(5), failingWith: .timeout) {
    await loadProfile(id: 1)
}
```

Cancellation stops only code that checks for it, like `Task.sleep` and `URLSession` calls. A long loop with no `await` runs to its end.

## Async sequences of results

For an `AsyncSequence` of `Result`s, fp-swift adds `successes()`, `failures()`, `map`, `mapError`, `flatMap`, `tap`, `tapError` and their `Async` versions. Each one works on one side, and the other side passes through:

```swift
let names = events
    .tapError { error in log(error) }
    .mapAsync { id in await loadName(id) }
    .successes()

for await name in names {
    show(name)
}
```

`AsyncStream.success(value)` and `.failure(error)` make a stream of one result. On a continuation, `success`, `failure`, `finishWithSuccess` and `finishWithFailure` add results:

```swift
let stream = AsyncStream<Result<Int, AppError>> { continuation in
    continuation.success(1)
    continuation.finishWithFailure(.timeout)
}
```

## Concurrent mapping

These map an async sequence with an async transform. Up to `concurrency` transforms run at the same time. The default is 1: one at a time.

| Operators                                                                | Results come out         |
| ------------------------------------------------------------------------ | ------------------------ |
| `mapAsyncOrdered`, `flatMapAsyncOrdered`, `compactMapAsyncOrdered`       | in source order          |
| `mapAsyncUnordered`, `flatMapAsyncUnordered`, `compactMapAsyncUnordered` | in the order they finish |

Rules:

- No new element is read while `concurrency` elements are being transformed or waiting for the consumer. So a slow consumer pauses the source.
- When the consumer stops, reading stops and running transforms are cancelled.
- On a sequence of `Result`s, `map…` and `flatMap…` change only the successes. Failures pass through in their place.
- `compactMap…` drops `nil` results. Its `passthrough:` gives a result without the transform, for example a cache hit.

For an all-or-nothing pass over an array, use `traverseAsync(concurrency:)` instead (see [Arrays](#arrays)).

### Keeping the source order

```swift
let images = refs.mapAsyncOrdered(concurrency: 8) { ref in
    await downloader.fetch(ref)
}

for await image in images {
    render(image)
}
```

A slow transform holds back the results after it, but not the work: later elements are still transformed, and their results wait. `bufferLimit:` caps how many results may wait, for example when the source never ends:

```swift
refs.mapAsyncOrdered(concurrency: 8, bufferLimit: 64) { ref in
    await downloader.fetch(ref)
}
```

A `bufferLimit` below `concurrency - 1` also lowers how many transforms run at the same time.

### In the order they finish

Each result comes out when its transform finishes, so a slow element holds back only itself:

```swift
let thumbs = photos.mapAsyncUnordered(concurrency: 8) { photo in
    await renderer.thumbnail(for: photo)
}

for await thumb in thumbs {
    gallery.insert(thumb)
}
```

## Retrying

`FPRetry` retries async operations that return a `Result`. It is based on [retry-ts](https://github.com/gcanti/retry-ts).

A `RetryPolicy` decides two things after each failure: whether to retry, and how long to wait first. Create a policy once and use it in many places.

```swift
import FPRetry

// Wait up to 200ms, 400ms, 800ms and so on, but never more
// than 2s. Retry at most 5 times. Each wait is random (jitter).
let apiPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
    .and(.limitRetries(5))
    .capDelay(.seconds(2))
    .jitter()

let user = await withRetry(apiPolicy) { await loadUser(id: 1) }
// Result<User, APIError>
```

`withRetry` returns the first success. If every attempt fails, it returns the last failure. It never retries a success.

### Retry only some failures

Some failures can pass on the next try, for example a timeout. Others fail every time, for example "not found". Use `while:` to choose which failures to retry: return `true` to retry. Without `while:`, every failure is retried.

You usually put this rule on your error type. `isTransient` is not part of FPRetry. You write it:

```swift
enum APIError: Error, Equatable {
    case timeout
    case rateLimited
    case server(status: Int)
    case notFound

    /// True when the request can succeed if we try again.
    var isTransient: Bool {
        switch self {
            case .timeout, .rateLimited: true
            case .server(let status): status >= 500
            case .notFound: false
        }
    }
}

let user = await withRetry(apiPolicy, while: \.isTransient) {
    await loadUser(id: 1)
}
```

`\.isTransient` is a key path, used as a function. You can also write a closure: `while: { $0 != .notFound }`.

### Use the retry status

The action can take a `RetryStatus`, which tells you which attempt is running:

```swift
let user = await withRetry(apiPolicy) { status in
    print("attempt", status.iteration + 1)
    return await loadUser(id: 1)
}
```

`RetryStatus` has three values:

- `iteration`: the number of retries so far. It is `0` on the first attempt.
- `cumulativeDelay`: the total time waited so far.
- `previousDelay`: the last wait. It is `nil` on the first attempt.

### Built-in policies

| Policy                                 | Wait before each retry                              | Stops                                          |
| -------------------------------------- | --------------------------------------------------- | ---------------------------------------------- |
| `.limitRetries(n)`                     | no wait                                             | after `n` retries                              |
| `.constantDelay(d)`                    | `d`                                                 | never                                          |
| `.exponentialBackoff(d)`               | `d`, `2d`, `4d`, …                                  | never                                          |
| `p.and(q)`                             | the longer wait of `p` and `q`                      | when `p` or `q` stops                          |
| `p.capDelay(max)`                      | the wait of `p`, at most `max`                      | when `p` stops                                 |
| `p.limitRetriesByDelay(max)`           | the wait of `p`                                     | when the next wait is longer than `max`        |
| `p.limitRetriesByCumulativeDelay(max)` | the wait of `p`                                     | when the total wait would be longer than `max` |
| `p.jitter(range)`                      | the wait of `p`, times a random number from `range` | when `p` stops                                 |

`constantDelay` and `exponentialBackoff` never stop by themselves. Combine them with a limit, for example `.and(.limitRetries(5))`.

### Jitter

When a server restarts, many clients fail at the same time. With the same policy, they also retry at the same time, and can overload the server again. Jitter makes each wait random, so the retries spread out.

The range holds multipliers, not durations:

| Call                 | Wait                                                   |
| -------------------- | ------------------------------------------------------ |
| `.jitter()`          | from 0 to the full wait. The same as `.jitter(0...1)`. |
| `.jitter(0.5...1)`   | from half the wait to the full wait                    |
| `.jitter(0.8...1.2)` | the wait, plus or minus 20%                            |

Put `jitter` last, after `capDelay`.

For tests that need the same random numbers every time, pass a seeded generator. The standard library has none, so write your own. SplitMix64 takes only a few lines. Here it is called `SeededGenerator`:

```swift
let testPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
    .and(.limitRetries(5))
    .jitter(using: SeededGenerator(seed: 42))
```

The policy keeps the generator, and each use takes the next numbers. To get the same numbers again, create the policy again with the same seed.

### Write your own policy

A policy is a function from a `RetryStatus` to a `Duration?`. Return a duration to wait and retry, or `nil` to stop. Wrap the function in `RetryPolicy { status in … }`, and it works with the built-in policies:

```swift
// Retry the first time at once. Then wait 1 second each time.
let quickThenSlow = RetryPolicy { status in
    status.iteration == 0 ? .zero : .seconds(1)
}

let user = await withRetry(quickThenSlow.and(.limitRetries(3))) {
    await loadUser(id: 1)
}
// Waits: 0s, 1s, 1s, then stops
```

To reuse a policy, add a `static func` in an extension. Then you can write it with a leading dot, like the built-in ones:

```swift
extension RetryPolicy {
    /// Waits `step`, then `2 × step`, then `3 × step`, and so on.
    static func linearBackoff(_ step: Duration) -> RetryPolicy {
        RetryPolicy { status in step * (status.iteration + 1) }
    }
}

let linear = RetryPolicy.linearBackoff(.milliseconds(500))
    .and(.limitRetries(4))
    .capDelay(.milliseconds(1500))
// Waits: 0.5s, 1s, 1.5s, 1.5s, then stops
```

A modifier changes another policy. Write it as an instance method that calls `self(status)` to get the wait of the original policy. This one sets a minimum wait:

```swift
extension RetryPolicy {
    /// Waits at least `minimum` before each retry.
    func minimumDelay(_ minimum: Duration) -> RetryPolicy {
        RetryPolicy { status in
            self(status).map { delay in max(delay, minimum) }
        }
    }
}
```

When the original policy stops, `self(status)` returns `nil`, and `map` keeps it, so the modifier stops too.

### Check a policy

`dryRun()` lists the steps of a policy. It does not run anything and does not wait:

```swift
RetryPolicy.exponentialBackoff(.seconds(1))
    .and(.limitRetries(3))
    .dryRun()
    .map(\.previousDelay)
// [1s, 2s, 4s, nil]
```

`dryRun()` is lazy. For a policy that never stops, take only the first steps: `.dryRun().prefix(10)`.

### Clock, cancellation and actors

- `withRetry` waits on a `ContinuousClock`. To use another clock, for example a test clock that does not really wait, pass `clock:`.
- A wait of zero does not use the clock.
- When the task is cancelled, `withRetry` stops and returns the last failure.
- A wait is never less than zero or more than `RetryPolicy.maximumDelay`, so a long backoff never overflows.
- The action runs on the caller's actor, so code on `@MainActor` can use its own state in it.

## API reference

The operators are in [Pipe operators](#pipe-operators), and the retry API is in [Retrying](#retrying).

`Result`:

| Method                                             | What it does                              |
| -------------------------------------------------- | ----------------------------------------- |
| `tap`, `tapAsync`                                  | Runs a side effect on a success.          |
| `tapError`, `tapErrorAsync`                        | Runs a side effect on a failure.          |
| `finally`, `finallyAsync`                          | Runs a side effect in both cases.         |
| `mapAsync`, `flatMapAsync`, `mapErrorAsync`        | `map`, `flatMap` and `mapError`, async.   |
| `as`, `asUnit`                                     | Replaces the success value.               |
| `match`, `matchAsync`                              | Turns both cases into one value.          |
| `isSuccess`, `isFailure`                           | Checks the case.                          |
| `alt`, `altAsync`                                  | Replaces a failure with another `Result`. |
| `orElse`, `orElseAsync`                            | Makes a new `Result` from the error.      |
| `getOrElse`, `getOrElseAsync`                      | The value, or a fallback.                 |
| `getOrExit`, `orExit`                              | Exits the process on a failure.           |
| `Result.fromOptional`                              | Turns an `Optional` into a `Result`.      |
| `Result.fromAsync`                                 | Runs async code that throws.              |
| `Result.fromTask`                                  | Waits for a `Task`.                       |
| `ResultDo`: `bind`, `let`, `bindAsync`, `letAsync` | Do notation.                              |

Functions:

| Function      | What it does                                                  |
| ------------- | ------------------------------------------------------------- |
| `flatten`     | Combines up to 10 results into a result of a tuple.           |
| `withAll`     | The same for async calls, run at the same time.               |
| `withAny`     | The first success of async calls, run at the same time.       |
| `withTimeout` | The result of an async call, or a failure when time runs out. |

`Optional`:

| Method                        | What it does                         |
| ----------------------------- | ------------------------------------ |
| `match`, `matchAsync`         | Turns both cases into one value.     |
| `mapAsync`, `flatMapAsync`    | `map` and `flatMap`, async.          |
| `orElse`, `orElseAsync`       | The first value that is not `nil`.   |
| `getOrElse`, `getOrElseAsync` | The value, or a default (like `??`). |
| `finally`, `finallyAsync`     | Runs a side effect in both cases.    |

`Array`:

| Method                                        | What it does                               |
| --------------------------------------------- | ------------------------------------------ |
| `traverse`, `traverseAsync`                   | All values, or the first failure.          |
| `separate`, `successes`, `failures`           | Splits `[Result]`.                         |
| `compact`, `sequence`                         | Removes `nil` elements, or all or nothing. |
| `mapAsync`, `flatMapAsync`, `compactMapAsync` | `map`, `flatMap` and `compactMap`, async.  |

`AsyncSequence` and `AsyncStream`:

| Method                                                                     | What it does                                |
| -------------------------------------------------------------------------- | ------------------------------------------- |
| `successes`, `failures`                                                    | One side of a sequence of results.          |
| `map`, `mapError`, `flatMap`, `tap`, `tapError` and their `Async` versions | Work on one side. The other passes through. |
| `mapAsyncOrdered`, `flatMapAsyncOrdered`, `compactMapAsyncOrdered`         | Concurrent, in source order.                |
| `mapAsyncUnordered`, `flatMapAsyncUnordered`, `compactMapAsyncUnordered`   | Concurrent, in the order they finish.       |
| `AsyncStream.success`, `AsyncStream.failure`                               | A stream of one result.                     |
| `success`, `failure`, `finishWithSuccess`, `finishWithFailure`             | Add a result on a continuation.             |

## Benchmarks

The benchmarks measure allocations, reference counting and time for the traversals, the concurrent maps and the parallel combinators. They are in their own package, in [`Benchmarks/`](Benchmarks/README.md):

```bash
cd Benchmarks && swift package benchmark
```

## License

Released under the [MIT License](LICENSE).
