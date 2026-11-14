# Contributing to fp-swift

## Setup

fp-swift is a plain SwiftPM package: clone it and build. You need Swift 6.3 or later.

```sh
swift build
swift test
```

CI runs `swift-format` in strict mode. Run it before you push:

```sh
swift format lint --strict --recursive Sources Tests Scripts \
    Benchmarks/Package.swift Benchmarks/Sources Benchmarks/Benchmarks
```

## Project layout

| Directory | Contents |
| --- | --- |
| `Sources/FP/` | the `FP` module: `Result`, `Optional`, `Array` and async sequence helpers |
| `Sources/FP/FP.docc/` | the `FP` DocC catalog. `Extensions/` holds the pages for the standard library types. |
| `Sources/FPRetry/` | the `FPRetry` module: `RetryPolicy`, `RetryStatus`, `withRetry` |
| `Scripts/` | `make-docc-articles.swift` |
| `Benchmarks/` | the benchmark package (see [Benchmarks](#benchmarks)) |

## Property tests

`Tests/FPPropertyTests` checks the libraries with
[Hegel](https://github.com/velocityzen/hegel-swift) properties, on macOS and
Linux. A failure's report ends with a `.hegel(reproducing:)` trait that
replays its minimal example.

Every push runs them on the same inputs. The nightly workflow runs them on new
inputs with ten times the test cases, and runs every test under
ThreadSanitizer. To run the same locally:

```sh
HEGEL_DEFAULT_PROFILE=nightly HEGEL_TEST_CASES_SCALE=10 swift test --filter FPPropertyTests
swift test --sanitize=thread \
    --skip '[oO]rExit[A-Za-z]*OnFailure|applyingAtTheLastIterationDoesNotCrash'
```

Exit tests are skipped under ThreadSanitizer: their child process starts
without the sanitizer's runtime and aborts.

## Documentation

`README.md` is the source of the documentation. A script makes the DocC articles in `Sources/FP/FP.docc` and `Sources/FPRetry/FPRetry.docc` from it, and the quick start on each landing page. Don't edit those by hand. Edit `README.md`, then run:

```sh
swift Scripts/make-docc-articles.swift            # write the articles
swift Scripts/make-docc-articles.swift --check    # change nothing; fail when an article is out of date
```

- **Articles.** Each article is made from one or more `## ` sections of the README, as `articles` at the top of the script lists them. The script fails on a section that no article uses. A new article also needs a `<doc:>` link in the Topics of `FP.md` or `FPRetry.md`.
- **Links.** DocC can't follow links to README sections (`#…`) or to relative paths. The script fails on them. Add the DocC link that replaces each one to `linkEdits` in the script.
- **Line length.** Keep code lines in the README at 72 characters or fewer. DocC cuts off longer lines, and the script fails on them.
- **Tests.** Every README example is also a test, in `Tests/fpTests/Readme/` and `Tests/FPRetryTests/Readme/`. When you change an example, change its test too.
- **Symbol docs.** Keep doc comments short and in plain English. Say what the API does and what to watch out for. Don't repeat the code.

To see the result, open the package in Xcode and choose Product → Build Documentation.

## Benchmarks

The [`Benchmarks/`](Benchmarks/README.md) package measures time, allocations and reference counting with [ordo-one/benchmark](https://github.com/ordo-one/benchmark). Record a baseline before a change and compare after it. CI fails a pull request whose allocation or retain and release counts get worse.
