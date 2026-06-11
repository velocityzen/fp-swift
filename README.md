# fp-swift

[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fvelocityzen%2Ffp-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/velocityzen/fp-swift)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fvelocityzen%2Ffp-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/velocityzen/fp-swift)
[![Documentation](https://img.shields.io/badge/documentation-DocC-purple)](https://swiftpackageindex.com/velocityzen/fp-swift/documentation/fp)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

_This is not a full fledged package for functional programming in Swift. This will have to wait until Higher Kinded Types are part of the language. However this will make it easier to write functional code using built-in Swift Result and Optional types._

A lightweight functional programming toolkit for Swift, providing composable utilities for working with `Result`, `Optional`, and `Array` types in both synchronous and asynchronous contexts. 

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Features](#features)
  - [Pipe Operators](#pipe-operators)
  - [Result Extensions](#result-extensions)
  - [Flatten Results](#flatten-results)
  - [Array Extensions](#array-extensions)
  - [AsyncSequence Result Processing](#asyncsequence-result-processing)
  - [Ordered Concurrent Mapping](#ordered-concurrent-mapping)
  - [AsyncStream Extensions](#asyncstream-extensions)
  - [Optional Extensions](#optional-extensions)
- [API Reference](#result-extensions-api)
  - [Result Extensions API](#result-extensions-api)
  - [Flatten Functions API](#flatten-functions-api)
  - [Array Extensions API](#array-extensions-api)
  - [AsyncSequence Extensions API](#asyncsequence-extensions-api)
  - [AsyncStream Extensions API](#asyncstream-extensions-api)
  - [Optional Extensions API](#optional-extensions-api)

## Requirements

- Swift 6.2+
- macOS 10.15+ / iOS 13+ / tvOS 13+ / watchOS 6+ / visionOS 1+ / Linux
- The `mapAsyncKeepOrder` family requires macOS 15+ / iOS 18+ / tvOS 18+ / watchOS 11+ / visionOS 2+ (no version gate on Linux)

Every platform is exercised in CI: macOS 15 and 26, Ubuntu Linux, and the iOS, tvOS, watchOS, and visionOS simulators.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/velocityzen/fp-swift.git", from: "3.0.0")
]
```

Then import it:

```swift
import FP
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

Pipe operators bind looser than arithmetic, ranges, casts, and `??`, but tighter than comparisons, logical operators, and assignment — the same placement as Elixir's `|>` and F#'s pipe family. The full expression on the left flows into the function on the right:

```swift
1 + 2 |> double          // double(3) = 6 — not 1 + double(2)
x |> transform == 6      // (x |> transform) == 6
flag && x |> isValid     // flag && (x |> isValid)
a ?? b |> process        // (a ?? b) |> process
```

All pipe operators (including the prefix flow operator) have async overloads. Sync and async functions can be freely mixed in a chain — the chain becomes `async` as soon as any step is async:

```swift
// Mixed sync/async chain — only one `await` needed at the front
let summary = await userId
    |> normalizeId         // sync (Int) -> Int
    |> fetchUser           // async (Int) async -> User
    |> renderSummary       // sync (User) -> String

// Two- and three-arg variants
let profile = await userId |>> (fetchProfile, session)
let html    = await body  |>>> (renderPage, title, theme)

// Async point-free
let load: (Int) async -> User = |> fetchUserAsync
```

Adding the async overloads does not affect existing sync usage: in a sync context (no `await`) only the sync overload can match, and in an async context Swift still prefers the sync overload when the closure is sync.

### Result Extensions

#### Do Notation for Composing Results

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

// Async variant with mixed sync/async steps
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

#### Chaining Async Operations

```swift
func processUser(id: Int) async -> Result<ProcessedUser, Error> {
    await Result.fromAsync { try await api.fetchUser(id: id) }
        .tapAsync { user in await analytics.track(.userFetched(user)) }
        .mapAsync { user in await enrichUserData(user) }
        .flatMapAsync { user in await validateUser(user) }
        .tapError { error in logger.error("Failed: \(error)") }
}
```

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

#### Map to Constant Value

Replace the success value with a constant or discard it entirely:

```swift
let result: Result<Int, AppError> = .success(42)

// Map to a specific constant
let mapped = result.as("done")  // .success("done")

// Map to Void (discard the success value)
let unit = result.asUnit()  // .success(())

// Useful in chains where you only care about success/failure
fetchUser(id: 1)
    .tap { user in saveToCache(user) }
    .asUnit()  // Result<Void, AppError>
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

Throwing variants convert the `Failure` type to `Error`; if the action throws, the thrown error becomes the failure (in the `tapError` case it replaces the original failure). Result-returning variants propagate the action's failure the same way.

#### Alt — Recover with an Alternative

If `self` is a success, keep it; otherwise return the lazily-evaluated alternative. The alternative may itself succeed (recovery) or fail (in which case its failure replaces the original):

```swift
fetchUser(id: 1)
    .alt { fetchUserFromCache(id: 1) }
    .alt { .success(.guest) }

// Async variant
await fetchUser(id: 1)
    .altAsync { await fetchUserFromCache(id: 1) }
```

#### GetOrElse — Unwrap with a Fallback

Returns the success value, or computes/returns a fallback when the result is a failure. Unlike `alt`, this returns the unwrapped `Success` rather than another `Result`:

```swift
// Closure-based — receives the error
let count = parse(input).getOrElse { _ in 0 }

// Constant default (lazily evaluated)
let count = parse(input).getOrElse(0)

// Async variant — closure receives the error
let user = await fetchUser(id: 1).getOrElseAsync { _ in
    await loadGuestUser()
}

// Async variant — lazily-evaluated async default
let user = await fetchUser(id: 1).getOrElseAsync(await loadGuestUser())
```

#### GetOrExit — Unwrap or Terminate the Process

Designed for CLI entry points. Returns the success value, or prints the failure to stderr and calls `Foundation.exit`:

```swift
// Default: prints "Error: <error>\n" and exits with status 1
let config = loadConfig().getOrExit()

// Customize the prefix and exit code
let port = parsePort(args).getOrExit(prefix: "fatal: ", exitCode: 2)

// Provide a fully custom message — include any trailing newline yourself
let user = fetchUser(id: 1).getOrExit { error in
    "could not load user: \(error)\n"
}
```

#### OrExit — Terminate on Failure, Discard Success

Same termination behavior as `getOrExit`, but discards the success value. Useful at the end of a pipeline that has already consumed the success:

```swift
runCommand(args)
    .tap { output in print(output) }
    .orExit()

// Custom message
runCommand(args).orExit { error in
    "command failed: \(error)\n"
}
```

#### Match

Branch on a Result without switching manually:

```swift
let message = result.match(
    { "value: \($0)" },
    { "error: \($0)" }
)

let fallback = result.match("ok", "error")

let mixed = result.match(
    { "value: \($0)" },
    "error"
)

let asyncMessage = await result.matchAsync(
    { value in
        await Task.yield()
        return "value: \(value)"
    },
    { error in
        await Task.yield()
        return "error: \(error)"
    }
)

let asyncMixed = await result.matchAsync(
    "ok",
    { error in
        await Task.yield()
        return "error: \(error)"
    }
)

// Use match for side effects without capturing the result
result.match(
    { value in print("Success: \(value)") },
    { error in print("Error: \(error)") }
)
```

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

#### Is Success / Is Failure

Boolean checks for simple conditionals:

```swift
let result: Result<User, AppError> = fetchUser(id: 1)

if result.isSuccess {
    print("User fetched successfully")
}

// Or in ternary expressions
let message = result.isSuccess ? "ok" : "error"

if result.isFailure {
    scheduleRetry()
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

// Async traverse — sequential: each element awaits the previous one,
// and elements after a failure never run
let result = await userIds.traverseAsync { id in
    await fetchUserAsync(id: id)
}

// Parallel traverse — up to `concurrency` transforms in flight at once.
// Results keep source order; fails with the lowest-index failure and
// cancels in-flight transforms cooperatively.
let result = await userIds.traverseAsync(concurrency: 4) { id in
    await fetchUserAsync(id: id)
}
```

Both `traverseAsync(concurrency:)` and `mapAsyncKeepOrder` run transforms in parallel with ordered output. Use `traverseAsync` for an all-or-nothing pass over a finite array — one `Result` at the end, the lowest-index failure wins, a failure cancels the rest. Use `mapAsyncKeepOrder` when you want each result as soon as order allows, have an endless source, or want failures kept in position in the stream.

#### Async Mapping

Asynchronous versions of `map`, `flatMap`, and `compactMap`:

```swift
let items = [1, 2, 3, 4, 5]

let mapped = await items.mapAsync { item in
    "v\(item)"
}

let flattened = await items.flatMapAsync { item in
    [item, item * 10]
}

let compacted = await items.compactMapAsync { item -> String? in
    await processItem(item)  // Returns nil for items to filter out
}

enum ParseError: Error {
    case invalid
}

let resultFlattened = await items.flatMapAsync { item -> Result<[Int], ParseError> in
    .success([item, item + 100])
}

let resultCompacted = await items.compactMapAsync { item -> Result<String?, ParseError> in
    .success(item.isMultiple(of: 2) ? "even-\(item)" : nil)
}
```

### AsyncSequence Result Processing

Process streams of Results with familiar functional operations:

```swift
let stream = AsyncStream<Result<Int, AppError>> { continuation in
    continuation.success(1)
    continuation.success(2)
    continuation.failure(.invalid)
    continuation.success(3)
    continuation.finish()
}

// Filter to just success values
for await value in stream.successes() {
    print(value)  // 1, 2, 3
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

Map elements through an async transform while preserving source order. By default transforms run **one at a time** — pass `concurrency` greater than 1 to opt into parallelism, bounding wall-clock time by the slowest element rather than the sum of all transforms while emission still follows source arrival order. If the consumer stops iterating early, no further elements are read from the source and in-flight transforms are cancelled cooperatively. Useful when an upstream provider streams items that should be processed concurrently but consumed in order (e.g. SSE image references that need to be fetched in parallel and rendered in order):

```swift
for await image in references.mapAsyncKeepOrder(concurrency: 8, { ref in
    await downloader.fetch(ref)
}) {
    render(image)
}
```

For an all-or-nothing parallel pass over a finite array, see `traverseAsync(concurrency:)` in [Traverse](#traverse) instead.

When the source is a stream of `Result`, an overload transforms only the success values and passes failures through unchanged — preserving order across both:

```swift
for await result in events.mapAsyncKeepOrder({ event in
    await enrich(event)
}) {
    handle(result)  // Result<EnrichedEvent, MyError>
}
```

### AsyncStream Extensions

Create single-element Result streams or use convenience methods on continuations:

```swift
// Static factories — single-element streams
let success: AsyncStream<Result<Int, MyError>> = .success(42)
let failure: AsyncStream<Result<Int, MyError>> = .failure(.someError)

// Continuation helpers
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

### Optional Extensions

#### Match

```swift
let optional: String? = "hello"

let message = optional.match(
    { "got: \($0)" },
    "nothing"
)
// "got: hello"

let missing: String? = nil
missing.match(
    { value in print(value) },
    ()
)
// Does nothing
```

#### Async Mapping

```swift
let optional: Int? = 42

let mapped = await optional.mapAsync { value in
    await fetchDetails(for: value)
}
// Returns nil if optional was nil, otherwise the transformed value

let flatMapped = await optional.flatMapAsync { value -> String? in
    value > 0 ? "id-\(value)" : nil
}
```

#### OrElse / GetOrElse

```swift
let optional: Int? = nil
let fallback = optional.orElse(99)  // 99 — first .some wins, so nil falls through
let kept = Optional(5).orElse(99)   // 5 — keeps the wrapped value

// getOrElse unwraps with a default (equivalent to ??)
let count = optional.getOrElse(0)   // 0
```

## Result Extensions API

### Do Notation

Monadic do-notation for composing multiple Result operations with an accumulating context:

```swift
// ResultDo starts the chain, bind adds Result values, let adds pure values
let result = ResultDo<MyError>()
    .bind { getUser() }                              // Result<User, MyError>
    .bind { user in getProfile(user) }               // Result<(User, Profile), MyError>
    .let { _, profile in profile.name }              // Result<(User, Profile, String), MyError>
    .map { user, _, name in "\(user.id): \(name)" }  // Result<String, MyError>

// Short-circuits on the first failure
let result = ResultDo<MyError>()
    .bind { getUser() }                // .failure(.notFound) → stops here
    .bind { user in getProfile(user) } // never called
    .map { user, profile in profile }  // never called
// result == .failure(.notFound)
```

**API:**
```swift
// Start the chain
ResultDo<Failure>()

// Bind: add a Result value, accumulates into a growing tuple
func bind<A>(_ f: () -> Result<A, Failure>) -> Result<A, Failure>
func bind<B>(_ f: (A) -> Result<B, Failure>) -> Result<(A, B), Failure>
func bind<C>(_ f: (A, B) -> Result<C, Failure>) -> Result<(A, B, C), Failure>
// ... up to 10 accumulated values

// Let: add a pure (non-Result) value
func `let`<A>(_ f: () -> A) -> Result<A, Failure>
func `let`<B>(_ f: (A) -> B) -> Result<(A, B), Failure>
func `let`<C>(_ f: (A, B) -> C) -> Result<(A, B, C), Failure>
// ... up to 10 accumulated values

// Async variants: bindAsync / letAsync
func bindAsync<A>(_ f: () async -> Result<A, Failure>) async -> Result<A, Failure>
func bindAsync<B>(_ f: (A) async -> Result<B, Failure>) async -> Result<(A, B), Failure>
// ... up to 10 accumulated values

func letAsync<A>(_ f: () async -> A) async -> Result<A, Failure>
func letAsync<B>(_ f: (A) async -> B) async -> Result<(A, B), Failure>
// ... up to 10 accumulated values
```

Sync and async can be freely mixed in the same chain:

```swift
let result = await ResultDo<MyError>()
    .bind { getCachedUser() }                          // sync
    .bindAsync { user in await fetchProfile(user) }    // async
    .let { user, profile in profile.name }             // sync
    .mapAsync { user, profile, name in                 // async
        await formatDisplay(user, name)
    }
```

### Map & FlatMap
```swift
// Non-throwing
func mapAsync<T>(_ transform: (Success) async -> T) async -> Result<T, Failure>
func mapErrorAsync<E: Error>(_ transform: (Failure) async -> E) async -> Result<Success, E>
func flatMapAsync<T>(_ transform: (Success) async -> Result<T, Failure>) async -> Result<T, Failure>

// Throwing (requires Failure == Error)
func mapAsync<T>(_ transform: (Success) async throws -> T) async -> Result<T, Error>

// Map to constant value
func `as`<T>(_ value: T) -> Result<T, Failure>
func asUnit() -> Result<Void, Failure>
```

### Alt
```swift
// Lazily provides an alternative on failure
func alt(_ alternative: () -> Result<Success, Failure>) -> Result<Success, Failure>
func altAsync(_ alternative: () async -> Result<Success, Failure>) async -> Result<Success, Failure>
```

### GetOrElse
```swift
// Unwrap or fall back
func getOrElse(_ onFailure: (Failure) -> Success) -> Success
func getOrElse(_ defaultValue: @autoclosure () -> Success) -> Success
func getOrElseAsync(_ onFailure: (Failure) async -> Success) async -> Success
func getOrElseAsync(_ defaultValue: @autoclosure @escaping () async -> Success) async -> Success
```

### GetOrExit / OrExit
```swift
// Unwrap or print to stderr and call Foundation.exit
func getOrExit(prefix: String = "Error: ", exitCode: Int32 = 1) -> Success
func getOrExit(exitCode: Int32 = 1, message: (Failure) -> String) -> Success

// Discard success; print to stderr and exit on failure
func orExit(prefix: String = "Error: ", exitCode: Int32 = 1)
func orExit(exitCode: Int32 = 1, message: (Failure) -> String)
```

### Match

All match variants are marked `@discardableResult`, so you can use them both for transforming values and for side effects without assigning the result.

```swift
@discardableResult func match<T>(_ onSuccess: (Success) -> T, _ onFailure: (Failure) -> T) -> T
@discardableResult func match<T>(_ onSuccess: (Success) -> T, _ failure: @autoclosure () -> T) -> T
@discardableResult func match<T>(_ success: @autoclosure () -> T, _ onFailure: (Failure) -> T) -> T
@discardableResult func match<T>(_ success: @autoclosure () -> T, _ failure: @autoclosure () -> T) -> T
@discardableResult func matchAsync<T>(_ onSuccess: (Success) async -> T, _ onFailure: (Failure) async -> T) async -> T
@discardableResult func matchAsync<T>(_ onSuccess: (Success) async -> T, _ failure: @autoclosure () -> T) async -> T
@discardableResult func matchAsync<T>(_ success: @autoclosure () -> T, _ onFailure: (Failure) async -> T) async -> T
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

### Is Success / Is Failure
```swift
var isSuccess: Bool  // true for success, false for failure
var isFailure: Bool  // true for failure, false for success
```

### Tap (Side Effects)

Throwing variants convert `Failure` to `Error`; a thrown error becomes the failure. Result-returning variants keep the success value but propagate the action's failure (the action's `Failure` type must match the Result's).

```swift
// Non-throwing
func tap(_ action: (Success) -> Void) -> Result<Success, Failure>
func tap<T>(_ action: (Success) -> T) -> Result<Success, Failure>

// Result-returning
func tap(_ action: (Success) -> Result<Void, Failure>) -> Result<Success, Failure>
func tap<T>(_ action: (Success) -> Result<T, Failure>) -> Result<Success, Failure>

// Throwing
func tap(_ action: (Success) throws -> Void) -> Result<Success, Error>
func tap<T>(_ action: (Success) throws -> T) -> Result<Success, Error>

// Async non-throwing
func tapAsync(_ action: (Success) async -> Void) async -> Result<Success, Failure>
func tapAsync<T>(_ action: (Success) async -> T) async -> Result<Success, Failure>

// Async Result-returning
func tapAsync(_ action: (Success) async -> Result<Void, Failure>) async -> Result<Success, Failure>
func tapAsync<T>(_ action: (Success) async -> Result<T, Failure>) async -> Result<Success, Failure>

// Async throwing
func tapAsync(_ action: (Success) async throws -> Void) async -> Result<Success, Error>
func tapAsync<T>(_ action: (Success) async throws -> T) async -> Result<Success, Error>
```

### TapError (Side Effects on Failure)

In the throwing variants, a thrown error replaces the original failure. In the Result-returning variants, the action's failure replaces the original; its success is discarded.

```swift
// Non-throwing
func tapError(_ action: (Failure) -> Void) -> Result<Success, Failure>
func tapError<T>(_ action: (Failure) -> T) -> Result<Success, Failure>

// Result-returning
func tapError<T>(_ action: (Failure) -> Result<T, Failure>) -> Result<Success, Failure>

// Throwing
func tapError(_ action: (Failure) throws -> Void) -> Result<Success, Error>
func tapError<T>(_ action: (Failure) throws -> T) -> Result<Success, Error>

// Async non-throwing
func tapErrorAsync(_ action: (Failure) async -> Void) async -> Result<Success, Failure>
func tapErrorAsync<T>(_ action: (Failure) async -> T) async -> Result<Success, Failure>

// Async Result-returning
func tapErrorAsync<T>(_ action: (Failure) async -> Result<T, Failure>) async -> Result<Success, Failure>

// Async throwing
func tapErrorAsync(_ action: (Failure) async throws -> Void) async -> Result<Success, Error>
func tapErrorAsync<T>(_ action: (Failure) async throws -> T) async -> Result<Success, Error>
```

### Finally
```swift
// Runs regardless of success or failure, returns self unchanged
func finally(_ action: () -> Void) -> Result<Success, Failure>
func finallyAsync(_ action: () async -> Void) async -> Result<Success, Failure>
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

## Array Extensions API

### Traverse
```swift
func traverse<Success>(_ transform: (Element) -> Success) -> Result<[Success], Never>
func traverse<Success, Failure>(_ transform: (Element) -> Result<Success, Failure>) -> Result<[Success], Failure>

// Sequential — each element awaits the previous one
func traverseAsync<Success>(_ transform: (Element) async -> Success) async -> Result<[Success], Never>
func traverseAsync<Success, Failure>(_ transform: (Element) async -> Result<Success, Failure>) async -> Result<[Success], Failure>

// Parallel — up to `concurrency` in flight, results in source order,
// lowest-index failure wins, in-flight transforms cancelled on failure
func traverseAsync<Success: Sendable>(
    concurrency: Int,
    _ transform: @Sendable @escaping (Element) async -> Success
) async -> Result<[Success], Never> where Element: Sendable
func traverseAsync<Success: Sendable, Failure: Error>(
    concurrency: Int,
    _ transform: @Sendable @escaping (Element) async -> Result<Success, Failure>
) async -> Result<[Success], Failure> where Element: Sendable
```

### Separate / Successes / Failures
```swift
// Split an array of Results into both sides
func separate<Success, Failure>() -> (successes: [Success], failures: [Failure])
    where Element == Result<Success, Failure>

// Just one side
func successes<Success, Failure>() -> [Success] where Element == Result<Success, Failure>
func failures<Success, Failure>() -> [Failure] where Element == Result<Success, Failure>
```

### Compact / Sequence
```swift
// Drop nil elements
func compact<T>() -> [T] where Element == T?

// All-or-nothing: nil if any element is nil
func sequence<T>() -> [T]? where Element == T?
```

### Async Mapping
```swift
// mapAsync — for Result-returning transforms, use traverseAsync
func mapAsync<T>(_ transform: (Element) async -> T) async -> [T]

// flatMapAsync
func flatMapAsync<S: Sequence>(
    _ transform: (Element) async -> S
) async -> [S.Element]
func flatMapAsync<S: Sequence, Failure: Error>(
    _ transform: (Element) async -> Result<S, Failure>
) async -> Result<[S.Element], Failure>

// compactMapAsync
func compactMapAsync<T>(_ transform: (Element) async -> T?) async -> [T]
func compactMapAsync<T, Failure: Error>(
    _ transform: (Element) async -> Result<T?, Failure>
) async -> Result<[T], Failure>
```

## AsyncSequence Extensions API

Extensions for any `AsyncSequence` where `Element == Result<Success, Failure>`:

### Filter
```swift
func successes() -> AsyncCompactMapSequence  // unwraps success values
func failures() -> AsyncCompactMapSequence   // unwraps failure errors
```

### Map & FlatMap
```swift
// Sync
func map<T>(_ transform: (Success) -> T) -> AsyncMapSequence<Self, Result<T, Failure>>
func mapError<E>(_ transform: (Failure) -> E) -> AsyncMapSequence<Self, Result<Success, E>>
func flatMap<T>(_ transform: (Success) -> Result<T, Failure>) -> AsyncMapSequence<Self, Result<T, Failure>>

// Async
func mapAsync<T>(_ transform: (Success) async -> T) -> AsyncMapSequence<Self, Result<T, Failure>>
func mapErrorAsync<E>(_ transform: (Failure) async -> E) -> AsyncMapSequence<Self, Result<Success, E>>
func flatMapAsync<T>(_ transform: (Success) async -> Result<T, Failure>) -> AsyncMapSequence<Self, Result<T, Failure>>
```

### Tap
```swift
// Sync
func tap(_ action: (Success) -> Void) -> AsyncMapSequence<Self, Result<Success, Failure>>
func tapError(_ action: (Failure) -> Void) -> AsyncMapSequence<Self, Result<Success, Failure>>

// Async
func tapAsync(_ action: (Success) async -> Void) -> AsyncMapSequence<Self, Result<Success, Failure>>
func tapErrorAsync(_ action: (Failure) async -> Void) -> AsyncMapSequence<Self, Result<Success, Failure>>
```

### Ordered Concurrent Mapping

Element transforms run at most `concurrency` at a time — sequential by default (`concurrency: 1`), parallel when you raise it; output preserves source arrival order either way. Early termination by the consumer cancels in-flight transforms cooperatively.

```swift
// General form
func mapAsyncKeepOrder<T: Sendable>(
    concurrency: Int = 1,
    _ transform: @Sendable @escaping (Element) async -> T
) -> AsyncStream<T>
where Self: Sendable, Failure == Never, Element: Sendable

// Result overload — transforms successes, passes failures through
func mapAsyncKeepOrder<Success: Sendable, E: Error, T: Sendable>(
    concurrency: Int = 1,
    _ transform: @Sendable @escaping (Success) async -> T
) -> AsyncStream<Result<T, E>>
where Self: Sendable, Failure == Never, Element == Result<Success, E>

// Fallible transform — transform failures replace the success they came from
func flatMapAsyncKeepOrder<Success: Sendable, E: Error, T: Sendable>(
    concurrency: Int = 1,
    _ transform: @Sendable @escaping (Success) async -> Result<T, E>
) -> AsyncStream<Result<T, E>>
where Self: Sendable, Failure == Never, Element == Result<Success, E>
```

## AsyncStream Extensions API

### Static Factories
Create single-element Result streams:

```swift
static func success<Success, Failure>(_ value: Success) -> AsyncStream<Result<Success, Failure>>
static func failure<Success, Failure>(_ error: Failure) -> AsyncStream<Result<Success, Failure>>
```

### Continuation Extensions

Extensions for `AsyncStream.Continuation` when the element type is `Result<Success, Failure>`:

```swift
// Yield success/failure values
func success<Success, Failure>(_ value: Success) -> YieldResult
func failure<Success, Failure>(_ error: Failure) -> YieldResult

// Yield and finish the stream
func finishWithSuccess<Success, Failure>(_ value: Success)
func finishWithFailure<Success, Failure>(_ error: Failure)
```

## Optional Extensions API

### Match
```swift
@discardableResult func match<T>(_ onSome: (Wrapped) -> T, _ onNone: @autoclosure () -> T) -> T
@discardableResult func matchAsync<T>(_ onSome: (Wrapped) async -> T, _ onNone: @autoclosure () -> T) async -> T
```

### Async Mapping
```swift
func mapAsync<T>(_ transform: (Wrapped) async -> T) async -> T?
func flatMapAsync<T>(_ transform: (Wrapped) async -> T?) async -> T?
```

### OrElse / GetOrElse
```swift
// First .some wins; the alternative is only evaluated when nil
func orElse(_ alternative: @autoclosure () -> Wrapped?) -> Wrapped?
func orElseAsync(_ alternative: @autoclosure @escaping () async -> Wrapped?) async -> Wrapped?

// Unwrap with a default (equivalent to ??)
func getOrElse(_ defaultValue: @autoclosure () -> Wrapped) -> Wrapped
func getOrElseAsync(_ defaultValue: @autoclosure @escaping () async -> Wrapped) async -> Wrapped
```

### Finally
```swift
// Runs regardless of .some/.none, returns self unchanged
func finally(_ action: () -> Void) -> Wrapped?
func finallyAsync(_ action: () async -> Void) async -> Wrapped?
```

## License

MIT
