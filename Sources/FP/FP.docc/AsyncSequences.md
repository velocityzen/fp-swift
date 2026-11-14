# Async Sequences

Work with async sequences of results, and map async sequences concurrently.

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

<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->
