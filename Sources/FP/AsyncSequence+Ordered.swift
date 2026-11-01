import Synchronization

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension AsyncSequence where Self: Sendable, Failure == Never, Element: Sendable {
    /// Maps each element through an async transform while preserving source
    /// order. By default transforms run one at a time; pass a
    /// `concurrency` greater than 1 to run them in parallel, bounding
    /// wall-clock time by the slowest element rather than the sum of all
    /// transforms.
    ///
    /// Results emit in source arrival order: a slow earlier transform holds
    /// back later faster ones, but each result is yielded as soon as the
    /// strict-order constraint allows.
    ///
    /// Use this when you want streaming, ordered emission of work — e.g., a
    /// provider that receives image references over SSE and wants to
    /// download them in parallel while preserving the order the provider
    /// sent them in.
    ///
    /// The stream applies backpressure: at most `concurrency` elements are
    /// being transformed or waiting to be consumed at any time, so a slow
    /// consumer pauses reading from the source instead of buffering results.
    /// With `concurrency: 1` nothing is read ahead — each element is read and
    /// transformed when the consumer asks for the next value.
    ///
    /// If the consumer stops iterating early, no further elements are read
    /// from the source and in-flight transforms are cancelled cooperatively.
    ///
    /// For an all-or-nothing parallel pass over a finite array, see
    /// `traverseAsync(concurrency:_:)` on `Array` instead.
    ///
    /// - Parameters:
    ///   - concurrency: Maximum number of transforms in flight at once;
    ///     must be at least 1. Defaults to 1 — sequential execution. Pass a
    ///     larger value (or `.max`) to opt into parallelism.
    ///   - transform: The async transform applied to each element.
    ///
    /// ```swift
    /// for await image in references.mapAsyncKeepOrder(concurrency: 8, { ref in
    ///     await downloader.fetch(ref)
    /// }) {
    ///     render(image)
    /// }
    /// ```
    @inlinable
    public func mapAsyncKeepOrder<T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Element) async -> T
    ) -> AsyncStream<T> {
        if concurrency == 1 {
            // Calls `transform` itself rather than through the closure that
            // makes its result optional for `keepOrderStream`, one async call
            // less per element.
            let source = SharedIterator(makeAsyncIterator())
            return AsyncStream(unfolding: {
                guard let element = await source.next() else {
                    return nil
                }
                return await transform(element)
            })
        }
        return keepOrderStream(concurrency: concurrency, passthrough: nil) { element in
            await transform(element)
        }
    }

    /// Maps each `Result` element's success value through an async transform,
    /// preserving failures and source arrival order. Same concurrency model as
    /// ``mapAsyncKeepOrder(concurrency:_:)->AsyncStream<T>`` — sequential by default,
    /// parallel up to `concurrency` when you raise it.
    ///
    /// Failures are not transformed — they pass through unchanged, emitted in
    /// their original position in the stream, without waiting for a worker.
    ///
    /// ```swift
    /// for await result in events.mapAsyncKeepOrder({ event in
    ///     await enrich(event)
    /// }) {
    ///     handle(result)
    /// }
    /// ```
    @inlinable
    public func mapAsyncKeepOrder<Success: Sendable, E: Error, T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Success) async -> T
    ) -> AsyncStream<Result<T, E>>
    where Element == Result<Success, E> {
        if concurrency == 1 {
            // Captures `transform` itself: going through `keepOrderStream`
            // allocates the closure that wraps it, one allocation per call.
            let source = SharedIterator(makeAsyncIterator())
            return AsyncStream(unfolding: {
                guard let element = await source.next() else {
                    return nil
                }
                return await element.mapAsync(transform)
            })
        }

        return keepOrderStream(concurrency: concurrency, passthrough: { $0.passthroughFailure() }) {
            element in
            await element.mapAsync(transform)
        }
    }

    /// Maps each `Result` element's success value through a fallible async
    /// transform, preserving failures and source arrival order. Same
    /// concurrency model as ``mapAsyncKeepOrder(concurrency:_:)->AsyncStream<T>`` —
    /// sequential by default, parallel up to `concurrency` when you
    /// raise it.
    ///
    /// Use this when each transform may fail. Source failures pass through
    /// unchanged; transform failures replace the success they originated from.
    ///
    /// ```swift
    /// for await result in events.flatMapAsyncKeepOrder({ event in
    ///     await validateAndEnrich(event)  // returns Result<Enriched, MyError>
    /// }) {
    ///     handle(result)
    /// }
    /// ```
    @inlinable
    public func flatMapAsyncKeepOrder<Success: Sendable, E: Error, T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Success) async -> Result<T, E>
    ) -> AsyncStream<Result<T, E>>
    where Element == Result<Success, E> {
        if concurrency == 1 {
            // Captures `transform` itself, as in the `mapAsyncKeepOrder`
            // above.
            let source = SharedIterator(makeAsyncIterator())
            return AsyncStream(unfolding: {
                guard let element = await source.next() else {
                    return nil
                }
                return await element.flatMapAsync(transform)
            })
        }

        return keepOrderStream(concurrency: concurrency, passthrough: { $0.passthroughFailure() }) {
            element in
            await element.flatMapAsync(transform)
        }
    }

    /// The stream every `KeepOrder` operator returns.
    @inlinable
    func keepOrderStream<T: Sendable>(
        concurrency: Int,
        passthrough: (@Sendable (Element) -> T?)?,
        _ transform: @concurrent @Sendable @escaping (Element) async -> T?
    ) -> AsyncStream<T> {
        precondition(concurrency >= 1, "concurrency must be at least 1")
        if concurrency == 1 {
            // Sequential: each pull reads one element and transforms it in
            // the consumer's task — no child tasks, no internal buffers, and
            // nothing is read ahead of the consumer.
            // The transform is called from the closure itself: a call
            // through `SequentialMapIterator` costs another async frame and
            // isolation check per element.
            let source = SharedIterator(makeAsyncIterator())
            return AsyncStream(unfolding: {
                while let element = await source.next() {
                    if let passthrough, let value = passthrough(element) {
                        return value
                    }

                    if let value = await transform(element) {
                        return value
                    }
                }
                return nil
            })
        }
        let pipeline = ConcurrentMapPipeline<Element, SourceOrder<T>>(
            source: self,
            concurrency: concurrency,
            passthrough: passthrough,
            transform: transform
        )
        return AsyncStream(
            unfolding: { await pipeline.next() },
            onCancel: { pipeline.cancel() }
        )
    }
}
