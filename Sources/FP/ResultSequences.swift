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

/// An async sequence that passes the elements of `Base` through, and ends with one failure
/// element when the task that reads it is cancelled.
///
/// `failOnCancellation(with:)` on an async sequence of `Result`s returns it. It throws only what
/// `Base` throws.
@frozen
public struct FailOnCancellationSequence<Base: AsyncSequence>: AsyncSequence {
    public typealias Element = Base.Element
    public typealias Failure = Base.Failure

    @usableFromInline let base: Base
    @usableFromInline let failure: Base.Element

    @inlinable
    init(_ base: Base, failure: Base.Element) {
        self.base = base
        self.failure = failure
    }

    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base.makeAsyncIterator(), failure: failure)
    }

    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline var base: Base.AsyncIterator
        @usableFromInline let failure: Base.Element
        @usableFromInline var finished = false

        @inlinable
        init(_ base: Base.AsyncIterator, failure: Base.Element) {
            self.base = base
            self.failure = failure
        }

        @inlinable
        public mutating func next() async throws(Base.Failure) -> Base.Element? {
            try await next(isolation: #isolation)
        }

        @inlinable
        public mutating func next(
            isolation actor: isolated (any Actor)?
        ) async throws(Base.Failure) -> Base.Element? {
            guard !finished else { return nil }
            if !Task.isCancelled, let element = try await base.next(isolation: actor) {
                return element
            }
            finished = true
            return Task.isCancelled ? failure : nil
        }
    }
}

extension FailOnCancellationSequence: Sendable where Base: Sendable, Base.Element: Sendable {}
extension FailOnCancellationSequence.Iterator: Sendable
where Base.AsyncIterator: Sendable, Base.Element: Sendable {}

/// An async sequence that wraps each element of `Base` in `.success`, and gives the error that
/// `Base` throws as its last element, a `.failure`.
///
/// `asResults()` on an async sequence returns it. It never throws.
@frozen
public struct ResultsSequence<Base: AsyncSequence>: AsyncSequence {
    public typealias Element = Result<Base.Element, Base.Failure>
    public typealias Failure = Never

    @usableFromInline let base: Base

    @inlinable
    init(_ base: Base) {
        self.base = base
    }

    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base.makeAsyncIterator())
    }

    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline var base: Base.AsyncIterator
        @usableFromInline var finished = false

        @inlinable
        init(_ base: Base.AsyncIterator) {
            self.base = base
        }

        @inlinable
        public mutating func next() async -> Element? {
            await next(isolation: #isolation)
        }

        @inlinable
        public mutating func next(isolation actor: isolated (any Actor)?) async -> Element? {
            guard !finished else { return nil }
            do throws(Base.Failure) {
                if let element = try await base.next(isolation: actor) {
                    return .success(element)
                }
            } catch {
                finished = true
                return .failure(error)
            }
            finished = true
            return nil
        }
    }
}

extension ResultsSequence: Sendable where Base: Sendable {}
extension ResultsSequence.Iterator: Sendable where Base.AsyncIterator: Sendable {}

/// An async sequence of the values of `Base`'s `Result` elements, which throws the first failure.
///
/// `get()` on an async sequence of `Result`s that can't throw returns it. After the failure, it
/// ends and does not read `Base` again.
@frozen
public struct GetSequence<Base: AsyncSequence, Success, Failure: Error>: AsyncSequence
where Base.Element == Result<Success, Failure>, Base.Failure == Never {
    public typealias Element = Success

    @usableFromInline let base: Base

    @inlinable
    init(_ base: Base) {
        self.base = base
    }

    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base.makeAsyncIterator())
    }

    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline var base: Base.AsyncIterator
        @usableFromInline var finished = false

        @inlinable
        init(_ base: Base.AsyncIterator) {
            self.base = base
        }

        @inlinable
        public mutating func next() async throws(Failure) -> Success? {
            try await next(isolation: #isolation)
        }

        @inlinable
        public mutating func next(
            isolation actor: isolated (any Actor)?
        ) async throws(Failure) -> Success? {
            guard !finished, let element = await base.next(isolation: actor) else {
                finished = true
                return nil
            }
            switch element {
                case .success(let value):
                    return value
                case .failure(let error):
                    finished = true
                    throw error
            }
        }
    }
}

extension GetSequence: Sendable where Base: Sendable {}
extension GetSequence.Iterator: Sendable where Base.AsyncIterator: Sendable {}

/// An async sequence of `Base`'s `Result` elements up to and including the first failure, or the
/// first success.
///
/// `untilFailure()` and `untilSuccess()` on an async sequence of `Result`s return it. After that
/// element, it ends and does not read `Base` again. It throws only what `Base` throws.
@frozen
public struct UntilSequence<Base: AsyncSequence, Success, ElementFailure: Error>: AsyncSequence
where Base.Element == Result<Success, ElementFailure> {
    public typealias Element = Base.Element
    public typealias Failure = Base.Failure

    @usableFromInline let base: Base
    @usableFromInline let stopsOnSuccess: Bool

    @inlinable
    init(_ base: Base, stopsOnSuccess: Bool) {
        self.base = base
        self.stopsOnSuccess = stopsOnSuccess
    }

    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base.makeAsyncIterator(), stopsOnSuccess: stopsOnSuccess)
    }

    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline var base: Base.AsyncIterator
        @usableFromInline let stopsOnSuccess: Bool
        @usableFromInline var finished = false

        @inlinable
        init(_ base: Base.AsyncIterator, stopsOnSuccess: Bool) {
            self.base = base
            self.stopsOnSuccess = stopsOnSuccess
        }

        @inlinable
        public mutating func next() async throws(Base.Failure) -> Base.Element? {
            try await next(isolation: #isolation)
        }

        @inlinable
        public mutating func next(
            isolation actor: isolated (any Actor)?
        ) async throws(Base.Failure) -> Base.Element? {
            guard !finished else { return nil }
            guard let element = try await base.next(isolation: actor) else {
                finished = true
                return nil
            }
            switch element {
                case .success:
                    if stopsOnSuccess { finished = true }
                case .failure:
                    if !stopsOnSuccess { finished = true }
            }
            return element
        }
    }
}

extension UntilSequence: Sendable where Base: Sendable {}
extension UntilSequence.Iterator: Sendable where Base.AsyncIterator: Sendable {}
