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

Then import it:

```swift
import FP
```

## Result Extensions API

### Map & FlatMap
```swift
// Non-throwing
func mapAsync<T>(_ transform: (Success) async -> T) async -> Result<T, Failure>
func flatMapAsync<T>(_ transform: (Success) async -> Result<T, Failure>) async -> Result<T, Failure>

// Throwing (requires Failure == Error)
func mapAsync<T>(_ transform: (Success) async throws -> T) async -> Result<T, Error>
```

### From Async
```swift
// Throwing (requires Failure == Error)
static func fromAsync(_ operation: () async throws -> Success) async -> Result<Success, Error>
```

### From Task
```swift
// Throwing Task (requires Failure == Error)
static func fromTask(_ task: Task<Success, Error>) async -> Result<Success, Error>
static func fromTask(_ task: () -> Task<Success, Error>) async -> Result<Success, Error>

// Non-throwing Task (requires Failure == Never)
static func fromTask(_ task: Task<Success, Never>) async -> Result<Success, Never>
static func fromTask(_ task: () -> Task<Success, Never>) async -> Result<Success, Never>

// Task returning Result (requires Failure == Error)
static func fromTask<S>(_ task: Task<Result<S, Error>, Never>) async -> Result<S, Error>
static func fromTask<S>(_ task: () -> Task<Result<S, Error>, Never>) async -> Result<S, Error>
```

### From Optional
```swift
static func fromOptional(_ optional: Success?, error: Failure) -> Result<Success, Failure>
static func fromOptional(_ optional: Success?, onError: () -> Failure) -> Result<Success, Failure>
static func fromOptional(error: Failure) -> (Success?) -> Result<Success, Failure>
static func fromOptional(onError: () -> Failure) -> (Success?) -> Result<Success, Failure>
```

### Tap (Side Effects)
```swift
// Non-throwing
func tap(_ action: (Success) -> Void) -> Result<Success, Failure>
func tap<T>(_ action: (Success) -> T) -> Result<Success, Failure>
func tap<E>(_ action: (Success) -> Result<Void, E>) -> Result<Success, E>
func tap<T, E>(_ action: (Success) -> Result<T, E>) -> Result<Success, E>

// Throwing
func tap(_ action: (Success) throws -> Void) -> Result<Success, Error>
func tap<T>(_ action: (Success) throws -> T) -> Result<Success, Error>

// Async non-throwing
func tapAsync(_ action: (Success) async -> Void) async -> Result<Success, Failure>
func tapAsync<T>(_ action: (Success) async -> T) async -> Result<Success, Failure>
func tapAsync<E>(_ action: (Success) async -> Result<Void, E>) async -> Result<Success, E>
func tapAsync<T, E>(_ action: (Success) async -> Result<T, E>) async -> Result<Success, E>

// Async throwing
func tapAsync(_ action: (Success) async throws -> Void) async -> Result<Success, Error>
func tapAsync<T>(_ action: (Success) async throws -> T) async -> Result<Success, Error>
```

### TapError (Side Effects on Failure)
```swift
// Non-throwing
func tapError(_ action: (Failure) -> Void) -> Result<Success, Failure>
func tapError<T>(_ action: (Failure) -> T) -> Result<Success, Failure>
func tapError<T, E>(_ action: (Failure) -> Result<T, E>) -> Result<Success, E>

// Throwing
func tapError(_ action: (Failure) throws -> Void) -> Result<Success, Error>
func tapError<T>(_ action: (Failure) throws -> T) -> Result<Success, Error>

// Async non-throwing
func tapErrorAsync(_ action: (Failure) async -> Void) async -> Result<Success, Failure>
func tapErrorAsync<T>(_ action: (Failure) async -> T) async -> Result<Success, Failure>
func tapErrorAsync<T, E>(_ action: (Failure) async -> Result<T, E>) async -> Result<Success, E>

// Async throwing
func tapErrorAsync(_ action: (Failure) async throws -> Void) async -> Result<Success, Error>
func tapErrorAsync<T>(_ action: (Failure) async throws -> T) async -> Result<Success, Error>
```

## Flatten Functions API

Combine multiple Results into a single Result containing a tuple of all success values. If any Result fails, returns the first failure.

