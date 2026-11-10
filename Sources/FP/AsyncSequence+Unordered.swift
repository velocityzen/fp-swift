@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension AsyncSequence where Self: Sendable, Failure == Never, Element: Sendable {
    /// Maps each element with an async transform, and gives the results in the
    /// order they finish.
    ///
    /// By default, each element is read and transformed when the consumer asks for
    /// the next value. With a larger `concurrency`, up to that many transforms run at
    /// the same time. A slow transform holds back only its own result. To keep the
    /// source order, use ``mapAsyncKeepOrder(concurrency:bufferLimit:_:)->AsyncStream<T>``.
    ///
    /// No new element is read while `concurrency` elements are being transformed or
    /// waiting for the consumer, so a slow consumer pauses the source. When the
    /// consumer stops, reading stops and running transforms are cancelled.
    ///
    /// - Parameters:
    ///   - concurrency: How many transforms may run at the same time. Must be 1 or
    ///     more. The default is 1.
    ///   - transform: The transform for one element.
    ///
    /// ```swift
    /// for await thumbnail in photos.mapAsyncUnordered(concurrency: 8, { photo in
    ///     await renderer.thumbnail(for: photo)
    /// }) {
    ///     gallery.insert(thumbnail)
    /// }
    /// ```
    @inlinable
    public func mapAsyncUnordered<T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Element) async -> T
    ) -> UnorderedMapSequence<Self, T> {
        UnorderedMapSequence(self, concurrency: concurrency, passthrough: nil) { element in
            await transform(element)
        }
    }

    /// Maps each element with an async transform that can drop it, and gives the
    /// results in the order they finish.
    ///
    /// A transform that returns nil drops the element. `passthrough` is for elements
    /// that need no async work, like cache hits: when it returns a value, that value
    /// is the result and `transform` is not called. It runs on the task that reads
    /// the source, so keep it fast. Otherwise it works like
    /// ``mapAsyncUnordered(concurrency:_:)->UnorderedMapSequence<Self,T>``.
    ///
    /// ```swift
    /// for await user in ids.compactMapAsyncUnordered(
    ///     concurrency: 8,
    ///     passthrough: { id in cache[id] },
    ///     { id in await api.user(id) }  // nil when the user is gone
    /// ) {
    ///     show(user)
    /// }
    /// ```
    @inlinable
    public func compactMapAsyncUnordered<T: Sendable>(
        concurrency: Int = 1,
        passthrough: (@Sendable (Element) -> T?)? = nil,
        _ transform: @concurrent @Sendable @escaping (Element) async -> T?
    ) -> UnorderedMapSequence<Self, T> {
        UnorderedMapSequence(
            self,
            concurrency: concurrency,
            passthrough: passthrough,
            transform: transform
        )
    }

    /// Maps the success value of each `Result` with an async transform, and gives
    /// the results in the order they finish.
    ///
    /// Failures pass through unchanged, as soon as they are read. Otherwise it works
    /// like ``mapAsyncUnordered(concurrency:_:)->UnorderedMapSequence<Self,T>``.
    @inlinable
    public func mapAsyncUnordered<Success: Sendable, E: Error, T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Success) async -> T
    ) -> UnorderedMapSequence<Self, Result<T, E>>
    where Element == Result<Success, E> {
        UnorderedMapSequence(
            self,
            concurrency: concurrency,
            passthrough: { $0.passthroughFailure() }
        ) { element in
            await element.mapAsync(transform)
        }
    }

    /// Maps the success value of each `Result` with an async transform that can
    /// fail, and gives the results in the order they finish.
    ///
    /// Failures pass through unchanged, as soon as they are read. A failure from the
    /// transform replaces the value it came from. Otherwise it works like
    /// ``mapAsyncUnordered(concurrency:_:)->UnorderedMapSequence<Self,T>``.
    @inlinable
    public func flatMapAsyncUnordered<Success: Sendable, E: Error, T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Success) async -> Result<T, E>
    ) -> UnorderedMapSequence<Self, Result<T, E>>
    where Element == Result<Success, E> {
        UnorderedMapSequence(
            self,
            concurrency: concurrency,
            passthrough: { $0.passthroughFailure() }
        ) { element in
            await element.flatMapAsync(transform)
        }
    }
}

/// An async sequence of the results of `mapAsyncUnordered` and its variants, in
/// the order they finish.
///
/// Each new iterator reads `Base` again from the start. Its transforms stop when
/// the iterator is released or its task is cancelled.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@frozen
public struct UnorderedMapSequence<Base: AsyncSequence & Sendable, Transformed: Sendable>:
    AsyncSequence, Sendable
where Base.Element: Sendable, Base.Failure == Never {
    public typealias Element = Transformed
    public typealias Failure = Never

    @usableFromInline let base: Base
    @usableFromInline let concurrency: Int
    @usableFromInline let passthrough: (@Sendable (Base.Element) -> Transformed?)?
    @usableFromInline let transform: @concurrent @Sendable (Base.Element) async -> Transformed?

    @inlinable
    init(
        _ base: Base,
        concurrency: Int,
        passthrough: (@Sendable (Base.Element) -> Transformed?)?,
        transform: @concurrent @Sendable @escaping (Base.Element) async -> Transformed?
    ) {
        precondition(concurrency >= 1, "concurrency must be at least 1")
        self.base = base
        self.concurrency = concurrency
        self.passthrough = passthrough
        self.transform = transform
    }

    @inlinable
    public func makeAsyncIterator() -> Iterator {
        if concurrency == 1 {
            // One at a time: each pull reads one element and transforms it in
            // the consumer's task, with no child tasks, buffers or read-ahead.
            return Iterator(
                sequential: SequentialMapIterator(
                    base.makeAsyncIterator(),
                    passthrough: passthrough,
                    transform: transform
                )
            )
        }
        return Iterator(
            pipeline: ConcurrentMapPipeline(
                source: base,
                concurrency: concurrency,
                passthrough: passthrough,
                transform: transform
            )
        )
    }

    @frozen
    public struct Iterator: AsyncIteratorProtocol {
        @usableFromInline var sequential: SequentialMapIterator<Base.AsyncIterator, Transformed>?
        @usableFromInline let pipeline:
            ConcurrentMapPipeline<Base.Element, CompletionOrder<Transformed>>?

        @inlinable
        init(sequential: SequentialMapIterator<Base.AsyncIterator, Transformed>) {
            self.sequential = sequential
            pipeline = nil
        }

        @inlinable
        init(pipeline: ConcurrentMapPipeline<Base.Element, CompletionOrder<Transformed>>) {
            sequential = nil
            self.pipeline = pipeline
        }

        @inlinable
        public mutating func next() async -> Transformed? {
            await next(isolation: #isolation)
        }

        @inlinable
        public mutating func next(isolation actor: isolated (any Actor)?) async -> Transformed? {
            guard let pipeline else {
                return await sequential?.next(isolation: actor)
            }

            return await withTaskCancellationHandler {
                await pipeline.next()
            } onCancel: {
                pipeline.cancel()
            }
        }
    }
}
