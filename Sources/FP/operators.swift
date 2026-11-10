/// The precedence of the pipe operators.
///
/// Pipes have lower precedence than arithmetic, ranges, casts, and `??`, and higher precedence
/// than comparisons, logical operators, and assignment:
///
/// ```swift
/// 1 + 2 |> double          // double(3), not 1 + double(2)
/// x |> transform == 6      // (x |> transform) == 6
/// flag && x |> isValid     // flag && (x |> isValid)
/// a ?? b |> process        // (a ?? b) |> process
/// ```
precedencegroup PipePrecedence {
    associativity: left
    higherThan: ComparisonPrecedence
    lowerThan: NilCoalescingPrecedence
}

infix operator |> : PipePrecedence

/// Passes `lhs` to `rhs`: `value |> transform` is `transform(value)`.
@inlinable
public func |> <A, Z>(lhs: A, rhs: (A) -> Z) -> Z {
    return rhs(lhs)
}

/// Passes `lhs` to the async function `rhs`.
@inlinable
public func |> <A, Z>(lhs: A, rhs: (A) async -> Z) async -> Z {
    await rhs(lhs)
}

infix operator |>> : PipePrecedence

/// Passes `lhs` as the second argument: `value |>> (fn, a)` is `fn(a, value)`.
@inlinable
public func |>> <A, B, Z>(lhs: B, rhs: ((A, B) -> Z, A)) -> Z {
    return rhs.0(rhs.1, lhs)
}

/// Passes `lhs` as the second argument of an async function.
@inlinable
public func |>> <A, B, Z>(lhs: B, rhs: ((A, B) async -> Z, A)) async -> Z {
    await rhs.0(rhs.1, lhs)
}

infix operator |>>> : PipePrecedence

/// Passes `lhs` as the third argument: `value |>>> (fn, a, b)` is `fn(a, b, value)`.
@inlinable
public func |>>> <A, B, C, Z>(lhs: C, rhs: (((A, B, C) -> Z), A, B)) -> Z {
    return rhs.0(rhs.1, rhs.2, lhs)
}

/// Passes `lhs` as the third argument of an async function.
@inlinable
public func |>>> <A, B, C, Z>(lhs: C, rhs: (((A, B, C) async -> Z), A, B)) async -> Z {
    await rhs.0(rhs.1, rhs.2, lhs)
}

prefix operator |>

/// Wraps a function in a closure, for function composition.
@inlinable
public prefix func |> <A, Z>(_ rhs: @escaping (A) -> Z) -> (A) -> Z {
    return { a in rhs(a) }
}

/// Wraps an async function in a closure, for function composition.
@inlinable
public prefix func |> <A, Z>(_ rhs: @escaping (A) async -> Z) -> (A) async -> Z {
    return { a in await rhs(a) }
}
