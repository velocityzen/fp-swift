import Foundation

extension AsyncSequence where Self: Sendable, Failure == Never, Element: Sendable {
    /// Maps each element through an async transform while preserving source
    /// order. Each transform runs in its own `Task` — they execute in
    /// parallel as the source emits — so total wall-clock time is bounded by
    /// the slowest element rather than the sum of all transforms.
    ///
    /// Results emit in source arrival order: a slow earlier transform holds
    /// back later faster ones, but each result is yielded as soon as the
    /// strict-order constraint allows.
    ///
    /// Use this when you want streaming, ordered emission of work that
    /// should run concurrently — e.g., a provider that receives image
    /// references over SSE and wants to download them in parallel while
    /// preserving the order the provider sent them in.
    ///
    /// ```swift
    /// for await result in events.mapAsyncKeepOrder({ event in
    ///     await process(event)
    /// }) {
    ///     handle(result)
    /// }
    /// ```
    public func mapAsyncKeepOrder<T: Sendable>(
        _ transform: @Sendable @escaping (Element) async -> T
    ) -> AsyncStream<T> {
        AsyncStream<T> { continuation in
            let drainer = Task {
                let (taskStream, taskCont) = AsyncStream.makeStream(of: Task<T, Never>.self)

                let consumer = Task {
                    for await task in taskStream {
                        continuation.yield(await task.value)
                    }
                    continuation.finish()
                }

                for await element in self {
                    taskCont.yield(Task { await transform(element) })
                }
                taskCont.finish()
                await consumer.value
            }
            continuation.onTermination = { _ in drainer.cancel() }
        }
    }

    /// Maps each `Result` element's success value through an async transform,
    /// preserving failures and source arrival order. Same concurrency model as
    /// ``mapAsyncKeepOrder(_:)`` — every success is transformed in its own
    /// `Task`, so wall-clock time is bounded by the slowest transform.
    ///
    /// Failures pass through immediately without spawning a task.
    ///
    /// ```swift
    /// for await result in events.mapAsyncKeepOrder({ event in
    ///     await enrich(event)
    /// }) {
    ///     handle(result)
    /// }
    /// ```
    public func mapAsyncKeepOrder<Success: Sendable, E: Error, T: Sendable>(
        _ transform: @Sendable @escaping (Success) async -> T
    ) -> AsyncStream<Result<T, E>>
    where Element == Result<Success, E> {
        mapAsyncKeepOrder { element in
            await element.mapAsync(transform)
        }
    }
}
