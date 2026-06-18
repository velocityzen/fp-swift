# ``FP``

A lightweight functional programming toolkit for Swift, providing composable utilities for `Result`, `Optional`, and `Array` types.

## Overview

FP extends Swift's built-in types with functional programming patterns for both synchronous and asynchronous contexts. Chain operations on `Result`, traverse arrays with error handling, compose functions with pipe operators, and more.

### Pipeline with Operators

```swift
let result = input
    |> validate
    |> transform
    |> format
```

Every pipe operator (`|>`, `|>>`, `|>>>`, and prefix `|>`) has an async overload. Sync and async steps mix freely — the chain becomes `async` as soon as one step needs it, and a single `await` covers the whole expression:

```swift
let summary = await userId
    |> normalizeId         // sync
    |> fetchUser           // async
    |> renderSummary       // sync
```

Adding the async overloads is purely additive: in a sync context only the sync overload can match, and in an async context Swift still prefers the sync overload when the closure is sync.

Pipe operators bind looser than arithmetic, ranges, casts, and `??`, but tighter than comparisons, logical operators, and assignment — the same placement as Elixir's `|>` and F#'s pipe family. The full expression on the left flows into the function on the right:

```swift
1 + 2 |> double          // double(3) = 6 — not 1 + double(2)
x |> transform == 6      // (x |> transform) == 6
flag && x |> isValid     // flag && (x |> isValid)
a ?? b |> process        // (a ?? b) |> process
```

### Do Notation

Compose multiple Result operations with an accumulating context, short-circuiting on the first failure:

```swift
func createOrder(userId: Int, itemId: Int) -> Result<Order, AppError> {
    ResultDo<AppError>()
        .bind { fetchUser(id: userId) }
        .bind { user in fetchItem(id: itemId) }
        .let { user, item in item.price * user.discountRate }
        .bind { user, item, price in
            validateOrder(user: user, item: item, price: price)
        }
        .map { user, item, price, validation in
            Order(user: user, item: item, price: price)
        }
}

// Async variant — sync and async steps can be freely mixed
func createOrderAsync(userId: Int, itemId: Int) async -> Result<Order, AppError> {
    await ResultDo<AppError>()
        .bindAsync { await fetchUser(id: userId) }
        .bindAsync { user in await fetchItem(id: itemId) }
        .letAsync { user, item in await discountedPrice(item, for: user) }
        .bindAsync { user, item, price in
            await validateOrder(user: user, item: item, price: price)
        }
        .map { user, item, price, validation in
            Order(user: user, item: item, price: price)
        }
}
```

### Chaining Async Operations

```swift
func processUser(id: Int) async -> Result<ProcessedUser, Error> {
    await Result.fromAsync { try await api.fetchUser(id: id) }
        .tapAsync { user in await analytics.track(.userFetched(user)) }
        .mapAsync { user in await enrichUserData(user) }
        .flatMapAsync { user in await validateUser(user) }
        .tapError { error in logger.error("Failed: \(error)") }
}
```

Existing `Task`s convert the same way:

```swift
let task = Task { try await api.fetchUser(id: 1) }
let result = await Result.fromTask(task)
```

### Transforming Errors

The standard library's `mapError` gets async counterparts on `Result`, and both forms on `AsyncSequence`s of Results:

```swift
let normalized = await fetchUser(id: 1).mapErrorAsync { error in
    await classifier.classify(error)
}

for await result in stream.mapError({ AppError.wrap($0) }) {
    // ...
}
```

### Pattern Matching with Match

```swift
let message = result.match(
    { "value: \($0)" },
    { "error: \($0)" }
)

// Use match for side effects without capturing the result
result.match(
    { value in print("Success: \(value)") },
    { error in print("Error: \(error)") }
)

// Async variants accept async closures on either side
let message = await result.matchAsync(
    { value in await render(value) },
    "fallback"
)
```

### Boolean Checks

```swift
let result: Result<User, AppError> = fetchUser(id: 1)

if result.isSuccess { celebrate() }
if result.isFailure { scheduleRetry() }
```

### Converting Optionals to Results

```swift
let result = Result<User, AppError>.fromOptional(user, error: .notFound)

// With lazy error
let result = Result<User, AppError>.fromOptional(user) {
    .notFound(id: userId)
}
```

### Mapping to Constant Values

```swift
let result: Result<Int, AppError> = .success(42)

// Map to a specific constant
let mapped = result.as("done")  // .success("done")

// Map to Void (discard the success value)
let unit = result.asUnit()  // .success(())
```

### Recovery: alt, orElse, getOrElse

Three ways to handle failure, each with a different trade-off:

