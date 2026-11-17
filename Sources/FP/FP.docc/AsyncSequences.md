# Async Sequences

Work with async sequences of results, map them concurrently, and repeat an operation.

For an `AsyncSequence` of `Result`s, fp-swift adds `successes()`, `failures()`, `map`, `mapError`, `flatMap`, `tap`, `tapError` and their `Async` versions. Each one works on one side, and the other side passes through:

```swift
let names = events
    .tapError { error in log(error) }
    .mapAsync { id in await loadName(id) }
    .successes()

for await name in names {
    show(name)
}
```

`AsyncStream.success(value)` and `.failure(error)` make a stream of one result. On a continuation, `success`, `failure`, `finishWithSuccess` and `finishWithFailure` add results:

```swift
let stream = AsyncStream<Result<Int, AppError>> { continuation in
    continuation.success(1)
    continuation.finishWithFailure(.timeout)
}
```

`asResults()` turns a sequence that throws into a sequence of results. Each element becomes a success, and the error that ends the sequence becomes a last failure, with the same error type. The new sequence does not throw, so reading it needs no `try`:

```swift
let lines = await url.lines.asResults().toResult()
// Result<[String], any Error>: every line, or the error it threw
```

## Reading a sequence into one value

These read a sequence of results and return one value. Each one stops reading where the table says:

| Method                          | Returns                                                              | Stops reading           |
| ------------------------------- | -------------------------------------------------------------------- | ----------------------- |
| `toResult()`                    | `Result<[Success], Failure>`: all values, or the first failure       | at the first failure    |
| `toArray()`                     | `[Result<Success, Failure>]`: every element                          | at the end              |
| `separate()`                    | `([Success], [Failure])`: every value and every error                | at the end              |
| `reduce(initial, combine)`      | `Result<U, Failure>`: all values combined into one                   | at the first failure    |
| `reduce(into: initial, update)` | `Result<U, Failure>`: all values added into one value, in place      | at the first failure    |
| `first()`                       | `Result<Success, Failure>?`: the first element                       | after the first element |
| `firstSuccess()`                | `Success?`: the first value                                          | at the first success    |
| `firstError()`                  | `Failure?`: the first error                                          | at the first failure    |
| `firstSuccessOrLastError()`     | `Result<Success, Failure>?`: the first value, or else the last error | at the first success    |
| `last()`                        | `Result<Success, Failure>?`: the last element                        | at the end              |
| `lastSuccess()`                 | `Success?`: the last value                                           | at the end              |
| `lastError()`                   | `Failure?`: the last error                                           | at the end              |

```swift
let users = await ids
    .mapAsyncOrdered(concurrency: 8) { id in await loadUser(id: id) }
    .toResult()
```

Rules:

- `firstSuccessOrLastError()` follows the rule of `withAny`: the first success wins, and when nothing succeeds, the last failure is the result.
- When one of them stops reading, the stages before it stop too. A concurrent map stops reading its source and cancels the transforms still running. It does not wait for them to stop.
- The ones that stop at the end never return for a sequence that never ends, like `withRepeat`.
- They throw only what the sequence throws. A sequence that can't throw needs no `try`.
- `toResult()` can run a sequence only for what its stages do, like a `tap`, without using its result. It still stops at the first failure.

## Stopping at a failure or a success

`get()` reads a sequence of results the way `Result.get()` reads one result: it gives the values, and throws the first failure with its own error type. It is there for sequences that don't throw themselves:

```swift
do throws(AppError) {
    let users = ids.mapAsyncOrdered(concurrency: 8) { id in
        await loadUser(id: id)
    }
    for try await user in users.get() {
        show(user)
    }
} catch {
    report(error)  // the first failure; reading stops there
}
```

`untilFailure()` and `untilSuccess()` keep the results, and end after the first failure or the first success, including it:

```swift
let status = await withRepeat(interval: .seconds(1)) {
    await checkJob()
}
.untilSuccess()
.last()  // the first success, or the last failure if it stopped
```

After the element they stop at, these three read the sequence no more, so a concurrent map before them stops too.

## In a cancelled task

In a cancelled task, many sequences end early instead of throwing: `AsyncStream`, `withRepeat` and the concurrent maps all stop. A sink that reads to the end then returns what it read so far, and that looks like a complete result. This is Swift's convention: the standard library's `reduce` and `contains` do the same.

To get a failure instead, put `failOnCancellation(with:)` before the sink:

