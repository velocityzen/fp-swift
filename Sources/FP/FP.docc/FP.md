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
        .let { user, item in item.price * user.discountRate }
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

- Use `alt` for a blind fallback chain (cache, default branch) — mirrors fp-ts `Either.alt`.
- Use `orElse` when recovery depends on the error, or when you want to normalize/wrap the failure type — mirrors fp-ts `Either.orElse`.
- Use `getOrElse` when you just need the plain value and can compute one from the error — mirrors fp-ts `Either.getOrElse`.

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

### Parallel Execution with Flatten

```swift
// All three operations run in parallel
let result = await flattenAsync(
    await fetchUser(id: userId),
    await fetchNotifications(for: userId),
    await fetchRecommendations(for: userId)
)
// Result<(User, [Notification], [Recommendation]), AppError>
```

### Batch Processing with Traverse

```swift
func processOrders(_ orderIds: [Int]) async -> Result<[Order], OrderError> {
    await orderIds.traverseAsync { id in
        await fetchAndValidateOrder(id: id)
    }
}
// Fails fast on first error, returns all orders on success
```

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

Map an `AsyncSequence` through an async transform in parallel while preserving source order — wall-clock time is bounded by the slowest element rather than the sum of all transforms, but emission still follows source arrival order:

```swift
for await image in references.mapAsyncKeepOrder({ ref in
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
