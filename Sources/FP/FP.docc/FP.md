# ``FP``

A lightweight functional programming toolkit for Swift, providing composable utilities for `Result`, `Optional`, and `Array` types.

## Overview

FP extends Swift's built-in types with functional programming patterns for both synchronous and asynchronous contexts. Chain operations on `Result`, traverse arrays with error handling, compose functions with pipe operators, and more.

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
