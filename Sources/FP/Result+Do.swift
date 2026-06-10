// MARK: - Do Notation

/// Starting point for Result's do-notation chain.
///
/// Provides `bind` and `let` to begin a monadic computation that accumulates values
/// into a growing tuple, short-circuiting on the first failure.
///
/// ```swift
/// let result = ResultDo<MyError>()
///     .bind { getUser() }                             // Result<User, MyError>
///     .bind { user in getProfile(user) }              // Result<(User, Profile), MyError>
///     .let { _, profile in profile.name }             // Result<(User, Profile, String), MyError>
///     .map { user, _, name in "\(user.id): \(name)" } // Result<String, MyError>
/// ```
public struct ResultDo<Failure: Error> {
    /// Binds the first Result value in the chain.
    public func bind<A>(_ fn: () -> Result<A, Failure>) -> Result<A, Failure> {
        fn()
    }

    /// Adds a pure value as the first element in the chain.
    public func `let`<A>(_ fn: () -> A) -> Result<A, Failure> {
        .success(fn())
    }
}

public extension Result where Failure: Error {
    /// Starts a do-notation chain.
    static var Do: ResultDo<Failure> { ResultDo() }
}

// MARK: - bind / let (1 → 2)

public extension Result {
    /// Binds a new Result, accumulating the success value into a pair.
    @_disfavoredOverload
    func bind<B>(
        _ fn: (Success) -> Result<B, Failure>
    ) -> Result<(Success, B), Failure> {
        flatMap { a in fn(a).map { b in (a, b) } }
    }

    /// Adds a pure computed value, accumulating into a pair.
    @_disfavoredOverload
    func `let`<B>(
        _ fn: (Success) -> B
    ) -> Result<(Success, B), Failure> {
        map { a in (a, fn(a)) }
    }
}

// MARK: - bind / let (2 → 3)

public extension Result {
    func bind<A, B, C>(
        _ fn: (A, B) -> Result<C, Failure>
    ) -> Result<(A, B, C), Failure> where Success == (A, B) {
        flatMap { (a, b) in fn(a, b).map { c in (a, b, c) } }
    }

    func `let`<A, B, C>(
        _ fn: (A, B) -> C
    ) -> Result<(A, B, C), Failure> where Success == (A, B) {
        map { (a, b) in (a, b, fn(a, b)) }
    }
}

// MARK: - bind / let (3 → 4)

public extension Result {
    func bind<A, B, C, D>(
        _ fn: (A, B, C) -> Result<D, Failure>
    ) -> Result<(A, B, C, D), Failure> where Success == (A, B, C) {
        flatMap { (a, b, c) in fn(a, b, c).map { d in (a, b, c, d) } }
    }

    func `let`<A, B, C, D>(
        _ fn: (A, B, C) -> D
    ) -> Result<(A, B, C, D), Failure> where Success == (A, B, C) {
        map { (a, b, c) in (a, b, c, fn(a, b, c)) }
    }
}

// MARK: - bind / let (4 → 5)

public extension Result {
    func bind<A, B, C, D, E>(
        _ fn: (A, B, C, D) -> Result<E, Failure>
    ) -> Result<(A, B, C, D, E), Failure> where Success == (A, B, C, D) {
        flatMap { (a, b, c, d) in fn(a, b, c, d).map { e in (a, b, c, d, e) } }
    }

    func `let`<A, B, C, D, E>(
        _ fn: (A, B, C, D) -> E
    ) -> Result<(A, B, C, D, E), Failure> where Success == (A, B, C, D) {
        map { (a, b, c, d) in (a, b, c, d, fn(a, b, c, d)) }
    }
}

// MARK: - bind / let (5 → 6)

public extension Result {
    func bind<A, B, C, D, E, F>(
        _ fn: (A, B, C, D, E) -> Result<F, Failure>
    ) -> Result<(A, B, C, D, E, F), Failure> where Success == (A, B, C, D, E) {
        flatMap { (a, b, c, d, e) in fn(a, b, c, d, e).map { f in (a, b, c, d, e, f) } }
    }

