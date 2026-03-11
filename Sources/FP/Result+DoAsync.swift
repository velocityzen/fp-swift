import Foundation

// MARK: - Do Notation (Async)

public extension ResultDo {
    /// Binds the first async Result value in the chain.
    func bindAsync<A>(_ fn: () async -> Result<A, Failure>) async -> Result<A, Failure> {
        await fn()
    }

    /// Adds an async pure value as the first element in the chain.
    func letAsync<A>(_ fn: () async -> A) async -> Result<A, Failure> {
        .success(await fn())
    }
}

// MARK: - bindAsync / letAsync (1 → 2)

public extension Result {
    @_disfavoredOverload
    func bindAsync<B>(
        _ fn: (Success) async -> Result<B, Failure>
    ) async -> Result<(Success, B), Failure> {
        switch self {
            case .success(let a):
                return await fn(a).map { b in (a, b) }
            case .failure(let error):
                return .failure(error)
        }
    }

    @_disfavoredOverload
    func letAsync<B>(
        _ fn: (Success) async -> B
    ) async -> Result<(Success, B), Failure> {
        switch self {
            case .success(let a):
                return .success((a, await fn(a)))
            case .failure(let error):
                return .failure(error)
        }
    }
}

// MARK: - bindAsync / letAsync (2 → 3)

public extension Result {
    func bindAsync<A, B, C>(
        _ fn: (A, B) async -> Result<C, Failure>
    ) async -> Result<(A, B, C), Failure> where Success == (A, B) {
        switch self {
            case .success(let (a, b)):
                return await fn(a, b).map { c in (a, b, c) }
            case .failure(let error):
                return .failure(error)
        }
    }

    func letAsync<A, B, C>(
        _ fn: (A, B) async -> C
    ) async -> Result<(A, B, C), Failure> where Success == (A, B) {
        switch self {
            case .success(let (a, b)):
                return .success((a, b, await fn(a, b)))
            case .failure(let error):
                return .failure(error)
        }
    }
}

// MARK: - bindAsync / letAsync (3 → 4)

public extension Result {
    func bindAsync<A, B, C, D>(
        _ fn: (A, B, C) async -> Result<D, Failure>
    ) async -> Result<(A, B, C, D), Failure> where Success == (A, B, C) {
        switch self {
            case .success(let (a, b, c)):
                return await fn(a, b, c).map { d in (a, b, c, d) }
            case .failure(let error):
                return .failure(error)
        }
    }

    func letAsync<A, B, C, D>(
        _ fn: (A, B, C) async -> D
    ) async -> Result<(A, B, C, D), Failure> where Success == (A, B, C) {
        switch self {
            case .success(let (a, b, c)):
                return .success((a, b, c, await fn(a, b, c)))
            case .failure(let error):
                return .failure(error)
        }
    }
}

// MARK: - bindAsync / letAsync (4 → 5)

public extension Result {
    func bindAsync<A, B, C, D, E>(
        _ fn: (A, B, C, D) async -> Result<E, Failure>
    ) async -> Result<(A, B, C, D, E), Failure> where Success == (A, B, C, D) {
        switch self {
            case .success(let (a, b, c, d)):
                return await fn(a, b, c, d).map { e in (a, b, c, d, e) }
            case .failure(let error):
                return .failure(error)
        }
    }

    func letAsync<A, B, C, D, E>(
        _ fn: (A, B, C, D) async -> E
    ) async -> Result<(A, B, C, D, E), Failure> where Success == (A, B, C, D) {
        switch self {
            case .success(let (a, b, c, d)):
                return .success((a, b, c, d, await fn(a, b, c, d)))
            case .failure(let error):
                return .failure(error)
        }
    }
}

// MARK: - bindAsync / letAsync (5 → 6)

public extension Result {
    func bindAsync<A, B, C, D, E, F>(
        _ fn: (A, B, C, D, E) async -> Result<F, Failure>
    ) async -> Result<(A, B, C, D, E, F), Failure> where Success == (A, B, C, D, E) {
        switch self {
            case .success(let (a, b, c, d, e)):
                return await fn(a, b, c, d, e).map { f in (a, b, c, d, e, f) }
            case .failure(let error):
                return .failure(error)
        }
    }

    func letAsync<A, B, C, D, E, F>(
        _ fn: (A, B, C, D, E) async -> F
    ) async -> Result<(A, B, C, D, E, F), Failure> where Success == (A, B, C, D, E) {
        switch self {
            case .success(let (a, b, c, d, e)):
                return .success((a, b, c, d, e, await fn(a, b, c, d, e)))
            case .failure(let error):
                return .failure(error)
        }
    }
}

