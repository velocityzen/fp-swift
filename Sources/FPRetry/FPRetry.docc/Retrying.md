# Retrying

Retry async operations, and choose when and how long to wait.

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

## Retry only some failures

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

## Use the retry status

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

## Built-in policies

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

## Jitter

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

## Write your own policy

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

## Check a policy

`dryRun()` lists the steps of a policy. It does not run anything and does not wait:

```swift
RetryPolicy.exponentialBackoff(.seconds(1))
    .and(.limitRetries(3))
    .dryRun()
    .map(\.previousDelay)
// [1s, 2s, 4s, nil]
```

`dryRun()` is lazy. For a policy that never stops, take only the first steps: `.dryRun().prefix(10)`.

## Clock, cancellation and actors

- `withRetry` waits on a `ContinuousClock`. To use another clock, for example a test clock that does not really wait, pass `clock:`.
- A wait of zero does not use the clock.
- When the task is cancelled, `withRetry` stops and returns the last failure.
- A wait is never less than zero or more than `RetryPolicy.maximumDelay`, so a long backoff never overflows.
- The action runs on the caller's actor, so code on `@MainActor` can use its own state in it.

<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->
