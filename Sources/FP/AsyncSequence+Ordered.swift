@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension AsyncSequence where Self: Sendable, Failure == Never, Element: Sendable {
    /// Maps each element through an async transform while preserving source
    /// order. By default transforms run one at a time; pass a
    /// `maxConcurrency` greater than 1 to run them in parallel, bounding
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
    /// If the consumer stops iterating early, no further elements are read
    /// from the source and in-flight transforms are cancelled cooperatively.
    ///
    /// - Parameters:
    ///   - maxConcurrency: Maximum number of transforms in flight at once;
    ///     must be at least 1. Defaults to 1 — sequential execution. Pass a
    ///     larger value (or `.max`) to opt into parallelism.
    ///   - transform: The async transform applied to each element.
    ///
    /// ```swift
    /// for await image in references.mapAsyncKeepOrder(maxConcurrency: 8, { ref in
    ///     await downloader.fetch(ref)
    /// }) {
    ///     render(image)
    /// }
    /// ```
    public func mapAsyncKeepOrder<T: Sendable>(
        maxConcurrency: Int = 1,
        _ transform: @Sendable @escaping (Element) async -> T
    ) -> AsyncStream<T> {
        precondition(maxConcurrency >= 1, "maxConcurrency must be at least 1")
        return AsyncStream<T> { continuation in
            let root = Task {
                await withTaskGroup(of: Void.self) { group in
                    let (results, resultsCont) = AsyncStream.makeStream(
                        of: (index: Int, value: T).self
                    )
                    // One token per completed transform; consumed by the
                    // producer to keep at most `maxConcurrency` in flight.
                    let (tokens, tokensCont) = AsyncStream.makeStream(of: Void.self)

                    // Emitter: buffers out-of-order completions and yields
                    // them in source order.
                    group.addTask {
                        var pending: [Int: T] = [:]
                        var emitIndex = 0
                        for await result in results {
                            pending[result.index] = result.value
                            while let value = pending.removeValue(forKey: emitIndex) {
                                continuation.yield(value)
                                emitIndex += 1
                            }
                        }
                        continuation.finish()
                    }

                    // Producer: one child task per element, throttled by the
                    // completion tokens. Transforms are group children, so
                    // cancelling `root` cancels them cooperatively.
                    var tokenIterator = tokens.makeAsyncIterator()
                    var index = 0
                    var inFlight = 0
                    for await element in self {
                        if inFlight >= maxConcurrency {
                            _ = await tokenIterator.next()
                            inFlight -= 1
                        }
                        let currentIndex = index
                        index += 1
                        let added = group.addTaskUnlessCancelled {
                            let value = await transform(element)
                            resultsCont.yield((index: currentIndex, value: value))
                            tokensCont.yield(())
                        }
                        guard added else { break }
                        inFlight += 1
                    }
                    while inFlight > 0 {
                        _ = await tokenIterator.next()
                        inFlight -= 1
                    }
                    resultsCont.finish()
                }
            }
            continuation.onTermination = { _ in root.cancel() }
        }
    }

    /// Maps each `Result` element's success value through an async transform,
    /// preserving failures and source arrival order. Same concurrency model as
    /// ``mapAsyncKeepOrder(maxConcurrency:_:)`` — sequential by default,
    /// parallel up to `maxConcurrency` when you raise it.
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
        maxConcurrency: Int = 1,
        _ transform: @Sendable @escaping (Success) async -> T
    ) -> AsyncStream<Result<T, E>>
    where Element == Result<Success, E> {
        mapAsyncKeepOrder(maxConcurrency: maxConcurrency) { element in
            await element.mapAsync(transform)
        }
    }

    /// Maps each `Result` element's success value through a fallible async
    /// transform, preserving failures and source arrival order. Same
    /// concurrency model as ``mapAsyncKeepOrder(maxConcurrency:_:)`` —
    /// sequential by default, parallel up to `maxConcurrency` when you
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
        maxConcurrency: Int = 1,
        _ transform: @Sendable @escaping (Success) async -> Result<T, E>
    ) -> AsyncStream<Result<T, E>>
    where Element == Result<Success, E> {
        mapAsyncKeepOrder(maxConcurrency: maxConcurrency) { element in
            await element.flatMapAsync(transform)
        }
    }
}
