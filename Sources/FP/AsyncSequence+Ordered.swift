import Synchronization

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension AsyncSequence where Self: Sendable, Failure == Never, Element: Sendable {
    /// Maps each element with an async transform, and keeps the source order.
    ///
    /// By default, each element is read and transformed when the consumer asks for
    /// the next value. With a larger `concurrency`, up to that many transforms run at
    /// the same time. A slow transform holds back the results after it, but not the
    /// work: later elements are still transformed, and their results wait.
    ///
    /// No new element is read while `concurrency` elements are being transformed or
    /// waiting for the consumer, so a slow consumer pauses the source. When the
    /// consumer stops, reading stops and running transforms are cancelled.
    ///
    /// - Parameters:
    ///   - concurrency: How many transforms may run at the same time. Must be 1 or
    ///     more. The default is 1.
    ///   - bufferLimit: How many results may wait for an earlier, slower element.
    ///     Must be 0 or more. The default is `.max`, no limit. A limit below
    ///     `concurrency - 1` also lowers how many transforms run at the same time.
    ///   - transform: The transform for one element.
    ///
    /// ```swift
    /// let images = refs.mapAsyncOrdered(concurrency: 8) { ref in
    ///     await downloader.fetch(ref)
    /// }
    ///
    /// for await image in images {
    ///     render(image)
    /// }
    /// ```
    @inlinable
    public func mapAsyncOrdered<T: Sendable>(
        concurrency: Int = 1,
        bufferLimit: Int = .max,
        _ transform: @concurrent @Sendable @escaping (Element) async -> T
    ) -> AsyncStream<T> {
        precondition(bufferLimit >= 0, "bufferLimit must be at least 0")
        if concurrency == 1 {
            // Calls `transform` directly. Going through
            // `compactMapAsyncOrdered` costs one more async call per element.
            let source = SharedIterator(makeAsyncIterator())
            return AsyncStream(unfolding: {
                guard let element = await source.next() else {
                    return nil
                }
                return await transform(element)
            })
        }

        return compactMapAsyncOrdered(
            concurrency: concurrency,
            bufferLimit: bufferLimit
        ) { element in
            await transform(element)
        }
    }

    /// Maps the success value of each `Result` with an async transform, and keeps
    /// the source order.
    ///
    /// Failures pass through unchanged, in their place. Otherwise it works like
    /// ``mapAsyncOrdered(concurrency:bufferLimit:_:)->AsyncStream<T>``.
    @inlinable
    public func mapAsyncOrdered<Success: Sendable, E: Error, T: Sendable>(
        concurrency: Int = 1,
        bufferLimit: Int = .max,
        _ transform: @concurrent @Sendable @escaping (Success) async -> T
    ) -> AsyncStream<Result<T, E>>
    where Element == Result<Success, E> {
        precondition(bufferLimit >= 0, "bufferLimit must be at least 0")
        if concurrency == 1 {
            // Captures `transform` directly. Going through
            // `compactMapAsyncOrdered` allocates a closure around it.
            let source = SharedIterator(makeAsyncIterator())
            return AsyncStream(unfolding: {
                guard let element = await source.next() else {
                    return nil
                }
                return await element.mapAsync(transform)
            })
        }

        return compactMapAsyncOrdered(
            concurrency: concurrency,
            bufferLimit: bufferLimit,
            passthrough: { $0.passthroughFailure() }
        ) { element in
            await element.mapAsync(transform)
        }
    }

    /// Maps the success value of each `Result` with an async transform that can
    /// fail, and keeps the source order.
    ///
    /// Failures pass through unchanged, in their place. A failure from the transform
    /// replaces the value it came from. Otherwise it works like
    /// ``mapAsyncOrdered(concurrency:bufferLimit:_:)->AsyncStream<T>``.
    @inlinable
    public func flatMapAsyncOrdered<Success: Sendable, E: Error, T: Sendable>(
        concurrency: Int = 1,
        bufferLimit: Int = .max,
        _ transform: @concurrent @Sendable @escaping (Success) async -> Result<T, E>
    ) -> AsyncStream<Result<T, E>>
    where Element == Result<Success, E> {
        precondition(bufferLimit >= 0, "bufferLimit must be at least 0")
        if concurrency == 1 {
            // Captures `transform` directly, like `mapAsyncOrdered` above.
            let source = SharedIterator(makeAsyncIterator())
            return AsyncStream(unfolding: {
                guard let element = await source.next() else {
                    return nil
                }
                return await element.flatMapAsync(transform)
            })
        }

        return compactMapAsyncOrdered(
            concurrency: concurrency,
            bufferLimit: bufferLimit,
            passthrough: { $0.passthroughFailure() }
        ) { element in
            await element.flatMapAsync(transform)
        }
    }

    /// Maps each element with an async transform that can drop it, and keeps the
    /// source order.
    ///
    /// A transform that returns nil drops the element. `passthrough` is for elements
    /// that need no async work, like cache hits: when it returns a value, that value
    /// is the result and `transform` is not called. It runs on the task that reads
    /// the source, so keep it fast. Otherwise it works like
    /// ``mapAsyncOrdered(concurrency:bufferLimit:_:)->AsyncStream<T>``.
    ///
    /// ```swift
    /// for await user in ids.compactMapAsyncOrdered(
    ///     concurrency: 8,
    ///     passthrough: { id in cache[id] },
    ///     { id in await api.user(id) }  // nil when the user is gone
    /// ) {
    ///     show(user)
    /// }
    /// ```
    @inlinable
    public func compactMapAsyncOrdered<T: Sendable>(
        concurrency: Int = 1,
        bufferLimit: Int = .max,
        passthrough: (@Sendable (Element) -> T?)? = nil,
        _ transform: @concurrent @Sendable @escaping (Element) async -> T?
    ) -> AsyncStream<T> {
        precondition(concurrency >= 1, "concurrency must be at least 1")
        precondition(bufferLimit >= 0, "bufferLimit must be at least 0")
        if concurrency == 1 {
            // One at a time: each pull reads one element and transforms it in
            // the consumer's task, with no child tasks, buffers or read-ahead.
            // The closure calls `transform` directly, because a call through
            // `SequentialMapIterator` costs one more async frame per element.
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
            bufferLimit: bufferLimit,
            passthrough: passthrough,
            transform: transform
        )
        return AsyncStream(
            unfolding: { await pipeline.next() },
            onCancel: { pipeline.cancel() }
        )
    }
}

