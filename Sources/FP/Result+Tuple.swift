import Foundation

// MARK: - Flatten tuple of Results into Result of tuple (sync)

// MARK: Arity 2

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
    flatten(a, b).flatMap { (a, b) in c.map { c in (a, b, c) } }
}

public func flatten<A, B, C, D, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>
) -> Result<(A, B, C, D), E> {
    flatten(a, b, c).flatMap { (a, b, c) in d.map { d in (a, b, c, d) } }
}

public func flatten<A, B, C, D, F, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>
) -> Result<(A, B, C, D, F), E> {
    flatten(a, b, c, d).flatMap { (a, b, c, d) in f.map { f in (a, b, c, d, f) } }
}

public func flatten<A, B, C, D, F, G, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>,
    _ g: Result<G, E>
) -> Result<(A, B, C, D, F, G), E> {
    flatten(a, b, c, d, f).flatMap { (a, b, c, d, f) in g.map { g in (a, b, c, d, f, g) } }
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
    flatten(a, b, c, d, f, g).flatMap { (a, b, c, d, f, g) in h.map { h in (a, b, c, d, f, g, h) } }
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
    flatten(a, b, c, d, f, g, h).flatMap { (a, b, c, d, f, g, h) in
        i.map { i in (a, b, c, d, f, g, h, i) }
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
    flatten(a, b, c, d, f, g, h, i).flatMap { (a, b, c, d, f, g, h, i) in
        j.map { j in (a, b, c, d, f, g, h, i, j) }
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
    flatten(a, b, c, d, f, g, h, i, j).flatMap { (a, b, c, d, f, g, h, i, j) in
        k.map { k in (a, b, c, d, f, g, h, i, j, k) }
    }
}

// MARK: - Flatten async Results in parallel

// MARK: Arity 2

public func flattenAsync<A: Sendable, B: Sendable, E: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<B, E>
) async -> Result<(A, B), E> {
    async let resultA = a()
    async let resultB = b()
    let (ra, rb) = await (resultA, resultB)
    return flatten(ra, rb)
}

// MARK: Arity 3

public func flattenAsync<A: Sendable, B: Sendable, C: Sendable, E: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<C, E>
) async -> Result<(A, B, C), E> {
    async let resultA = a()
    async let resultB = b()
    async let resultC = c()
    let (ra, rb, rc) = await (resultA, resultB, resultC)
    return flatten(ra, rb, rc)
}

// MARK: Arity 4

public func flattenAsync<A: Sendable, B: Sendable, C: Sendable, D: Sendable, E: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<D, E>
) async -> Result<(A, B, C, D), E> {
    async let resultA = a()
    async let resultB = b()
    async let resultC = c()
    async let resultD = d()
    let (ra, rb, rc, rd) = await (resultA, resultB, resultC, resultD)
    return flatten(ra, rb, rc, rd)
}

// MARK: Arity 5

public func flattenAsync<A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, E: Error>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<F, E>
) async -> Result<(A, B, C, D, F), E> {
    async let resultA = a()
    async let resultB = b()
    async let resultC = c()
    async let resultD = d()
    async let resultF = f()
    let (ra, rb, rc, rd, rf) = await (resultA, resultB, resultC, resultD, resultF)
    return flatten(ra, rb, rc, rd, rf)
}

// MARK: Arity 6

public func flattenAsync<
    A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, G: Sendable, E: Error
>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<F, E>,
    _ g: @Sendable @autoclosure @escaping () async -> Result<G, E>
) async -> Result<(A, B, C, D, F, G), E> {
    async let resultA = a()
    async let resultB = b()
    async let resultC = c()
    async let resultD = d()
    async let resultF = f()
    async let resultG = g()
    let (ra, rb, rc, rd, rf, rg) = await (resultA, resultB, resultC, resultD, resultF, resultG)
    return flatten(ra, rb, rc, rd, rf, rg)
}

// MARK: Arity 7

public func flattenAsync<
    A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, G: Sendable, H: Sendable,
    E: Error
