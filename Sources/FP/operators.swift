/// Pipe operators bind looser than arithmetic, ranges, casts, and `??`, but
/// tighter than comparisons, logical operators, and assignment — the same
/// placement as Elixir's `|>` and F#'s pipe family. The full expression on
/// the left flows into the function on the right:
///
/// ```swift
/// 1 + 2 |> double          // double(3) — not 1 + double(2)
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

/// Pipes a value into a function: `value |> transform`.
public func |> <A, Z>(lhs: A, rhs: (A) -> Z) -> Z {
    return rhs(lhs)
}

/// Asynchronously pipes a value into an async function: `value |> asyncTransform`.
public func |> <A, Z>(lhs: A, rhs: (A) async -> Z) async -> Z {
    await rhs(lhs)
}

infix operator |>> : PipePrecedence

/// Pipes a value as the second argument: `value |>> (function, firstArg)`.
public func |>> <A, B, Z>(lhs: B, rhs: ((A, B) -> Z, A)) -> Z {
    return rhs.0(rhs.1, lhs)
}

/// Asynchronously pipes a value as the second argument: `value |>> (asyncFunction, firstArg)`.
public func |>> <A, B, Z>(lhs: B, rhs: ((A, B) async -> Z, A)) async -> Z {
    await rhs.0(rhs.1, lhs)
}

infix operator |>>> : PipePrecedence

/// Pipes a value as the third argument: `value |>>> (function, firstArg, secondArg)`.
public func |>>> <A, B, C, Z>(lhs: C, rhs: (((A, B, C) -> Z), A, B)) -> Z {
    return rhs.0(rhs.1, rhs.2, lhs)
}

/// Asynchronously pipes a value as the third argument: `value |>>> (asyncFunction, firstArg, secondArg)`.
public func |>>> <A, B, C, Z>(lhs: C, rhs: (((A, B, C) async -> Z), A, B)) async -> Z {
    await rhs.0(rhs.1, rhs.2, lhs)
}

prefix operator |>

/// Flow operator: wraps a function for use in point-free composition.
public prefix func |> <A, Z>(_ rhs: @escaping (A) -> Z) -> (A) -> Z {
    return { a in rhs(a) }
}

/// Async flow operator: wraps an async function for use in point-free composition.
public prefix func |> <A, Z>(_ rhs: @escaping (A) async -> Z) -> (A) async -> Z {
    return { a in await rhs(a) }
}