    func `let`<A, B, C, D, E, F>(
        _ fn: (A, B, C, D, E) -> F
    ) -> Result<(A, B, C, D, E, F), Failure> where Success == (A, B, C, D, E) {
        map { (a, b, c, d, e) in (a, b, c, d, e, fn(a, b, c, d, e)) }
    }
}

// MARK: - bind / let (6 → 7)

public extension Result {
    func bind<A, B, C, D, E, F, G>(
        _ fn: (A, B, C, D, E, F) -> Result<G, Failure>
    ) -> Result<(A, B, C, D, E, F, G), Failure> where Success == (A, B, C, D, E, F) {
        flatMap { (a, b, c, d, e, f) in fn(a, b, c, d, e, f).map { g in (a, b, c, d, e, f, g) } }
    }

    func `let`<A, B, C, D, E, F, G>(
        _ fn: (A, B, C, D, E, F) -> G
    ) -> Result<(A, B, C, D, E, F, G), Failure> where Success == (A, B, C, D, E, F) {
        map { (a, b, c, d, e, f) in (a, b, c, d, e, f, fn(a, b, c, d, e, f)) }
    }
}

// MARK: - bind / let (7 → 8)

public extension Result {
    func bind<A, B, C, D, E, F, G, H>(
        _ fn: (A, B, C, D, E, F, G) -> Result<H, Failure>
    ) -> Result<(A, B, C, D, E, F, G, H), Failure> where Success == (A, B, C, D, E, F, G) {
        flatMap { (a, b, c, d, e, f, g) in
            fn(a, b, c, d, e, f, g).map { h in (a, b, c, d, e, f, g, h) }
        }
    }

    func `let`<A, B, C, D, E, F, G, H>(
        _ fn: (A, B, C, D, E, F, G) -> H
    ) -> Result<(A, B, C, D, E, F, G, H), Failure> where Success == (A, B, C, D, E, F, G) {
        map { (a, b, c, d, e, f, g) in (a, b, c, d, e, f, g, fn(a, b, c, d, e, f, g)) }
    }
}

// MARK: - bind / let (8 → 9)

public extension Result {
    func bind<A, B, C, D, E, F, G, H, I>(
        _ fn: (A, B, C, D, E, F, G, H) -> Result<I, Failure>
    ) -> Result<(A, B, C, D, E, F, G, H, I), Failure> where Success == (A, B, C, D, E, F, G, H) {
        flatMap { (a, b, c, d, e, f, g, h) in
            fn(a, b, c, d, e, f, g, h).map { i in (a, b, c, d, e, f, g, h, i) }
        }
    }

    func `let`<A, B, C, D, E, F, G, H, I>(
        _ fn: (A, B, C, D, E, F, G, H) -> I
    ) -> Result<(A, B, C, D, E, F, G, H, I), Failure> where Success == (A, B, C, D, E, F, G, H) {
        map { (a, b, c, d, e, f, g, h) in (a, b, c, d, e, f, g, h, fn(a, b, c, d, e, f, g, h)) }
    }
}

// MARK: - bind / let (9 → 10)

public extension Result {
    func bind<A, B, C, D, E, F, G, H, I, J>(
        _ fn: (A, B, C, D, E, F, G, H, I) -> Result<J, Failure>
    ) -> Result<(A, B, C, D, E, F, G, H, I, J), Failure>
    where Success == (A, B, C, D, E, F, G, H, I) {
        flatMap { (a, b, c, d, e, f, g, h, i) in
            fn(a, b, c, d, e, f, g, h, i).map { j in (a, b, c, d, e, f, g, h, i, j) }
        }
    }

    func `let`<A, B, C, D, E, F, G, H, I, J>(
        _ fn: (A, B, C, D, E, F, G, H, I) -> J
    ) -> Result<(A, B, C, D, E, F, G, H, I, J), Failure>
    where Success == (A, B, C, D, E, F, G, H, I) {
        map { (a, b, c, d, e, f, g, h, i) in
            (a, b, c, d, e, f, g, h, i, fn(a, b, c, d, e, f, g, h, i))
        }
    }
}
