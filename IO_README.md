# IO Typeclass in Swift

## Overview

The `IO` typeclass represents computations that perform side effects. It provides a way to compose and defer side effects in a purely functional manner, ensuring that side effects are explicit and controlled.

## What is IO?

`IO<A>` represents a computation that, when executed, will perform some side effects and produce a value of type `A`. The key insight is that `IO` values are **descriptions** of computations, not the computations themselves. This allows us to:

- Compose side-effectful computations without executing them
- Reason about side effects in a pure functional way
- Control exactly when and how side effects occur

## Basic Usage

### Creating IO Values

```swift
// Pure value (no side effects)
let greeting = IO.pure("Hello, World!")

// Side effect that returns a value
let currentTime = IO { Date() }

// Side effect that returns Void
let printAction = IO<Void>.effect { print("Side effect!") }
```

### Executing IO

```swift
let result = greeting.unsafePerformIO()
// Note: unsafePerformIO() is where the side effect actually happens
```

## Core Operations

### Functor (map)

Transform the value inside an IO without changing the effect:

```swift
let number = IO.pure(5)
let doubled = number.map { $0 * 2 }
// Or using the pipe operator:
let doubled = number |> { $0 * 2 }
```

### Monad (flatMap)

Compose IO computations sequentially:

```swift
let computation = IO.pure(5)
    .flatMap { value in
        IO.pure(value * 2)
    }
    .flatMap { doubled in
        IO<Void>.print("Result: \(doubled)")
    }

// Or using the pipe operator:
let computation = IO.pure(5)
    |> { value in IO.pure(value * 2) }
    |> { doubled in IO<Void>.print("Result: \(doubled)") }
```

### Applicative

Apply a function wrapped in IO to a value wrapped in IO:

```swift
let function = IO.pure { (x: Int) in x * 2 }
let value = IO.pure(5)
let result = function <*> value
```

## Sequencing Operations

### Sequential Execution

```swift
// Execute first, then second, keep second result
let sequence1 = firstIO *> secondIO

// Execute first, then second, keep first result  
let sequence2 = firstIO <* secondIO

// Execute first, then second (explicit)
let sequence3 = firstIO.then(secondIO)
let sequence4 = firstIO.before(secondIO)
```

### Conditional Execution

```swift
// Execute action only if condition is true
IO<Void>.when(shouldExecute, action)

// Choose between two actions
IO<String>.ifThenElse(condition, thenAction, elseAction)
```

## Working with Collections

### Sequence

Convert a collection of IO actions into an IO of a collection:

```swift
let ioActions = [IO.pure(1), IO.pure(2), IO.pure(3)]
let sequenced: IO<[Int]> = IO.sequence(ioActions)
```

### Traverse

Map each element through an IO action and sequence the results:

```swift
let numbers = [1, 2, 3]
let traversed = IO<[String]>.traverse(numbers) { num in
    IO.pure("Number: \(num)")
}
```

## Common Patterns

### Logging and Side Effects

```swift
let logIO = { (message: String) in
    IO<Void>.effect { print("Log: \(message)") }
}

let computation = 
    logIO("Starting computation")
    *> IO.pure(42)
    |> { value in 
        logIO("Got value: \(value)")
        *> IO.pure(value * 2)
    }
    <* logIO("Computation complete")
```

### Resource Management

```swift
func withResource<R, A>(_ resource: R, _ action: (R) -> IO<A>) -> IO<A> {
    return IO<Void>.effect { print("Acquiring \(resource)") }
        *> action(resource)
        <* IO<Void>.effect { print("Releasing \(resource)") }
}

let result = withResource("DatabaseConnection") { connection in
    IO<Void>.print("Using \(connection)")
        *> IO.pure("Query result")
}
```

### Error Handling and Retry

```swift
let unreliableOperation = IO {
    // Some operation that might need retrying
    return "Success"
}

let retriedOperation = unreliableOperation.retry(maxAttempts: 3)
```

### Timing Operations

```swift
let operation = IO {
    Thread.sleep(forTimeInterval: 1.0)
    return "Done"
}

let timedOperation = operation.timed()
let (result, duration) = timedOperation.unsafePerformIO()
```

## Built-in IO Operations

### Console Operations

