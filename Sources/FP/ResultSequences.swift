// MARK: - Sequences returned by the AsyncSequence Result operators

// The standard library's `AsyncMapSequence` and `AsyncCompactMapSequence`
// keep their initializers and stored properties out of client code, so each
// element costs calls into the runtime and an indirect call of a closure the
// optimizer cannot see. These sequences are inlinable throughout, and frozen
// so they stay that way in a library-evolution build: a transform written at
// the call site compiles into the loop that iterates the sequence.

/// An async sequence that transforms each element of `Base` with a
/// synchronous closure, run wherever the sequence is iterated.
///
/// `map`, `mapError`, `flatMap`, `tap` and `tapError` on an async sequence of
/// `Result`s return it. It throws only what `Base` throws.
@frozen
public struct ResultMapSequence<Base: AsyncSequence, Transformed>: AsyncSequence {
    public typealias Element = Transformed
    public typealias Failure = Base.Failure

    @usableFromInline let base: Base
    @usableFromInline let transform: @Sendable (Base.Element) -> Transformed

    @inlinable
    init(_ base: Base, transform: @escaping @Sendable (Base.Element) -> Transformed) {
        self.base = base
        self.transform = transform
    }

    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base.makeAsyncIterator(), transform: transform)
    }

    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline var base: Base.AsyncIterator
        @usableFromInline let transform: @Sendable (Base.Element) -> Transformed

        @inlinable
        init(
            _ base: Base.AsyncIterator,
            transform: @escaping @Sendable (Base.Element) -> Transformed
        ) {
            self.base = base
            self.transform = transform
        }

        @inlinable
        public mutating func next() async throws(Base.Failure) -> Transformed? {
            try await next(isolation: #isolation)
        }

        @inlinable
        public mutating func next(
            isolation actor: isolated (any Actor)?
        ) async throws(Base.Failure) -> Transformed? {
            guard let element = try await base.next(isolation: actor) else { return nil }
            return transform(element)
        }
    }
}

extension ResultMapSequence: Sendable where Base: Sendable {}
extension ResultMapSequence.Iterator: Sendable where Base.AsyncIterator: Sendable {}

/// An async sequence that transforms each element of `Base` with an
/// asynchronous closure, run on the actor that iterates the sequence like
/// the closures of the other async combinators.
///
/// `mapAsync`, `mapErrorAsync`, `flatMapAsync`, `tapAsync` and
/// `tapErrorAsync` on an async sequence of `Result`s return it. It throws
/// only what `Base` throws.
@frozen
public struct ResultMapAsyncSequence<Base: AsyncSequence, Transformed>: AsyncSequence {
    public typealias Element = Transformed
    public typealias Failure = Base.Failure

    @usableFromInline let base: Base
    @usableFromInline let transform: @Sendable (Base.Element) async -> Transformed

    @inlinable
    init(_ base: Base, transform: @escaping @Sendable (Base.Element) async -> Transformed) {
        self.base = base
        self.transform = transform
    }

    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base.makeAsyncIterator(), transform: transform)
    }

    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline var base: Base.AsyncIterator
        @usableFromInline let transform: @Sendable (Base.Element) async -> Transformed

        @inlinable
        init(
            _ base: Base.AsyncIterator,
            transform: @escaping @Sendable (Base.Element) async -> Transformed
        ) {
            self.base = base
            self.transform = transform
        }

        @inlinable
        public mutating func next() async throws(Base.Failure) -> Transformed? {
            try await next(isolation: #isolation)
        }

        @inlinable
        public mutating func next(
            isolation actor: isolated (any Actor)?
        ) async throws(Base.Failure) -> Transformed? {
            guard let element = try await base.next(isolation: actor) else { return nil }
            return await transform(element)
        }
    }
}

extension ResultMapAsyncSequence: Sendable where Base: Sendable {}
extension ResultMapAsyncSequence.Iterator: Sendable where Base.AsyncIterator: Sendable {}

/// An async sequence of the non-nil results of transforming each element of
/// `Base` with a synchronous closure, run wherever the sequence is iterated.
///
/// `successes` and `failures` on an async sequence of `Result`s return it. It
/// throws only what `Base` throws.
@frozen
public struct ResultCompactMapSequence<Base: AsyncSequence, Transformed>: AsyncSequence {
    public typealias Element = Transformed
    public typealias Failure = Base.Failure

    @usableFromInline let base: Base
    @usableFromInline let transform: @Sendable (Base.Element) -> Transformed?

    @inlinable
    init(_ base: Base, transform: @escaping @Sendable (Base.Element) -> Transformed?) {
        self.base = base
        self.transform = transform
    }

    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base.makeAsyncIterator(), transform: transform)
    }

    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline var base: Base.AsyncIterator
        @usableFromInline let transform: @Sendable (Base.Element) -> Transformed?

        @inlinable
        init(
            _ base: Base.AsyncIterator,
            transform: @escaping @Sendable (Base.Element) -> Transformed?
        ) {
            self.base = base
            self.transform = transform
        }

        @inlinable
        public mutating func next() async throws(Base.Failure) -> Transformed? {
            try await next(isolation: #isolation)
        }

        @inlinable
        public mutating func next(
            isolation actor: isolated (any Actor)?
        ) async throws(Base.Failure) -> Transformed? {
            while let element = try await base.next(isolation: actor) {
                if let value = transform(element) { return value }
            }
            return nil
        }
    }
}

extension ResultCompactMapSequence: Sendable where Base: Sendable {}
extension ResultCompactMapSequence.Iterator: Sendable where Base.AsyncIterator: Sendable {}
