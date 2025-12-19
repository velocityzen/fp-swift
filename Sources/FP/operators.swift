precedencegroup PipePrecedence {
    associativity: left
    higherThan: BitwiseShiftPrecedence
}

infix operator |> : PipePrecedence

/// Forward pipe operator
public func |> <A, Z>(lhs: A, rhs: (A) -> Z) -> Z {
    return rhs(lhs)
}

infix operator |>> : PipePrecedence

/// Pipe into second argument
public func |>> <A, B, Z>(lhs: B, rhs: ((A, B) -> Z, A)) -> Z {
    return rhs.0(rhs.1, lhs)
}

infix operator |>>> : PipePrecedence

/// Pipe into third argument
public func |>>> <A, B, C, Z>(lhs: C, rhs: (((A, B, C) -> Z), A, B)) -> Z {
    return rhs.0(rhs.1, rhs.2, lhs)
}

infix operator |< : PipePrecedence

/// Pipe into last argument
public func |< <A, Z>(lhs: A, rhs: (A) -> Z) -> Z {
    return rhs(lhs)
}

prefix operator |>

/// Flow operator - creates a function from another function
public prefix func |> <A, Z>(_ rhs: @escaping (A) -> Z) -> (A) -> Z {
    return { a in rhs(a) }
}