// MARK: - Old names

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension AsyncSequence where Self: Sendable, Failure == Never, Element: Sendable {
    /// Renamed to `mapAsyncOrdered`.
    @available(*, deprecated, renamed: "mapAsyncOrdered(concurrency:_:)")
    @inlinable
    public func mapAsyncKeepOrder<T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Element) async -> T
    ) -> AsyncStream<T> {
        mapAsyncOrdered(concurrency: concurrency, transform)
    }

    /// Renamed to `mapAsyncOrdered`.
    @available(*, deprecated, renamed: "mapAsyncOrdered(concurrency:_:)")
    @inlinable
    public func mapAsyncKeepOrder<Success: Sendable, E: Error, T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Success) async -> T
    ) -> AsyncStream<Result<T, E>>
    where Element == Result<Success, E> {
        mapAsyncOrdered(concurrency: concurrency, transform)
    }

    /// Renamed to `flatMapAsyncOrdered`.
    @available(*, deprecated, renamed: "flatMapAsyncOrdered(concurrency:_:)")
    @inlinable
    public func flatMapAsyncKeepOrder<Success: Sendable, E: Error, T: Sendable>(
        concurrency: Int = 1,
        _ transform: @concurrent @Sendable @escaping (Success) async -> Result<T, E>
    ) -> AsyncStream<Result<T, E>>
    where Element == Result<Success, E> {
        flatMapAsyncOrdered(concurrency: concurrency, transform)
    }
}
