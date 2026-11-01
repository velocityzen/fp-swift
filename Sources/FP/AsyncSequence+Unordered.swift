@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension AsyncSequence where Self: Sendable, Failure == Never, Element: Sendable {
    /// Maps each element through an async transform, emitting each result as
    /// soon as its transform finishes. By default transforms run one at a
    /// time; pass a `concurrency` greater than 1 to run them in parallel.
    ///
    /// Results emit in the order the transforms finish, so a slow element
    /// holds back nothing but itself. Use
    /// ``mapAsyncKeepOrder(concurrency:_:)->AsyncStream<T>`` when the results
    /// must keep source order.
    ///
    /// The sequence applies backpressure: at most `concurrency` elements are
    /// being transformed or waiting to be consumed at any time, so a slow
    /// consumer pauses reading from the source instead of buffering results.
    /// With `concurrency: 1` nothing is read ahead — each element is read and
    /// transformed when the consumer asks for the next value.
    ///
    /// If the consumer stops iterating early, no further elements are read
    /// from the source and in-flight transforms are cancelled cooperatively.
    /// Each iteration of the returned sequence reads the source afresh.
    ///
    /// - Parameters:
    ///   - concurrency: Maximum number of transforms in flight at once;
    ///     must be at least 1. Defaults to 1 — sequential execution. Pass a
    ///     larger value (or `.max`) to opt into parallelism.
    ///   - transform: The async transform applied to each element.
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

    /// Maps each element through an async transform that may drop it,
    /// emitting each non-nil result as soon as its transform finishes. Same
    /// concurrency model as ``mapAsyncUnordered(concurrency:_:)->UnorderedMapSequence<Self,T>``
    /// — sequential by default, parallel up to `concurrency` when you raise
    /// it. A dropped element frees its slot at once.
    ///
    /// Pass `passthrough` for elements that need no async work, such as cache
    /// hits: an element it maps to a value is emitted as that value without
    /// calling `transform`. It runs on the task that reads the source, so it
    /// should be quick; passed-through elements count toward `concurrency`
    /// until the consumer takes them, but never wait for a transform to
    /// finish.
    ///
    /// - Parameters:
    ///   - concurrency: Maximum number of elements being transformed or
    ///     waiting to be consumed at once; must be at least 1.
    ///   - passthrough: Maps an element straight to its result, or returns
    ///     nil to have `transform` run on it.
    ///   - transform: The async transform applied to each element; returns
    ///     nil to drop it.
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

    /// Maps each `Result` element's success value through an async transform,
    /// emitting each result as soon as it is ready. Same concurrency model as
    /// ``mapAsyncUnordered(concurrency:_:)->UnorderedMapSequence<Self,T>`` —
    /// sequential by default, parallel up to `concurrency` when you raise it.
    ///
    /// Failures are not transformed — they pass through unchanged, emitted as
    /// soon as they are read, without waiting for a worker.
    ///
    /// ```swift
    /// for await result in events.mapAsyncUnordered(concurrency: 4, { event in
    ///     await enrich(event)
    /// }) {
    ///     handle(result)
    /// }
    /// ```
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

    /// Maps each `Result` element's success value through a fallible async
    /// transform, emitting each result as soon as it is ready. Same
    /// concurrency model as ``mapAsyncUnordered(concurrency:_:)->UnorderedMapSequence<Self,T>``
    /// — sequential by default, parallel up to `concurrency` when you raise
    /// it.
    ///
    /// Source failures pass through unchanged, without waiting for a worker;
    /// transform failures replace the success they originated from.
    ///
    /// ```swift
    /// for await result in events.flatMapAsyncUnordered(concurrency: 4, { event in
    ///     await validateAndEnrich(event)  // returns Result<Enriched, MyError>
    /// }) {
    ///     handle(result)
    /// }
    /// ```
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

/// An async sequence of the results of transforming each element of `Base`
/// with an async closure, up to `concurrency` at a time, in the order the
/// transforms finish.
///
/// `mapAsyncUnordered`, `compactMapAsyncUnordered` and
/// `flatMapAsyncUnordered` return it. Each iterator reads `Base` afresh, and
/// above `concurrency: 1` runs its own reader and workers, which stop when
/// the iterator is released or the task iterating it is cancelled.
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
            // Sequential: each pull reads one element and transforms it in
            // the consumer's task — no child tasks, no internal buffers, and
            // nothing is read ahead of the consumer.
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
