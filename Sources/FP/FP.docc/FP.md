# ``FP``

Functional helpers for Swift's own `Result`, `Optional` and `Array` types, in sync and async code.

## Overview

fp-swift adds functional helpers to Swift's own `Result`, `Optional` and `Array` types, for sync and async code. Chain steps that can fail, recover from errors, and run work in parallel. Retries are in the separate `FPRetry` module.

<!-- Quick start: made from README.md by Scripts/make-docc-articles.swift. -->

```swift
import FP

enum AppError: Error {
    case notANumber(String)
}

func parse(_ text: String) -> Result<Int, AppError> {
    .fromOptional(Int(text), error: .notANumber(text))
}

let doubled = parse("21")
    .tap { n in print("parsed", n) }  // prints "parsed 21"
    .map { n in n * 2 }
    .getOrElse(0)                     // 42
```

`Result` is Swift's own type. fp-swift adds methods like `tap` and `getOrElse` to it. A failure skips the steps that change values, so `parse("x")` gives 0.

<!-- End of quick start. -->

The articles below start with the basics and end with advanced topics. Start with <doc:GettingStarted>.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:PipeOperators>
- <doc:WorkingWithResults>
- <doc:Optionals>

### Advanced Topics

- <doc:DoNotation>
- <doc:AsyncResults>
- <doc:Arrays>
- <doc:AsyncSequences>

### Reference

- <doc:APIReference>
