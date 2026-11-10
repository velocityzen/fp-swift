# Async Results

Chain async steps, combine results, race calls, and add time limits.

`mapAsync`, `flatMapAsync`, `mapErrorAsync`, `tapAsync`, `tapErrorAsync`, `altAsync` and the other `Async` methods take async closures:

```swift
func profile(id: Int) async -> Result<Profile, AppError> {
    await fetchUser(id: id)
        .tapAsync { user in await analytics.track(user) }
        .flatMapAsync { user in await loadProfile(of: user) }
}
```

To call async code that throws, use `Result.fromAsync`. The failure type is then `any Error`:

```swift
let data = await Result.fromAsync {
    try await loadData()
}
```

`Result.fromTask(task)` waits for a `Task` and turns its value or error into a `Result`.

## Combining results

`flatten` combines up to 10 results into one result of a tuple. It gives the first failure, if there is one:

```swift
let both = flatten(fetchUser(id: 1), fetchSettings(id: 1))
// Result<(User, Settings), AppError>
```

`withAll` does the same with async calls, and runs them at the same time. The first failure returns at once and cancels the other calls:

```swift
let home = await withAll(
    await loadUser(id: 1),
    await loadMessages(id: 1)
)
// Result<(User, [Message]), AppError>
```

## Racing and timeouts

`withAny` runs async calls at the same time and gives the first success. A failure does not win: the other calls keep running. The winner cancels the rest. When all fail, it gives the last failure.

```swift
let data = await withAny(
    await download(from: primary),
    await download(from: backup)
)
```

For a number of calls known only at run time, pass an array of closures. It must not be empty.

`withTimeout` gives the result of an async call, or a failure when the time runs out. Then it cancels the call. A failure that comes in time is returned as it is.

```swift
let profile = await withTimeout(.seconds(5), failingWith: .timeout) {
    await loadProfile(id: 1)
}
```

Cancellation stops only code that checks for it, like `Task.sleep` and `URLSession` calls. A long loop with no `await` runs to its end.

<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->