### Sync Flatten
```swift
// Supports 2-10 arguments
func flatten<A, B, E: Error>(_ a: Result<A, E>, _ b: Result<B, E>) -> Result<(A, B), E>
func flatten<A, B, C, E: Error>(_ a: Result<A, E>, _ b: Result<B, E>, _ c: Result<C, E>) -> Result<(A, B, C), E>
// ... up to 10 arguments
```

### Async Flatten (Parallel Execution)
```swift
// Supports 2-10 arguments, runs all operations in parallel
func flattenAsync<A: Sendable, B: Sendable, E: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<B, E>
) async -> Result<(A, B), E>
// ... up to 10 arguments
```

## Optional Extensions API

```swift
// Async (supports both throwing and non-throwing)
func mapAsync<T>(_ transform: (Wrapped) async -> T) async -> T?
func mapAsync<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T?

func orElse<T>(_ defaultValue: T) -> T?
```

## AsyncStream.Continuation Extensions API

Extensions for `AsyncStream.Continuation` when the element type is `Result<Success, Failure>`:

```swift
// Yield success/failure values
func success<Success, Failure>(_ value: Success) -> YieldResult
func failure<Success, Failure>(_ error: Failure) -> YieldResult

// Yield and finish the stream
func finishWithSuccess<Success, Failure>(_ value: Success)
func finishWithFailure<Success, Failure>(_ error: Failure)
```

## Array Extensions API

### Traverse
```swift
func traverse<Success>(_ transform: (Element) -> Success) -> Result<[Success], Never>
func traverse<Success, Failure>(_ transform: (Element) -> Result<Success, Failure>) -> Result<[Success], Failure>
func traverseAsync<Success>(_ transform: (Element) async -> Success) async -> Result<[Success], Never>
func traverseAsync<Success, Failure>(_ transform: (Element) async -> Result<Success, Failure>) async -> Result<[Success], Failure>
```

### CompactMap Async
```swift
// Async (supports both throwing and non-throwing)
func compactMapAsync<T>(_ transform: (Element) async -> T?) async -> [T]
func compactMapAsync<T>(_ transform: (Element) async throws -> T?) async rethrows -> [T]
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

// Create Result from Task
let task = Task { try await networkCall() }
let result = await Result.fromTask(task)

// Or with closure syntax
let result = await Result.fromTask {
    Task { try await networkCall() }
}

// Also works with Tasks returning Results
let task = Task { await someResultOperation() }
let result: Result<Value, Error> = await Result.fromTask(task)
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

### AsyncStream.Continuation Extensions

Convenience methods for yielding `Result` values in async streams:

```swift
let stream = AsyncStream<Result<Int, MyError>> { continuation in
    continuation.success(1)
    continuation.success(2)
    continuation.failure(.someError)
    continuation.finish()
}

// Or finish with a final value
let stream = AsyncStream<Result<String, MyError>> { continuation in
    continuation.success("processing...")
    continuation.finishWithSuccess("done")  // Yields and finishes
}

// Finish with error
let stream = AsyncStream<Result<Data, NetworkError>> { continuation in
    continuation.finishWithFailure(.connectionLost)  // Yields error and finishes
}
```

### Flatten Results

Combine multiple Results into a single Result with a tuple of values:

```swift
let userResult: Result<User, AppError> = fetchUser(id: 1)
let profileResult: Result<Profile, AppError> = fetchProfile(id: 1)
let settingsResult: Result<Settings, AppError> = fetchSettings(id: 1)

// Sync flatten - combine already-computed Results
let combined = flatten(userResult, profileResult, settingsResult)
// Result<(User, Profile, Settings), AppError>

// Use map to create named tuple for easier access
let namedResult = flatten(userResult, profileResult)
    .map { (user: $0, profile: $1) }
// Result<(user: User, profile: Profile), AppError>

if case .success(let data) = namedResult {
    print(data.user.name)
    print(data.profile.bio)
}
```

#### Async Flatten with Parallel Execution

Run multiple async operations in parallel and combine their results:

```swift
func loadDashboard(userId: Int) async -> Result<Dashboard, AppError> {
    // All three operations run in parallel
    let result = await flattenAsync(
        await fetchUser(id: userId),
        await fetchNotifications(for: userId),
        await fetchRecommendations(for: userId)
    )
    // Result<(User, [Notification], [Recommendation]), AppError>
    
    return result.map { user, notifications, recommendations in
        Dashboard(user: user, notifications: notifications, recommendations: recommendations)
    }
}
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
