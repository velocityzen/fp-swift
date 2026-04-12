# ``FP``

A lightweight functional programming toolkit for Swift, providing composable utilities for `Result`, `Optional`, and `Array` types.

## Overview

FP extends Swift's built-in types with functional programming patterns for both synchronous and asynchronous contexts. Chain operations on `Result`, traverse arrays with error handling, compose functions with pipe operators, and more.

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

### Pipeline with Operators

```swift
let result = input
    |> validate
    |> transform
    |> format
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
