import Foundation

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
    public func bind<A>(_ f: () -> Result<A, Failure>) -> Result<A, Failure> {
        f()
    }

    /// Adds a pure value as the first element in the chain.
    public func `let`<A>(_ f: () -> A) -> Result<A, Failure> {
        .success(f())
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
        _ f: (Success) -> Result<B, Failure>
    ) -> Result<(Success, B), Failure> {
        flatMap { a in f(a).map { b in (a, b) } }
    }

    /// Adds a pure computed value, accumulating into a pair.
    @_disfavoredOverload
    func `let`<B>(
        _ f: (Success) -> B
    ) -> Result<(Success, B), Failure> {
        map { a in (a, f(a)) }
    }
}

// MARK: - bind / let (2 → 3)

public extension Result {
    func bind<A, B, C>(
        _ f: (A, B) -> Result<C, Failure>
    ) -> Result<(A, B, C), Failure> where Success == (A, B) {
        flatMap { (a, b) in f(a, b).map { c in (a, b, c) } }
    }

    func `let`<A, B, C>(
        _ f: (A, B) -> C
    ) -> Result<(A, B, C), Failure> where Success == (A, B) {
        map { (a, b) in (a, b, f(a, b)) }
    }
}

// MARK: - bind / let (3 → 4)

public extension Result {
    func bind<A, B, C, D>(
        _ f: (A, B, C) -> Result<D, Failure>
    ) -> Result<(A, B, C, D), Failure> where Success == (A, B, C) {
        flatMap { (a, b, c) in f(a, b, c).map { d in (a, b, c, d) } }
    }

    func `let`<A, B, C, D>(
        _ f: (A, B, C) -> D
    ) -> Result<(A, B, C, D), Failure> where Success == (A, B, C) {
        map { (a, b, c) in (a, b, c, f(a, b, c)) }
    }
}

// MARK: - bind / let (4 → 5)

public extension Result {
    func bind<A, B, C, D, E>(
        _ f: (A, B, C, D) -> Result<E, Failure>
    ) -> Result<(A, B, C, D, E), Failure> where Success == (A, B, C, D) {
        flatMap { (a, b, c, d) in f(a, b, c, d).map { e in (a, b, c, d, e) } }
    }

    func `let`<A, B, C, D, E>(
        _ f: (A, B, C, D) -> E
    ) -> Result<(A, B, C, D, E), Failure> where Success == (A, B, C, D) {
        map { (a, b, c, d) in (a, b, c, d, f(a, b, c, d)) }
    }
}
