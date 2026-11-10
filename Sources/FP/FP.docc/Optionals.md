# Optionals

Turn optionals into results, and work with optional values.

`Result.fromOptional` turns an `Optional` into a `Result`:

```swift
let result: Result<User, AppError> =
    .fromOptional(cachedUser, error: .notFound)
```

To make the error only when it is needed, pass a closure: `.fromOptional(cachedUser) { .notFound }`.

fp-swift also adds a few methods to `Optional`:

```swift
let name: String? = nil

name.match({ n in "Hi, \(n)" }, "Hi, guest")  // "Hi, guest"
name.orElse(nickname)     // the first value that is not nil
name.getOrElse("guest")   // like ??
```

`mapAsync`, `flatMapAsync`, `orElseAsync` and `getOrElseAsync` take async closures. `finally` runs a side effect in both cases.

<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->
