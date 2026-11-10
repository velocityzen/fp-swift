# Getting Started

Add fp-swift to your package, and write your first chain of results.

## Installation

Requirements:

- Swift 6.3 or later
- macOS, iOS, tvOS, watchOS or visionOS 26 or later, or Linux

Add the package to `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/velocityzen/fp-swift.git",
        from: "4.3.0"
    ),
],
```

Then add the products your target uses:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "FP", package: "fp-swift"),
        // Only if you need retries:
        .product(name: "FPRetry", package: "fp-swift"),
    ]
),
```

`FPRetry` does not depend on `FP`, so a target that only retries can use it alone.

## Quick start

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

<!-- Made from README.md by Scripts/make-docc-articles.swift. Edit README.md, then run the script. -->
