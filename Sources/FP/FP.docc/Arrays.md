# Arrays

Turn arrays into results, split arrays of results, and map with async code.

| Method                                        | What it does                                                                |
| --------------------------------------------- | --------------------------------------------------------------------------- |
| `traverse { element in result }`              | Turns each element into a `Result`. Gives all values, or the first failure. |
| `traverseAsync { … }`                         | The same with an async closure, one element at a time.                      |
| `traverseAsync(concurrency: n) { … }`         | Runs up to `n` closures at the same time. See below.                        |
| `separate()`                                  | Splits `[Result]` into `(successes, failures)`.                             |
| `successes()`, `failures()`                   | One side of `[Result]`.                                                     |
| `compact()`                                   | Removes the `nil` elements of `[T?]`.                                       |
| `sequence()`                                  | Turns `[T?]` into `[T]?`. It is `nil` if any element is `nil`.              |
| `mapAsync`, `flatMapAsync`, `compactMapAsync` | `map`, `flatMap` and `compactMap` with an async closure.                    |

```swift
let ids = [1, 2, 3]

let users = ids.traverse { id in fetchUser(id: id) }
// .success([User]), or the first failure

let loaded = await ids.traverseAsync(concurrency: 4) { id in
    await loadUser(id: id)
}
```

With `concurrency:`, the values keep the array order. When elements fail, it gives the failure of the first one in the array, and cancels the closures that still run.

<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->
