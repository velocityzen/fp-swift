# Working with Results

Run side effects, change and check results, and recover from failures.

fp-swift adds these methods to `Result`:

| Method                        | What it does                                                 |
| ----------------------------- | ------------------------------------------------------------ |
| `tap { value in … }`          | Runs a side effect on a success. The result does not change. |
| `tapError { error in … }`     | Runs a side effect on a failure.                             |
| `finally { … }`               | Runs a side effect in both cases.                            |
| `as(value)`                   | Replaces the success value with `value`.                     |
| `asUnit()`                    | Replaces the success value with `()`.                        |
| `isSuccess`, `isFailure`      | `true` for a success, or for a failure.                      |
| `match(onSuccess, onFailure)` | Turns both cases into one value.                             |

```swift
let greeting = fetchUser(id: 1)
    .tap { user in cache.save(user) }
    .tapError { error in log(error) }
    .match(
        { user in "Hello, \(user.name)" },
        { error in "Error: \(error)" }
    )
```

`match` also takes plain values: `result.match("ok", "error")`.

`tap` and `tapError` also take a closure that throws, or one that returns a `Result`. Then an error from the closure becomes the failure.

## Recovering from failures

| Method                       | Gives                                                                     |
| ---------------------------- | ------------------------------------------------------------------------- |
| `alt { otherResult }`        | `self` if it is a success, or else the other `Result`.                    |
| `orElse { error in result }` | Like `alt`, but the closure gets the error and can change its type.       |
| `getOrElse(value)`           | The success value, or `value`.                                            |
| `getOrElse { error in … }`   | The success value, or a value made from the error.                        |
| `getOrExit()`                | The success value, or prints the error and exits. For command-line tools. |
| `orExit()`                   | Nothing, or prints the error and exits.                                   |

```swift
let user = fetchUser(id: 1)
    .alt { fetchCachedUser(id: 1) }
    .getOrElse(.guest)
```

In a command-line tool:

```swift
let config = loadConfig().getOrExit()
// On a failure, prints "Error: <error>" to stderr and exits with 1.
```

`getOrExit(prefix:exitCode:)` and `getOrExit { error in message }` change the message and the exit code. `orExit` takes the same arguments.

<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->