| Method       | Receives error? | Can change `Failure` type? | Returns                    |
| ------------ | --------------- | -------------------------- | -------------------------- |
| `alt`        | no              | no                         | `Result<Success, Failure>` |
| `orElse`     | yes             | yes                        | `Result<Success, NewFailure>` |
| `getOrElse`  | yes (closure)   | n/a (unwraps)              | `Success`                  |

- Use `alt` for a blind fallback chain (cache, default branch).
- Use `orElse` when recovery depends on the error, or when you want to normalize/wrap the failure type.
- Use `getOrElse` when you just need the plain value and can compute one from the error.

```swift
// alt — blind chain; type stays Result<User, AppError>
fetchUser(id: 1)
    .alt { fetchUserFromCache(id: 1) }
    .alt { .success(.guest) }

// orElse — branch on the error, optionally change Failure type
fetchUser(id: 1).orElse { error in
    error is Timeout
        ? fetchUser(id: 1)                    // retry, keeps Failure = AppError
        : .failure(AppError.wrap(error))      // normalize to a different Failure type
}

// getOrElse — unwrap to Success
let count = parse(input).getOrElse { _ in 0 }
let count = parse(input).getOrElse(0)  // autoclosure — lazy constant

// Async variants exist for all three
await fetchUser(id: 1).altAsync { await fetchUserFromCache(id: 1) }
await fetchUser(id: 1).orElseAsync { error in await recover(from: error) }
await fetchUser(id: 1).getOrElseAsync(await loadGuestUser())
```

### CLI Entry Points: getOrExit

For command-line tools, `getOrExit` unwraps a success or prints the failure to stderr and calls `Foundation.exit`:

```swift
// Default — "Error: <error>\n" to stderr, exit status 1
let config = loadConfig().getOrExit()

// Custom prefix and exit code
let port = parsePort(args).getOrExit(prefix: "fatal: ", exitCode: 2)

// Fully custom message
let user = fetchUser(id: 1).getOrExit { error in
    "could not load user: \(error)\n"
}

// orExit — discard the success value, exit only on failure
runCommand(args)
    .tap { output in print(output) }
    .orExit()
```

### Side Effects with Tap

```swift
someOperation()
    .tap { value in saveToCache(value) }
    .tapError { error in logError(error) }
    .map { value in transform(value) }

// Async variants
await result
    .tapAsync { value in await sendAnalytics(value) }
    .tapErrorAsync { error in await reportError(error) }
```

### Cleanup with Finally

Run a side effect regardless of success/failure (or `.some`/`.none` for `Optional`) — useful for cleanup, logging, or metrics. Available on both `Result` and `Optional`:

```swift
fetchUser(id: 1)
    .tap { user in cache.store(user) }
    .tapError { error in logger.error("\(error)") }
    .finally { metrics.record(.requestComplete) }

// Async variant
await fetchUser(id: 1).finallyAsync { await spinner.stop() }

// Same on Optional
loadCached(id: 1).finally { spinner.stop() }
```

### Combining Async Results in Parallel

```swift
// All three operations run in parallel
let result = await allAsync(
    await fetchUser(id: userId),
    await fetchNotifications(for: userId),
    await fetchRecommendations(for: userId)
)
// Result<(User, [Notification], [Recommendation]), AppError>
```

### Racing for the First Success

Run several operations concurrently and take the first to finish **with a success**. Unlike a plain "first to finish wins" race, a `.failure` that completes first is passed over while the rest keep running — a fast failure never beats a slower success. The winner cancels the remaining operations; if all of them fail, the last failure to complete is returned.

```swift
// Whichever mirror succeeds first wins; the slower ones are cancelled.
let payload = await raceAsync(
    await fetch(from: primaryMirror),
    await fetch(from: backupMirror),
    await fetch(from: archiveMirror)
)
// Result<Payload, NetworkError>
```

Operations are autoclosures, so calls are deferred and raced — the same ergonomics as `allAsync`. The variadic form takes 2–10 operations; to race a count known only at runtime, pass a (non-empty) array of closures:

```swift
let attempts: [@Sendable () async -> Result<Payload, NetworkError>] =
    mirrors.map { mirror in { await fetch(from: mirror) } }
let payload = await raceAsync(attempts)
```

Cancellation is cooperative — a long racer that ignores `Task.isCancelled` still runs to completion before `raceAsync` returns.

### Batch Processing with Traverse

```swift
func processOrders(_ orderIds: [Int]) async -> Result<[Order], OrderError> {
    await orderIds.traverseAsync { id in
        await fetchAndValidateOrder(id: id)
    }
}
// Sequential: each element awaits the previous one, fails fast on
// first error, returns all orders on success
```

Pass `concurrency:` to run transforms in parallel — results keep source order, the lowest-index failure wins, and in-flight transforms are cancelled cooperatively on failure:

```swift
let orders = await orderIds.traverseAsync(concurrency: 4) { id in
    await fetchAndValidateOrder(id: id)
}
```

