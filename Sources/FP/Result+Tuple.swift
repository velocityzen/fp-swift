import Foundation

// MARK: - Flatten tuple of Results into Result of tuple

public func flatten<A, B, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>
) -> Result<(A, B), E> {
    switch (a, b) {
        case (.success(let a), .success(let b)):
            return .success((a, b))
        case (.failure(let e), _), (_, .failure(let e)):
            return .failure(e)
    }
}

public func flatten<A, B, C, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>
) -> Result<(A, B, C), E> {
    switch (a, b, c) {
        case (.success(let a), .success(let b), .success(let c)):
            return .success((a, b, c))
        case (.failure(let e), _, _), (_, .failure(let e), _), (_, _, .failure(let e)):
            return .failure(e)
    }
}

public func flatten<A, B, C, D, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>
) -> Result<(A, B, C, D), E> {
    switch (a, b, c, d) {
        case (.success(let a), .success(let b), .success(let c), .success(let d)):
            return .success((a, b, c, d))
        case (.failure(let e), _, _, _), (_, .failure(let e), _, _),
            (_, _, .failure(let e), _), (_, _, _, .failure(let e)):
            return .failure(e)
    }
}

public func flatten<A, B, C, D, F, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>
) -> Result<(A, B, C, D, F), E> {
    switch (a, b, c, d, f) {
        case (.success(let a), .success(let b), .success(let c), .success(let d), .success(let f)):
            return .success((a, b, c, d, f))
        case (.failure(let e), _, _, _, _), (_, .failure(let e), _, _, _),
            (_, _, .failure(let e), _, _), (_, _, _, .failure(let e), _),
            (_, _, _, _, .failure(let e)):
            return .failure(e)
    }
}

public func flatten<A, B, C, D, F, G, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>,
    _ g: Result<G, E>
) -> Result<(A, B, C, D, F, G), E> {
    switch (a, b, c, d, f, g) {
        case (
            .success(let a), .success(let b), .success(let c), .success(let d), .success(let f),
            .success(let g)
        ):
            return .success((a, b, c, d, f, g))
        case (.failure(let e), _, _, _, _, _), (_, .failure(let e), _, _, _, _),
            (_, _, .failure(let e), _, _, _), (_, _, _, .failure(let e), _, _),
            (_, _, _, _, .failure(let e), _), (_, _, _, _, _, .failure(let e)):
            return .failure(e)
    }
}

public func flatten<A, B, C, D, F, G, H, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>,
    _ g: Result<G, E>,
    _ h: Result<H, E>
) -> Result<(A, B, C, D, F, G, H), E> {
    switch (a, b, c, d, f, g, h) {
        case (
            .success(let a), .success(let b), .success(let c), .success(let d), .success(let f),
            .success(let g), .success(let h)
        ):
            return .success((a, b, c, d, f, g, h))
        case (.failure(let e), _, _, _, _, _, _), (_, .failure(let e), _, _, _, _, _),
            (_, _, .failure(let e), _, _, _, _), (_, _, _, .failure(let e), _, _, _),
            (_, _, _, _, .failure(let e), _, _), (_, _, _, _, _, .failure(let e), _),
            (_, _, _, _, _, _, .failure(let e)):
            return .failure(e)
    }
}

public func flatten<A, B, C, D, F, G, H, I, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>,
    _ g: Result<G, E>,
    _ h: Result<H, E>,
    _ i: Result<I, E>
) -> Result<(A, B, C, D, F, G, H, I), E> {
    switch (a, b, c, d, f, g, h, i) {
        case (
            .success(let a), .success(let b), .success(let c), .success(let d), .success(let f),
            .success(let g), .success(let h), .success(let i)
        ):
            return .success((a, b, c, d, f, g, h, i))
        case (.failure(let e), _, _, _, _, _, _, _), (_, .failure(let e), _, _, _, _, _, _),
            (_, _, .failure(let e), _, _, _, _, _), (_, _, _, .failure(let e), _, _, _, _),
            (_, _, _, _, .failure(let e), _, _, _), (_, _, _, _, _, .failure(let e), _, _),
            (_, _, _, _, _, _, .failure(let e), _), (_, _, _, _, _, _, _, .failure(let e)):
            return .failure(e)
    }
}

public func flatten<A, B, C, D, F, G, H, I, J, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>,
    _ g: Result<G, E>,
    _ h: Result<H, E>,
    _ i: Result<I, E>,
    _ j: Result<J, E>
) -> Result<(A, B, C, D, F, G, H, I, J), E> {
    switch (a, b, c, d, f, g, h, i, j) {
        case (
            .success(let a), .success(let b), .success(let c), .success(let d), .success(let f),
            .success(let g), .success(let h), .success(let i), .success(let j)
        ):
            return .success((a, b, c, d, f, g, h, i, j))
        case (.failure(let e), _, _, _, _, _, _, _, _), (_, .failure(let e), _, _, _, _, _, _, _),
            (_, _, .failure(let e), _, _, _, _, _, _), (_, _, _, .failure(let e), _, _, _, _, _),
            (_, _, _, _, .failure(let e), _, _, _, _), (_, _, _, _, _, .failure(let e), _, _, _),
            (_, _, _, _, _, _, .failure(let e), _, _), (_, _, _, _, _, _, _, .failure(let e), _),
            (_, _, _, _, _, _, _, _, .failure(let e)):
            return .failure(e)
    }
}

public func flatten<A, B, C, D, F, G, H, I, J, K, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>,
    _ g: Result<G, E>,
    _ h: Result<H, E>,
    _ i: Result<I, E>,
    _ j: Result<J, E>,
    _ k: Result<K, E>
) -> Result<(A, B, C, D, F, G, H, I, J, K), E> {
    switch (a, b, c, d, f, g, h, i, j, k) {
        case (
            .success(let a), .success(let b), .success(let c), .success(let d), .success(let f),
            .success(let g), .success(let h), .success(let i), .success(let j), .success(let k)
        ):
            return .success((a, b, c, d, f, g, h, i, j, k))
        case (.failure(let e), _, _, _, _, _, _, _, _, _),
            (_, .failure(let e), _, _, _, _, _, _, _, _),
            (_, _, .failure(let e), _, _, _, _, _, _, _),
            (_, _, _, .failure(let e), _, _, _, _, _, _),
            (_, _, _, _, .failure(let e), _, _, _, _, _),
            (_, _, _, _, _, .failure(let e), _, _, _, _),
            (_, _, _, _, _, _, .failure(let e), _, _, _),
            (_, _, _, _, _, _, _, .failure(let e), _, _),
            (_, _, _, _, _, _, _, _, .failure(let e), _),
            (_, _, _, _, _, _, _, _, _, .failure(let e)):
            return .failure(e)
    }
}
