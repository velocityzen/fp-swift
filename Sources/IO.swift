import Foundation

// MARK: - Operator declarations

infix operator <*> : PipePrecedence
infix operator *> : PipePrecedence
infix operator <* : PipePrecedence

/// IO Monad for representing side-effectful computations
/// Provides a way to compose and defer side effects in a purely functional manner
public struct IO<A> {
    private let computation: () -> A

    /// Create an IO action from a computation
    public init(_ computation: @escaping () -> A) {
        self.computation = computation
    }

    /// Execute the IO action and return the result
    /// This is where the side effect actually happens
    public func unsafePerformIO() -> A {
        return computation()
    }

    /// Map over the result of the IO action (Functor)
    public func map<B>(_ f: @escaping (A) -> B) -> IO<B> {
        return IO<B> {
            f(self.computation())
        }
    }

    /// FlatMap for monadic composition (Monad)
    public func flatMap<B>(_ f: @escaping (A) -> IO<B>) -> IO<B> {
        return IO<B> {
            f(self.computation()).computation()
        }
    }

    /// Apply a function wrapped in IO to a value wrapped in IO (Applicative)
    public func apply<B>(_ f: IO<(A) -> B>) -> IO<B> {
        return f.flatMap { fn in
            self.map(fn)
        }
    }
}

// MARK: - Static constructors

extension IO {
    /// Create an IO action that returns a pure value (Monad return/pure)
    public static func pure(_ value: A) -> IO<A> {
        return IO { value }
    }

    /// Alias for pure
    public static func `return`(_ value: A) -> IO<A> {
        return pure(value)
    }

    /// Create an IO action that performs a side effect and returns unit
    public static func effect(_ sideEffect: @escaping () -> Void) -> IO<Void> {
        return IO<Void> { sideEffect() }
    }

    /// Create an IO action that delays execution
    public static func delay(_ computation: @escaping () -> A) -> IO<A> {
        return IO(computation)
    }
}

// MARK: - Common IO operations

extension IO {
    /// Sequence two IO actions, keeping only the result of the second
    public func then<B>(_ next: IO<B>) -> IO<B> {
        return self.flatMap { _ in next }
    }

    /// Sequence two IO actions, keeping only the result of the first
    public func before<B>(_ next: IO<B>) -> IO<A> {
        return self.flatMap { a in
            next.map { _ in a }
        }
    }

    /// Repeat an IO action n times
    public func repeated(_ times: Int) -> IO<[A]> {
        guard times > 0 else { return IO<[A]>.pure([]) }

        return IO<[A]> {
            var results: [A] = []
            for _ in 0..<times {
                results.append(self.computation())
            }
            return results
        }
    }

    /// Conditionally execute an IO action
    public static func when(_ condition: Bool, _ action: IO<Void>) -> IO<Void> {
        return condition ? action : IO<Void>.pure(())
    }

    /// Execute one of two IO actions based on a condition
    public static func ifThenElse<B>(_ condition: Bool, _ thenAction: IO<B>, _ elseAction: IO<B>)
        -> IO<B>
    {
        return condition ? thenAction : elseAction
    }
}

// MARK: - IO for common side effects

extension IO where A == Void {
    /// Print a string to stdout
    public static func print(_ string: String) -> IO<Void> {
        return IO.effect { Swift.print(string) }
    }

    /// Print a string with no newline
    public static func printNoNewline(_ string: String) -> IO<Void> {
        return IO.effect { Swift.print(string, terminator: "") }
    }
}

extension IO where A == String {
    /// Read a line from stdin
    public static func readLine() -> IO<String> {
        return IO {
            Swift.readLine() ?? ""
        }
    }
}

extension IO where A == String? {
    /// Read a line from stdin (can be nil if EOF)
    public static func readLineOptional() -> IO<String?> {
        return IO {
            Swift.readLine()
        }
    }
}

// MARK: - Sequence operations

extension IO {
    /// Sequence a collection of IO actions into an IO of a collection
    public static func sequence<C: Collection>(_ ios: C) -> IO<[A]> where C.Element == IO<A> {
        return IO<[A]> {
            ios.map { $0.unsafePerformIO() }
        }
    }

    /// Map each element through an IO action and sequence the results
    public static func traverse<B, C: Collection>(
        _ collection: C, _ f: @escaping (C.Element) -> IO<B>
    ) -> IO<[B]> {
        return IO<[B]> {
            collection.map { element in
                f(element).unsafePerformIO()
            }
        }
    }
}

// MARK: - Pipe operators for IO

/// Map operator for IO (Functor)
public func |> <A, B>(lhs: IO<A>, rhs: @escaping (A) -> B) -> IO<B> {
    return lhs.map(rhs)
}

/// FlatMap operator for IO (Monad)
public func |> <A, B>(lhs: IO<A>, rhs: @escaping (A) -> IO<B>) -> IO<B> {
    return lhs.flatMap(rhs)
}

/// Apply operator for IO (Applicative)
public func <*> <A, B>(lhs: IO<(A) -> B>, rhs: IO<A>) -> IO<B> {
    return rhs.apply(lhs)
}

/// Sequence operator - execute first, then second, keep second result
public func *> <A, B>(lhs: IO<A>, rhs: IO<B>) -> IO<B> {
    return lhs.then(rhs)
}

/// Sequence operator - execute first, then second, keep first result
public func <* <A, B>(lhs: IO<A>, rhs: IO<B>) -> IO<A> {
    return lhs.before(rhs)
}

// MARK: - Convenience extensions

extension IO: CustomStringConvertible {
    public var description: String {
        return "IO<\(A.self)>"
    }
}

extension IO: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "IO<\(A.self)>(computation: <deferred>)"
    }
}

// MARK: - Example usage and common patterns

extension IO {
    /// Create an IO action that measures execution time
    public func timed() -> IO<(result: A, timeInterval: TimeInterval)> {
        return IO<(result: A, timeInterval: TimeInterval)> {
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = self.computation()
            let timeInterval = CFAbsoluteTimeGetCurrent() - startTime
            return (result: result, timeInterval: timeInterval)
        }
    }

    /// Retry an IO action up to n times
    /// Note: This is a simplified implementation for demonstration
    public func retry(_ maxAttempts: Int) -> IO<A> {
        return IO {
            for _ in 0..<maxAttempts {
                // In a real implementation, you'd want to handle errors properly
                // For now, we just return the computation result
                return self.computation()
            }
            return self.computation()
        }
    }
}
