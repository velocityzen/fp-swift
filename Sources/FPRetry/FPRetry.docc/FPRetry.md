# ``FPRetry``

Retry async operations that return a `Result`, with policies you can combine and reuse.

## Overview

FPRetry is based on [retry-ts](https://github.com/gcanti/retry-ts).

A ``RetryPolicy`` decides two things after each failure: whether to retry, and how long to wait first. Create a policy once and use it in many places.

```swift
import FPRetry

// Wait up to 200ms, 400ms, 800ms, and so on, but never more than 2s.
// Retry at most 5 times. Each wait is random (jitter).
let apiPolicy = RetryPolicy.exponentialBackoff(.milliseconds(200))
    .and(.limitRetries(5))
    .capDelay(.seconds(2))
    .jitter()

let user = await withRetry(apiPolicy, while: \.isTransient) { await fetchUser(id) }
// Result<User, APIError>
```

`withRetry` returns the first success. If every attempt fails, it returns the last failure. It never retries a success. The action can take a ``RetryStatus`` to know which attempt is running.

### Retry only some failures

Some failures can pass on the next try, for example a timeout. Others fail again every time, for example "not found". Use `while:` to choose which failures to retry: return `true` to retry. Without `while:`, every failure is retried.

You usually put this rule on your error type. `isTransient` is not part of FPRetry. You write it:

```swift
enum APIError: Error, Equatable {
    case timeout
    case rateLimited
    case server(status: Int)
    case unauthorized
    case notFound

    /// True when the request can succeed if we try again.
    var isTransient: Bool {
        switch self {
            case .timeout, .rateLimited: true
            case .server(let status): status >= 500
            case .unauthorized, .notFound: false
        }
    }
}
```

`\.isTransient` is a key path. Swift can use a key path as a function (SE-0249). These two lines do the same thing:

```swift
await withRetry(apiPolicy, while: \.isTransient) { await fetchUser(id) }
await withRetry(apiPolicy, while: { error in error.isTransient }) { await fetchUser(id) }
```

### Combine policies

``RetryPolicy/and(_:)`` retries only while both policies retry, and waits the longer of the two waits. Modifiers change the wait of a policy, or when it stops:

```swift
RetryPolicy.exponentialBackoff(.seconds(1))
    .capDelay(.seconds(30))
    .limitRetriesByCumulativeDelay(.seconds(120))
```

``RetryPolicy/constantDelay(_:)`` and ``RetryPolicy/exponentialBackoff(_:)`` never stop by themselves. Combine them with a limit, for example `.and(.limitRetries(5))`.

### Jitter

Many clients often fail at the same time, for example when a server restarts. With the same policy, they also retry at the same time, and this can overload the server again. ``RetryPolicy/jitter(_:)`` makes each wait random, so the retries spread out. Use jitter when many clients use the same policy.

The range contains multipliers, not durations:

- `.jitter()`: from 0 to the full wait. The same as `.jitter(0...1)`.
- `.jitter(0.5...1)`: from half the wait to the full wait.
- `.jitter(0.8...1.2)`: the wait, plus or minus 20%.

Put jitter last, after ``RetryPolicy/capDelay(_:)``. Then a wait is never longer than the cap.

For tests that need the same random numbers every time, use ``RetryPolicy/jitter(_:using:)`` with your own seeded generator.

### Write your own policy

A policy is a function. It takes a ``RetryStatus`` and returns a `Duration?`. Return a duration to wait and retry. Return `nil` to stop. Wrap the function in ``RetryPolicy/init(_:)``, and it works with all the built-in policies.

A policy for one place:

```swift
// Retry the first time at once. Then wait 1 second before each retry.
let quickThenSlow = RetryPolicy { status in
    status.iteration == 0 ? .zero : .seconds(1)
}

let user = await withRetry(quickThenSlow.and(.limitRetries(3))) { await fetchUser(id) }
// Waits: 0s, 1s, 1s, then stops
```

A policy to reuse: add a `static func` in an extension. Then you can write it with a leading dot, like the built-in policies:

```swift
extension RetryPolicy {
    /// Waits `step`, then `2 × step`, then `3 × step`, and so on.
    static func linearBackoff(_ step: Duration) -> RetryPolicy {
        RetryPolicy { status in step * (status.iteration + 1) }
    }
}

let linearPolicy = RetryPolicy.linearBackoff(.milliseconds(500))
    .and(.limitRetries(4))
    .capDelay(.milliseconds(1500))
// Waits: 0.5s, 1s, 1.5s, 1.5s, then stops
```

A modifier changes another policy. Write it as an instance method. Call `self(status)` to get the wait of the original policy, then change it. This modifier sets a minimum wait:

```swift
extension RetryPolicy {
    /// Waits at least `minimum` before each retry.
    func minimumDelay(_ minimum: Duration) -> RetryPolicy {
        RetryPolicy { status in
            self(status).map { delay in max(delay, minimum) }
        }
    }
}

let user = await withRetry(.limitRetries(3).minimumDelay(.milliseconds(100))) {
    await fetchUser(id)
}
// Waits: 100ms, 100ms, 100ms, then stops
```

When the original policy stops, `self(status)` returns `nil`. `Optional.map` keeps the `nil`, so the modifier stops too.

### Check a policy

``RetryPolicy/dryRun()`` shows the steps of a policy. It does not run anything and does not wait:

```swift
RetryPolicy.exponentialBackoff(.seconds(1))
    .and(.limitRetries(3))
    .dryRun()
    .map(\.previousDelay)
// [1s, 2s, 4s, nil]
```

### Clock and cancellation

`withRetry` waits on a `ContinuousClock`. To use another clock, pass `clock:`. For example, a test clock that does not really wait. If the task is cancelled, `withRetry` stops and returns the last failure.

## Topics

### Policies

- ``RetryPolicy``
- ``RetryStatus``
