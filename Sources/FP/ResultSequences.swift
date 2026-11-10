// MARK: - Sequences returned by the AsyncSequence Result operators

// The standard `AsyncMapSequence` and `AsyncCompactMapSequence` hide their
// initializers and stored properties from client code. So each element costs
// runtime calls and a closure call the optimizer cannot see into. These types
// are inlinable and frozen (also in a library-evolution build), so a transform
// at the call site compiles into the loop that reads the sequence.

/// An async sequence that transforms each element of `Base` with a sync closure.
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

/// An async sequence that transforms each element of `Base` with an async
/// closure. The closure runs on the actor that reads the sequence.
///
/// `mapAsync`, `mapErrorAsync`, `flatMapAsync`, `tapAsync` and `tapErrorAsync`
/// on an async sequence of `Result`s return it. It throws only what `Base`
/// throws.
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

/// An async sequence that transforms each element of `Base` with a sync
/// closure, and drops nil results.
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