>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<F, E>,
    _ g: @Sendable @autoclosure @escaping () async -> Result<G, E>,
    _ h: @Sendable @autoclosure @escaping () async -> Result<H, E>
) async -> Result<(A, B, C, D, F, G, H), E> {
    async let resultA = a()
    async let resultB = b()
    async let resultC = c()
    async let resultD = d()
    async let resultF = f()
    async let resultG = g()
    async let resultH = h()
    let (ra, rb, rc, rd, rf, rg, rh) = await (
        resultA, resultB, resultC, resultD, resultF, resultG, resultH
    )
    return flatten(ra, rb, rc, rd, rf, rg, rh)
}

// MARK: Arity 8

public func flattenAsync<
    A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, G: Sendable, H: Sendable,
    I: Sendable, E: Error
>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<F, E>,
    _ g: @Sendable @autoclosure @escaping () async -> Result<G, E>,
    _ h: @Sendable @autoclosure @escaping () async -> Result<H, E>,
    _ i: @Sendable @autoclosure @escaping () async -> Result<I, E>
) async -> Result<(A, B, C, D, F, G, H, I), E> {
    async let resultA = a()
    async let resultB = b()
    async let resultC = c()
    async let resultD = d()
    async let resultF = f()
    async let resultG = g()
    async let resultH = h()
    async let resultI = i()
    let (ra, rb, rc, rd, rf, rg, rh, ri) = await (
        resultA, resultB, resultC, resultD, resultF, resultG, resultH, resultI
    )
    return flatten(ra, rb, rc, rd, rf, rg, rh, ri)
}

// MARK: Arity 9

public func flattenAsync<
    A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, G: Sendable, H: Sendable,
    I: Sendable, J: Sendable, E: Error
>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<F, E>,
    _ g: @Sendable @autoclosure @escaping () async -> Result<G, E>,
    _ h: @Sendable @autoclosure @escaping () async -> Result<H, E>,
    _ i: @Sendable @autoclosure @escaping () async -> Result<I, E>,
    _ j: @Sendable @autoclosure @escaping () async -> Result<J, E>
) async -> Result<(A, B, C, D, F, G, H, I, J), E> {
    async let resultA = a()
    async let resultB = b()
    async let resultC = c()
    async let resultD = d()
    async let resultF = f()
    async let resultG = g()
    async let resultH = h()
    async let resultI = i()
    async let resultJ = j()
    let (ra, rb, rc, rd, rf, rg, rh, ri, rj) = await (
        resultA, resultB, resultC, resultD, resultF, resultG, resultH, resultI, resultJ
    )
    return flatten(ra, rb, rc, rd, rf, rg, rh, ri, rj)
}

// MARK: Arity 10

public func flattenAsync<
    A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, G: Sendable, H: Sendable,
    I: Sendable, J: Sendable, K: Sendable, E: Error
>(
    _ a: @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @Sendable @autoclosure @escaping () async -> Result<F, E>,
    _ g: @Sendable @autoclosure @escaping () async -> Result<G, E>,
    _ h: @Sendable @autoclosure @escaping () async -> Result<H, E>,
    _ i: @Sendable @autoclosure @escaping () async -> Result<I, E>,
    _ j: @Sendable @autoclosure @escaping () async -> Result<J, E>,
    _ k: @Sendable @autoclosure @escaping () async -> Result<K, E>
) async -> Result<(A, B, C, D, F, G, H, I, J, K), E> {
    async let resultA = a()
    async let resultB = b()
    async let resultC = c()
    async let resultD = d()
    async let resultF = f()
    async let resultG = g()
    async let resultH = h()
    async let resultI = i()
    async let resultJ = j()
    async let resultK = k()
    let (ra, rb, rc, rd, rf, rg, rh, ri, rj, rk) = await (
        resultA, resultB, resultC, resultD, resultF, resultG, resultH, resultI, resultJ, resultK
    )
    return flatten(ra, rb, rc, rd, rf, rg, rh, ri, rj, rk)
}