Both `traverseAsync(concurrency:)` and `mapAsyncKeepOrder` run transforms in parallel with ordered output. Use `traverseAsync` for an all-or-nothing pass over a finite array — one `Result` at the end, the lowest-index failure wins, a failure cancels the rest. Use `mapAsyncKeepOrder` when you want each result as soon as order allows, have an endless source, or want failures kept in position in the stream.

### Separating Result Arrays

```swift
let results: [Result<Int, ValidationError>] = [
    .success(1),
    .failure(.invalid),
    .success(2),
]

let separated = results.separate()
// separated.successes == [1, 2]
// separated.failures == [.invalid]

// When you only need one side
results.successes()  // [1, 2]
results.failures()   // [.invalid]
```

### Compacting and Sequencing Optional Arrays

```swift
let xs: [Int?] = [1, nil, 2, nil, 3]

// compact — drop the nils
xs.compact()   // [1, 2, 3]

// sequence — all-or-nothing flip to [Int]?
xs.sequence()  // nil (because one element is nil)
[1, 2, 3].map(Optional.some).sequence()  // [1, 2, 3]
```

### Array Async Mapping

```swift
let items = [1, 2, 3, 4, 5]

let mapped = await items.mapAsync { item in
    "v\(item)"
}

let flatMapped = await items.flatMapAsync { item in
    [item, item * 10]
}

let compacted = await items.compactMapAsync { item -> String? in
    await processItem(item)
}
```

### AsyncSequence Result Processing

```swift
let stream = AsyncStream<Result<Int, AppError>> { continuation in
    continuation.success(1)
    continuation.failure(.invalid)
    continuation.success(2)
    continuation.finish()
}

// Filter to just success values
for await value in stream.successes() {
    print(value)  // 1, 2
}

// Transform, tap, and chain
for await result in stream
    .tap { value in logger.info("got \(value)") }
    .tapError { error in logger.error("\(error)") }
    .mapAsync { value in await enrich(value) }
    .flatMap { value in validate(value) }
{
    // ...
}
```

### Ordered Concurrent Mapping

Map an `AsyncSequence` through an async transform while preserving source order. Transforms run sequentially by default (`concurrency: 1`); raise `concurrency` to run them in parallel, bounding wall-clock time by the slowest element rather than the sum of all transforms while emission still follows source arrival order. In-flight transforms are cancelled cooperatively if the consumer stops iterating early:

```swift
for await image in references.mapAsyncKeepOrder(concurrency: 8, { ref in
    await downloader.fetch(ref)
}) {
    render(image)
}
```

A `Result`-aware overload transforms only the success side and passes failures through unchanged:

```swift
for await result in events.mapAsyncKeepOrder({ event in
    await enrich(event)
}) {
    handle(result)  // Result<EnrichedEvent, MyError>
}
```

When the transform itself can fail, use `flatMapAsyncKeepOrder` — the transform returns a `Result`, source failures pass through, and transform failures replace the success they came from:

```swift
for await result in events.flatMapAsyncKeepOrder({ event in
    await validateAndEnrich(event)  // Result<EnrichedEvent, MyError>
}) {
    handle(result)
}
```

### AsyncStream Result Factories

```swift
// Create single-element Result streams
let success: AsyncStream<Result<Int, MyError>> = .success(42)
let failure: AsyncStream<Result<Int, MyError>> = .failure(.someError)

// Continuation helpers
let stream = AsyncStream<Result<Int, MyError>> { continuation in
    continuation.success(1)
    continuation.failure(.someError)
    continuation.finishWithSuccess(2)
    // or end with an error: continuation.finishWithFailure(.fatal)
}
```

### Optional Match

```swift
let optional: String? = "hello"

let message = optional.match(
    { "got: \($0)" },
    "nothing"
)
// "got: hello"
```

### Optional Async Mapping

```swift
let optional: Int? = 42

let mapped = await optional.mapAsync { value in
    await fetchDetails(for: value)
}

let flatMapped = await optional.flatMapAsync { value -> String? in
    value > 0 ? "id-\(value)" : nil
}
```

### Optional Recovery: orElse, getOrElse

Same distinction as the `Result` variants, minus the error value (`Optional` has none):

| Method       | Returns       | Fallback accepts |
| ------------ | ------------- | ---------------- |
| `orElse`     | `Wrapped?`    | `Wrapped?` — chains through nils |
| `getOrElse`  | `Wrapped`     | `Wrapped` — unwraps with a default |

```swift
// orElse — first .some wins; chain through multiple sources
let name = cachedName
    .orElse(storedName)
    .orElse(fetchName())

// getOrElse — unwrap with a default (equivalent to ??)
let count = parsed.getOrElse(0)

// Async variants
let name = await cachedName.orElseAsync(await fetchName())
let user = await cachedUser.getOrElseAsync(await loadGuestUser())
```
