/// map for Result
public func |> <A, Z, Error>(lhs: Result<A, Error>, rhs: (A) -> Z) -> Result<Z, Error> {
    return lhs.map(rhs)
}

public func |> <A, Z, Error>(lhs: Result<A, Error>, rhs: (A) -> Result<Z, Error>) -> Result<
    Z, Error
> {
    return lhs.flatMap(rhs)
}
