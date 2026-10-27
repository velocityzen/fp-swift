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
    public func mapAsyncKeepOrder<T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Element) async -> T
    ) -> AsyncStream<T> {
        precondition(concurrency >= 1, "concurrency must be at least 1")
        if concurrency == 1 {
            // Sequential: each pull reads one element and transforms it in
            // the consumer's task — no child tasks, no internal buffers, and
            // nothing is read ahead of the consumer.
            let source = SourceIterator(makeAsyncIterator())
            return AsyncStream(unfolding: {
                guard let element = await source.next() else { return nil }
                return await transform(element)
            })
        }
        let pipeline = KeepOrderPipeline(
            source: self,
            concurrency: concurrency,
            transform: transform
        )
        return AsyncStream(
            unfolding: { await pipeline.next() },
            onCancel: { pipeline.cancel() }
        )
    }

    /// Maps each `Result` element's success value through an async transform,
    /// preserving failures and source arrival order. Same concurrency model as
    /// ``mapAsyncKeepOrder(concurrency:_:)->AsyncStream<T>`` — sequential by default,
    /// parallel up to `concurrency` when you raise it.
    ///
    /// Failures are not transformed — they pass through unchanged, emitted in
    /// their original position in the stream.
    ///
    /// ```swift
    /// for await result in events.mapAsyncKeepOrder({ event in
    ///     await enrich(event)
    /// }) {
    ///     handle(result)
    /// }
    /// ```
    public func mapAsyncKeepOrder<Success: Sendable, E: Error, T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Success) async -> T
    ) -> AsyncStream<Result<T, E>>
    where Element == Result<Success, E> {
        mapAsyncKeepOrder(concurrency: concurrency) { element in
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
    public func flatMapAsyncKeepOrder<Success: Sendable, E: Error, T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Success) async -> Result<T, E>
    ) -> AsyncStream<Result<T, E>>
    where Element == Result<Success, E> {
        mapAsyncKeepOrder(concurrency: concurrency) { element in
            await element.flatMapAsync(transform)
        }
    }
}

/// Shares a source iterator with the `AsyncStream(unfolding:)` closure.
///
/// `@unchecked Sendable`: an `AsyncStream` has a single consumer, so `next()`
/// is never called concurrently.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
private final class SourceIterator<Base: AsyncIteratorProtocol>: @unchecked Sendable
where Base.Failure == Never {
    private var base: Base

    init(_ base: Base) {
        self.base = base
    }

    func next() async -> Base.Element? {
        await base.next(isolation: #isolation)
    }
}

/// The parallel engine behind `mapAsyncKeepOrder(concurrency:_:)`.
///
/// A slot is taken when an element starts and given back only when the
/// consumer takes its result, so at most `concurrency` elements are running
/// or waiting to be consumed. A slow consumer therefore pauses the source,
/// and a slow early element bounds how many later results wait behind it.
///
/// `@unchecked Sendable`: `results` is read only by the stream's single
/// consumer, through `next()`.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
private final class KeepOrderPipeline<T: Sendable>: @unchecked Sendable {
    private var results: AsyncStream<T>.Iterator
    private let slots: AsyncStream<Void>.Continuation
    private let root: Task<Void, Never>

    init<Source: AsyncSequence & Sendable>(
        source: Source,
        concurrency: Int,
        transform: @concurrent @Sendable @escaping (Source.Element) async -> T
    ) where Source.Failure == Never, Source.Element: Sendable {
        let (ordered, orderedCont) = AsyncStream.makeStream(of: T.self)
        // One element per slot the consumer gives back.
        let (freed, freedCont) = AsyncStream.makeStream(of: Void.self)
        results = ordered.makeAsyncIterator()
        slots = freedCont

        root = Task {
            await withTaskGroup(of: Void.self) { group in
                let (completed, completedCont) = AsyncStream.makeStream(
                    of: (index: Int, value: T).self
                )

                // Emitter: buffers out-of-order completions and yields them
                // in source order. At most `concurrency` are ever buffered.
                group.addTask {
                    var pending: [Int: T] = [:]
                    pending.reserveCapacity(min(concurrency, 64))
                    var emitIndex = 0
                    for await result in completed {
                        pending[result.index] = result.value
                        while let value = pending.removeValue(forKey: emitIndex) {
                            orderedCont.yield(value)
                            emitIndex += 1
                        }
                    }
                    orderedCont.finish()
                }

                // Producer: one child task per element, admitted only while
                // a slot is free. Transforms are children of a nested group,
                // so cancelling `root` cancels them cooperatively, and the
                // group returning means every admitted transform finished.
                await withTaskGroup(of: Void.self) { transforms in
                    var freedIterator = freed.makeAsyncIterator()
                    var index = 0
                    var taken = 0
                    for await element in source {
                        if taken >= concurrency {
                            _ = await freedIterator.next()
                            taken -= 1
                        }
                        // Check the task's own flag, not just the group's:
                        // after cancellation the slot wait above returns at
                        // once, and the group's cancel record can lag behind
                        // (observed on the macOS 15 runtime), so
                        // addTaskUnlessCancelled alone would then admit
                        // another element.
                        if Task.isCancelled { break }
                        let currentIndex = index
                        index += 1
                        let added = transforms.addTaskUnlessCancelled {
                            let value = await transform(element)
                            completedCont.yield((index: currentIndex, value: value))
                        }
                        guard added else { break }
                        taken += 1
                    }
                }
                // Lets the emitter drain what is left and finish the stream.
                completedCont.finish()
            }
        }
    }

    deinit {
        // The consumer dropped the stream without cancelling its task.
        root.cancel()
    }

    func next() async -> T? {
        guard let value = await results.next(isolation: #isolation) else {
            return nil
        }
        slots.yield(())
        return value
    }

    func cancel() {
        root.cancel()
    }
}