// MARK: - bindAsync / letAsync (6 → 7)

public extension Result {
    func bindAsync<A, B, C, D, E, F, G>(
        _ fn: (A, B, C, D, E, F) async -> Result<G, Failure>
    ) async -> Result<(A, B, C, D, E, F, G), Failure> where Success == (A, B, C, D, E, F) {
        switch self {
            case .success(let (a, b, c, d, e, f)):
                return await fn(a, b, c, d, e, f).map { g in (a, b, c, d, e, f, g) }
            case .failure(let error):
                return .failure(error)
        }
    }

    func letAsync<A, B, C, D, E, F, G>(
        _ fn: (A, B, C, D, E, F) async -> G
    ) async -> Result<(A, B, C, D, E, F, G), Failure> where Success == (A, B, C, D, E, F) {
        switch self {
            case .success(let (a, b, c, d, e, f)):
                return .success((a, b, c, d, e, f, await fn(a, b, c, d, e, f)))
            case .failure(let error):
                return .failure(error)
        }
    }
}

// MARK: - bindAsync / letAsync (7 → 8)

public extension Result {
    func bindAsync<A, B, C, D, E, F, G, H>(
        _ fn: (A, B, C, D, E, F, G) async -> Result<H, Failure>
    ) async -> Result<(A, B, C, D, E, F, G, H), Failure> where Success == (A, B, C, D, E, F, G) {
        switch self {
            case .success(let (a, b, c, d, e, f, g)):
                return await fn(a, b, c, d, e, f, g).map { h in (a, b, c, d, e, f, g, h) }
            case .failure(let error):
                return .failure(error)
        }
    }

    func letAsync<A, B, C, D, E, F, G, H>(
        _ fn: (A, B, C, D, E, F, G) async -> H
    ) async -> Result<(A, B, C, D, E, F, G, H), Failure> where Success == (A, B, C, D, E, F, G) {
        switch self {
            case .success(let (a, b, c, d, e, f, g)):
                return .success((a, b, c, d, e, f, g, await fn(a, b, c, d, e, f, g)))
            case .failure(let error):
                return .failure(error)
        }
    }
}

// MARK: - bindAsync / letAsync (8 → 9)

public extension Result {
    func bindAsync<A, B, C, D, E, F, G, H, I>(
        _ fn: (A, B, C, D, E, F, G, H) async -> Result<I, Failure>
    ) async -> Result<(A, B, C, D, E, F, G, H, I), Failure> where Success == (A, B, C, D, E, F, G, H) {
        switch self {
            case .success(let (a, b, c, d, e, f, g, h)):
                return await fn(a, b, c, d, e, f, g, h).map { i in (a, b, c, d, e, f, g, h, i) }
            case .failure(let error):
                return .failure(error)
        }
    }

    func letAsync<A, B, C, D, E, F, G, H, I>(
        _ fn: (A, B, C, D, E, F, G, H) async -> I
    ) async -> Result<(A, B, C, D, E, F, G, H, I), Failure> where Success == (A, B, C, D, E, F, G, H) {
        switch self {
            case .success(let (a, b, c, d, e, f, g, h)):
                return .success((a, b, c, d, e, f, g, h, await fn(a, b, c, d, e, f, g, h)))
            case .failure(let error):
                return .failure(error)
        }
    }
}

// MARK: - bindAsync / letAsync (9 → 10)

public extension Result {
    func bindAsync<A, B, C, D, E, F, G, H, I, J>(
        _ fn: (A, B, C, D, E, F, G, H, I) async -> Result<J, Failure>
    ) async -> Result<(A, B, C, D, E, F, G, H, I, J), Failure> where Success == (A, B, C, D, E, F, G, H, I) {
        switch self {
            case .success(let (a, b, c, d, e, f, g, h, i)):
                return await fn(a, b, c, d, e, f, g, h, i).map { j in (a, b, c, d, e, f, g, h, i, j) }
            case .failure(let error):
                return .failure(error)
        }
    }

    func letAsync<A, B, C, D, E, F, G, H, I, J>(
        _ fn: (A, B, C, D, E, F, G, H, I) async -> J
    ) async -> Result<(A, B, C, D, E, F, G, H, I, J), Failure> where Success == (A, B, C, D, E, F, G, H, I) {
        switch self {
            case .success(let (a, b, c, d, e, f, g, h, i)):
                return .success((a, b, c, d, e, f, g, h, i, await fn(a, b, c, d, e, f, g, h, i)))
            case .failure(let error):
                return .failure(error)
        }
    }
}