```swift
// Print to stdout
IO<Void>.print("Hello, World!")

// Print without newline
IO<Void>.printNoNewline("Input: ")

// Read from stdin
let input: IO<String> = IO<String>.readLine()
let optionalInput: IO<String?> = IO<String?>.readLineOptional()
```

### Repetition

```swift
let action = IO<Void>.print("Hello")
let repeated = action.repeated(3) // Executes 3 times
```

## Operators Reference

| Operator | Name | Description |
|----------|------|-------------|
| `\|>` | Pipe/Map | `IO<A> \|> (A -> B) -> IO<B>` |
| `\|>` | Pipe/FlatMap | `IO<A> \|> (A -> IO<B>) -> IO<B>` |
| `<*>` | Apply | `IO<(A -> B)> <*> IO<A> -> IO<B>` |
| `*>` | Sequence Right | `IO<A> *> IO<B> -> IO<B>` |
| `<*` | Sequence Left | `IO<A> <* IO<B> -> IO<A>` |

## Laws and Properties

The IO type satisfies the monad laws:

### Left Identity
```swift
IO.pure(a).flatMap(f) ≡ f(a)
```

### Right Identity  
```swift
io.flatMap(IO.pure) ≡ io
```

### Associativity
```swift
io.flatMap(f).flatMap(g) ≡ io.flatMap { x in f(x).flatMap(g) }
```

## Best Practices

### 1. Compose, Don't Execute Early

```swift
// Good: Compose operations
let program = 
    getUserInput()
    |> processInput
    |> saveResult
    |> logSuccess

// Execute only once at the end
program.unsafePerformIO()

// Bad: Execute intermediate steps
let input = getUserInput().unsafePerformIO()
let processed = processInput(input).unsafePerformIO()
// ...
```

### 2. Use Type Annotations for Complex Compositions

```swift
// Help the compiler with explicit types
let complexOperation: IO<String> = 
    step1()
    |> { result1 in 
        step2(result1) |> { result2 in
            IO.pure("\(result1) + \(result2)")
        }
    }
```

### 3. Separate Pure and Effectful Code

```swift
// Pure function
func calculateResult(input: String) -> Int {
    return input.count * 2
}

// IO wrapper
func getResultIO() -> IO<Int> {
    return getUserInput() |> calculateResult
}
```

### 4. Use Resource Management Patterns

```swift
func withFile<A>(_ path: String, _ action: (FileHandle) -> IO<A>) -> IO<A> {
    return IO<FileHandle> { FileHandle(forReadingAtPath: path)! }
        |> { handle in 
            action(handle) <* IO<Void>.effect { handle.closeFile() }
        }
}
```

## Examples

See `IOExamples.swift` for comprehensive examples including:

- Basic IO operations
- Composition patterns
- Sequencing and conditional execution
- Collection operations
- Business logic with IO
- Resource management
- Interactive programs

## Testing IO Code

When testing IO operations, you can:

1. Test the composition without executing:
```swift
let program = createProgram(input: "test")
// Assert on the structure, not execution
```

2. Execute in controlled environments:
```swift
let result = program.unsafePerformIO()
XCTAssertEqual(result, expectedValue)
```

3. Mock IO operations:
```swift
func mockGetUser(id: Int) -> IO<User?> {
    return IO.pure(User(id: id, name: "Test User"))
}
```

## Advanced Topics

### IO and Concurrency

While this implementation is sequential, IO can be extended to work with Swift's async/await:

```swift
// Future extension possibility
extension IO {
    func async() async -> A {
        return self.unsafePerformIO()
    }
}
```

### IO Transformers

IO can be combined with other monads using monad transformers (not implemented in this basic version).

### Performance Considerations

- IO operations are lazy - no computation happens until `unsafePerformIO()`
- Deeply nested IO operations might cause stack overflow in extreme cases
- Consider batching operations when possible

## Conclusion

The IO typeclass provides a powerful way to handle side effects in a functional programming style. It allows you to:

- Compose effectful computations declaratively
- Separate pure and impure code
- Control exactly when side effects occur
- Test and reason about effectful code more easily

By treating side effects as first-class values that can be composed and transformed, IO enables you to write more maintainable and predictable code while still performing necessary side effects.