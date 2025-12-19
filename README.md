# fp-swift

_This is not a full fledged package for functional programming in Swift. This will have to wait until Higher Kinded Types are part of the language. However this will make it easier to write functional code using built-in Swift Result and Optional types._

A lightweight functional programming toolkit for Swift, providing composable utilities for working with `Result`, `Optional`, and `Array` types in both synchronous and asynchronous contexts. 

## Requirements

- Swift 6.2+

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/velocityzen/fp-swift.git", from: "0.2.0")
]
```

## Features

### Pipe Operators

Forward pipe operators for function composition:

```swift
// Basic pipe: pass value to function
let result = 5 |> double |> toString  // "10"

// Pipe into second argument
let result = value |>> (function, firstArg)

// Pipe into third argument  
let result = value |>>> (function, firstArg, secondArg)

// Flow operator: create function from another function
let transform = |> double  // (Int) -> Int
```

### Result Extensions

#### Async Map Operations

```swift
let result: Result<Int, Error> = .success(42)

// Transform success value asynchronously
let mapped = await result.mapAsync { value in
    await fetchData(for: value)
}

// FlatMap for chaining Result-returning async operations
let chained = await result.flatMapAsync { value in
    await validateAndTransform(value)  // Returns Result<T, Error>
}

// Create Result from async throwing operation
let result = await Result.fromAsync {
    try await networkCall()
}
```

#### Tap for Side Effects

Perform side effects while keeping the Result chain flowing:

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

Tap variants:
- `.tap()` - Sync side effect on success
- `.tapAsync()` - Async side effect on success
- `.tapError()` - Sync side effect on failure
- `.tapErrorAsync()` - Async side effect on failure
- Throwing variants convert `Failure` type to `Error`

#### From Optional

Convert optionals to Results:

```swift
// With static error
let result = Result<User, AppError>.fromOptional(user, error: .notFound)

// With lazy error (only evaluated if nil)
let result = Result<User, AppError>.fromOptional(user) {
    .notFound(id: userId)
}
```

### Optional Extensions

#### Async Map

```swift
let optional: Int? = 42

let result = await optional.mapAsync { value in
    await fetchDetails(for: value)
}
// Returns nil if optional was nil, otherwise the transformed value
```

#### OrElse

```swift
let optional: Int? = nil
let fallback = optional.orElse(99)  // Returns 99 when nil, nil when has value
```

### Array Extensions

#### Traverse

Apply a Result-returning transform to each element, short-circuiting on first failure:

```swift
let userIds = [1, 2, 3]

// Sync traverse
let result = userIds.traverse { id -> Result<User, AppError> in
    fetchUser(id: id)
}
// Returns .success([User]) or .failure on first error

// Async traverse
let result = await userIds.traverseAsync { id in
    await fetchUserAsync(id: id)
}
```

#### CompactMap Async

Asynchronous version of `compactMap`:

```swift
let items = [1, 2, 3, 4, 5]

let result = await items.compactMapAsync { item -> String? in
    await processItem(item)  // Returns nil for items to filter out
}

// Throwing variant
let result = try await items.compactMapAsync { item throws -> String? in
    try await validateAndProcess(item)
}
```

## Usage Examples

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

## License

MIT
