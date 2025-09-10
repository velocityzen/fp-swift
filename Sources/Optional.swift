public func |> <A, Z>(lhs: A?, rhs: (A) -> Z) -> Z? {
    return lhs.map(rhs)
}

public func |> <A, Z>(lhs: A?, rhs: (A) -> Z?) -> Z? {
    return lhs.flatMap(rhs)
}
