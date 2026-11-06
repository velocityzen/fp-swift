# ``FPRetry``

Composable, reusable retry policies for async operations that return a `Result`, modeled on [retry-ts](https://github.com/gcanti/retry-ts).

## Overview

A ``RetryPolicy`` is a function from a ``RetryStatus`` — how many retries so far, how long waited in all, the previous delay — to the delay before the next retry, or `nil` to give up. Policies are plain `Sendable` values: define one once, then reuse it with every operation that retries.

```swift
import FPRetry

// Random delays up to 200ms, 400ms, 800ms, … capped at 2s, at most 5 retries.
let apiPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
    .and(.limitRetries(5))
    .capDelay(.seconds(2))
    .jitter()

let user = await withRetry(apiPolicy, while: \.isTransient) { await fetchUser(id) }
// Result<User, APIError>: the first success, or the latest failure
```

`withRetry` only runs async operations that return a `Result`. A success is never retried; a failure is retried while `while:` accepts its error and the policy keeps returning a delay. The action can take the current ``RetryStatus`` when it needs to know where it stands.

### Choosing which failures to retry

Not every failure is worth another attempt. A timeout or a 503 may pass on the next try; a 404 or a rejected password fails the same way every time, so retrying it only adds delay. `while:` takes a function `(Failure) -> Bool` that returns `true` for the failures to retry; a failure it rejects is returned at once, without asking the policy. Without `while:`, every failure is retried.

The rule usually belongs to the error type, so every call site agrees on what is retryable. `isTransient` in the example above is a property of the example's own error type, not part of FPRetry:

```swift
enum APIError: Error, Equatable {
    case timeout
    case rateLimited
    case server(status: Int)
    case unauthorized
    case notFound

    /// Failures that may succeed if tried again.
    var isTransient: Bool {
        switch self {
            case .timeout, .rateLimited: true
            case .server(let status): status >= 500
            case .unauthorized, .notFound: false
        }
    }
}
```

`\.isTransient` is a key path used as a function: wherever Swift expects a function `(APIError) -> Bool`, the key path `\APIError.isTransient` works too (SE-0249). These two calls are the same:

```swift
await withRetry(apiPolicy, while: \.isTransient) { await fetchUser(id) }
await withRetry(apiPolicy, while: { error in error.isTransient }) { await fetchUser(id) }
```

A one-off rule fits in a closure: `while: { $0 != .unauthorized }`.

### Composing policies

``RetryPolicy/and(_:)`` retries only while both policies do and waits the longer of their delays. It is associative, with ``RetryPolicy/constantDelay(_:)`` of `.zero` as its identity, so policies form a monoid — retry-ts's `Monoid`. Modifiers reshape a policy's delays or when it gives up:

```swift
RetryPolicy.exponentialBackoff(.seconds(1))
    .capDelay(.seconds(30))
    .limitRetriesByCumulativeDelay(.seconds(120))
```

### Adding jitter

When many clients fail at the same moment — a server restarts, the network blips — the same policy has them all retry at the same moments too. Each retry arrives as one burst, and the bursts can keep the server down. ``RetryPolicy/jitter(_:)`` spreads the retries out by multiplying every delay by a random factor from a range. Add it to any policy that more than one client runs.

The range is of factors, not durations:
- `.jitter()`, the same as `.jitter(0...1)`, is *full jitter*: anywhere from no delay up to the policy's own. It spreads retries out the most.
- `.jitter(0.5...1)` is *equal jitter*: at least half the policy's delay, so a retry never comes too soon.
- `.jitter(0.8...1.2)` is within 20% either side of the policy's delay.

Add jitter last, after ``RetryPolicy/capDelay(_:)``: the cap then bounds the delay jitter draws from, so `.capDelay(.seconds(2)).jitter()` waits 2s at most. Jitter never changes how often a policy retries, and the status records the delay actually waited.

For delays a test can predict, ``RetryPolicy/jitter(_:using:)`` draws the factors from a seeded random number generator of your own — the standard library has none.

### Writing your own policy

A policy is just a function from ``RetryStatus`` to `Duration?`: return a delay to retry after it, or `nil` to give up. Wrap that function in ``RetryPolicy/init(_:)`` and it composes with the built-ins like any other policy.

A one-off policy can be written inline. This one retries the first failure at once, and waits a second before every retry after it — forever, so give it a limit:

```swift
let quickThenSlow = RetryPolicy { status in
    status.iteration == 0 ? .zero : .seconds(1)
}

let user = await withRetry(quickThenSlow.and(.limitRetries(3))) { await fetchUser(id) }
// Delays: 0s, 1s, 1s, then gives up
```

A policy you reuse belongs in an extension of ``RetryPolicy``. A `static func` that returns a policy works with leading-dot syntax, exactly like ``RetryPolicy/exponentialBackoff(_:)``, so it chains with the built-in modifiers:

```swift
extension RetryPolicy {
    /// Waits `step` before the first retry, `2 × step` before the second, and so on.
    static func linearBackoff(_ step: Duration) -> RetryPolicy {
        RetryPolicy { status in step * (status.iteration + 1) }
    }
}

let apiPolicy = RetryPolicy.linearBackoff(.milliseconds(500))
    .and(.limitRetries(4))
    .capDelay(.milliseconds(1500))
// Delays: 0.5s, 1s, 1.5s, 1.5s, then gives up
```

A modifier — a policy that reshapes another — is an instance method that asks `self` for its delay and changes the answer. Calling a policy as a function, `self(status)`, returns its delay. This one is the opposite of ``RetryPolicy/capDelay(_:)``: it never lets a retry come sooner than `minimum`:

```swift
extension RetryPolicy {
    /// Waits at least `minimum` before every retry.
    func minimumDelay(_ minimum: Duration) -> RetryPolicy {
        RetryPolicy { status in
            self(status).map { delay in max(delay, minimum) }
        }
    }
}

let user = await withRetry(.limitRetries(3).minimumDelay(.milliseconds(100))) {
    await fetchUser(id)
}
// Delays: 100ms, 100ms, 100ms, then gives up
```

`Optional.map` passes `nil` through untouched, so the policy a modifier wraps still decides when to give up. Check a policy you write with ``RetryPolicy/dryRun()``.

### Checking a schedule

``RetryPolicy/dryRun()`` lists the statuses a policy goes through, without running or waiting:

```swift
RetryPolicy.exponentialBackoff(.seconds(1))
    .and(.limitRetries(3))
    .dryRun()
    .map(\.previousDelay)
// [1s, 2s, 4s, nil]
```

### Clocks and cancellation

Delays are waited on a `ContinuousClock` unless `withRetry` is given another `Clock<Duration>`, such as a test clock that records its sleeps and returns at once. A `.zero` delay retries without using the clock. Cancelling the task stops retrying and returns the latest failure.

## Topics

### Policies

- ``RetryPolicy``
- ``RetryStatus``