```swift
let users = await ids
    .mapAsyncOrdered(concurrency: 8) { id in await loadUser(id: id) }
    .failOnCancellation(with: .cancelled)
    .toResult()  // .failure(.cancelled) in a cancelled task
```

- It checks for cancellation before each read and when the sequence ends. If the task is cancelled, it gives `.failure(error)` and ends, and does not read the sequence again.
- The failure is an element of the sequence's own error type, so the sinks need no `try`, and they treat it like any other failure: `toResult` and `reduce` return it, and `toArray` and `last` end with it. The ones that skip failures, like `lastSuccess`, still return what they read.
- It can't tell a sequence that ended because of the cancellation from one that ended just before it, so it gives the failure in both cases.
- Inside `withTaskCancellationShield`, the task does not look cancelled, so every element passes through.

## Concurrent mapping

These map an async sequence with an async transform. Up to `concurrency` transforms run at the same time. The default is 1: one at a time.

| Operators                                                                | Results come out         |
| ------------------------------------------------------------------------ | ------------------------ |
| `mapAsyncOrdered`, `flatMapAsyncOrdered`, `compactMapAsyncOrdered`       | in source order          |
| `mapAsyncUnordered`, `flatMapAsyncUnordered`, `compactMapAsyncUnordered` | in the order they finish |

Rules:

- No new element is read while `concurrency` elements are being transformed or waiting for the consumer. So a slow consumer pauses the source.
- When the consumer stops, reading stops and running transforms are cancelled.
- Inside `withTaskCancellationShield`, cancelling the consumer's task does not stop the stream.
- On a sequence of `Result`s, `map…` and `flatMap…` change only the successes. Failures pass through in their place.
- `compactMap…` drops `nil` results. Its `passthrough:` gives a result without the transform, for example a cache hit.

For an all-or-nothing pass over an array, use `traverseAsync(concurrency:)` instead (see <doc:Arrays>).

### Keeping the source order

```swift
let images = refs.mapAsyncOrdered(concurrency: 8) { ref in
    await downloader.fetch(ref)
}

for await image in images {
    render(image)
}
```

A slow transform holds back the results after it, but not the work: later elements are still transformed, and their results wait. `bufferLimit:` caps how many results may wait, for example when the source never ends:

```swift
refs.mapAsyncOrdered(concurrency: 8, bufferLimit: 64) { ref in
    await downloader.fetch(ref)
}
```

A `bufferLimit` below `concurrency - 1` also lowers how many transforms run at the same time.

### In the order they finish

Each result comes out when its transform finishes, so a slow element holds back only itself:

```swift
let thumbs = photos.mapAsyncUnordered(concurrency: 8) { photo in
    await renderer.thumbnail(for: photo)
}

for await thumb in thumbs {
    gallery.insert(thumb)
}
```

## Repeating

`withRepeat` runs an operation again and again, and gives its results as an async sequence. The first one comes at once:

```swift
let statuses = withRepeat(interval: .seconds(5)) {
    await fetchStatus()
}

for await status in statuses {
    show(status)
}
```

Each later call starts once 5 seconds have passed since the one before it started, or at once if they have passed when the loop asks for the next status. Nothing runs until the loop asks, so a slow loop or a slow call never makes calls pile up.

To count the 5 seconds from when a call finishes instead, pass `from: .finish`. Then there are at least 5 seconds between the end of one call and the start of the next, however long the calls take:

```swift
let statuses = withRepeat(interval: .seconds(5), from: .finish) {
    await fetchStatus()
}
```

The operation can be sync or async, and it runs on the loop's actor. It can't throw. To go on after a failure, return a `Result`, and use `successes()`, `tapError` and the other operators for sequences of results:

```swift
let users = withRepeat(interval: .seconds(30)) {
    await loadUser(id: 1)
}
.tapError { error in log(error) }
.successes()

for await user in users {
    show(user)
}
```

Rules:

- The sequence never ends by itself. Cancelling the loop's task ends it, and stops a wait at once. A running call sees the cancellation only if it checks for it, and its element still comes out.
- Inside `withTaskCancellationShield`, cancelling the loop's task does not stop the sequence.
- Each `for await` loop over the sequence makes its own calls, and its first element comes at once.
- `withRepeat` waits on a `ContinuousClock`. To test code that repeats without waiting, pass a clock that does not really wait as `clock:`.

<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->
