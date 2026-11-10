# ``FPRetry``

Retry async operations that return a `Result`, with policies you can combine and reuse.

## Overview

A ``RetryPolicy`` decides two things after each failure: whether to retry, and how long to wait first. `withRetry` runs an action until it succeeds or the policy stops.

<!-- Quick start: made from README.md by Scripts/make-docc-articles.swift. -->

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

<!-- End of quick start. -->

<doc:Retrying> shows how to retry only some failures, the built-in policies, jitter, and how to write your own policy.

## Topics

### Essentials

- <doc:Retrying>

### Policies

- ``RetryPolicy``
- ``RetryStatus``
