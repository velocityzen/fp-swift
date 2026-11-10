# API Reference

Every helper, and what it does.

The operators are in <doc:PipeOperators>, and the retry API is in the `FPRetry` module.

`Result`:

| Method                                             | What it does                              |
| -------------------------------------------------- | ----------------------------------------- |
| `tap`, `tapAsync`                                  | Runs a side effect on a success.          |
| `tapError`, `tapErrorAsync`                        | Runs a side effect on a failure.          |
| `finally`, `finallyAsync`                          | Runs a side effect in both cases.         |
| `mapAsync`, `flatMapAsync`, `mapErrorAsync`        | `map`, `flatMap` and `mapError`, async.   |
| `as`, `asUnit`                                     | Replaces the success value.               |
| `match`, `matchAsync`                              | Turns both cases into one value.          |
| `isSuccess`, `isFailure`                           | Checks the case.                          |
| `alt`, `altAsync`                                  | Replaces a failure with another `Result`. |
| `orElse`, `orElseAsync`                            | Makes a new `Result` from the error.      |
| `getOrElse`, `getOrElseAsync`                      | The value, or a fallback.                 |
| `getOrExit`, `orExit`                              | Exits the process on a failure.           |
| `Result.fromOptional`                              | Turns an `Optional` into a `Result`.      |
| `Result.fromAsync`                                 | Runs async code that throws.              |
| `Result.fromTask`                                  | Waits for a `Task`.                       |
| `ResultDo`: `bind`, `let`, `bindAsync`, `letAsync` | Do notation.                              |

Functions:

| Function      | What it does                                                  |
| ------------- | ------------------------------------------------------------- |
| `flatten`     | Combines up to 10 results into a result of a tuple.           |
| `withAll`     | The same for async calls, run at the same time.               |
| `withAny`     | The first success of async calls, run at the same time.       |
| `withTimeout` | The result of an async call, or a failure when time runs out. |

`Optional`:

| Method                        | What it does                         |
| ----------------------------- | ------------------------------------ |
| `match`, `matchAsync`         | Turns both cases into one value.     |
| `mapAsync`, `flatMapAsync`    | `map` and `flatMap`, async.          |
| `orElse`, `orElseAsync`       | The first value that is not `nil`.   |
| `getOrElse`, `getOrElseAsync` | The value, or a default (like `??`). |
| `finally`, `finallyAsync`     | Runs a side effect in both cases.    |

`Array`:

| Method                                        | What it does                               |
| --------------------------------------------- | ------------------------------------------ |
| `traverse`, `traverseAsync`                   | All values, or the first failure.          |
| `separate`, `successes`, `failures`           | Splits `[Result]`.                         |
| `compact`, `sequence`                         | Removes `nil` elements, or all or nothing. |
| `mapAsync`, `flatMapAsync`, `compactMapAsync` | `map`, `flatMap` and `compactMap`, async.  |

`AsyncSequence` and `AsyncStream`:

| Method                                                                     | What it does                                |
| -------------------------------------------------------------------------- | ------------------------------------------- |
| `successes`, `failures`                                                    | One side of a sequence of results.          |
| `map`, `mapError`, `flatMap`, `tap`, `tapError` and their `Async` versions | Work on one side. The other passes through. |
| `mapAsyncOrdered`, `flatMapAsyncOrdered`, `compactMapAsyncOrdered`         | Concurrent, in source order.                |
| `mapAsyncUnordered`, `flatMapAsyncUnordered`, `compactMapAsyncUnordered`   | Concurrent, in the order they finish.       |
| `AsyncStream.success`, `AsyncStream.failure`                               | A stream of one result.                     |
| `success`, `failure`, `finishWithSuccess`, `finishWithFailure`             | Add a result on a continuation.             |

<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->
