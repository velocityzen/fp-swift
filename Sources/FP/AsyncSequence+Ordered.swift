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
    @inlinable
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
    @inlinable
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
@usableFromInline
final class SourceIterator<Base: AsyncIteratorProtocol>: @unchecked Sendable
where Base.Failure == Never {
    @usableFromInline var base: Base

    @inlinable
    init(_ base: Base) {
        self.base = base
    }

    @inlinable
    func next() async -> Base.Element? {
        await base.next(isolation: #isolation)
    }
}

/// The parallel engine behind `mapAsyncKeepOrder(concurrency:_:)`: owns the
/// task that reads the source and runs the transforms, and stops it when the
/// stream is cancelled or dropped.
///
/// A reader admits a source element only while fewer than `concurrency` are
/// being transformed or waiting to be consumed, so a slow consumer pauses the
/// source, and a slow early element bounds how many later results wait
/// behind it. Admitted elements go to a pool of at most `concurrency`
/// workers, started as they are needed, each of which loops: transform,
/// deposit the result, take the next element.
///
/// Every handoff between the reader, the workers and the consumer resumes a
/// continuation, so after the pool has started an element costs its
/// transform and a few wakeups, with no task, stream or other allocation.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
final class KeepOrderPipeline<Element: Sendable, T: Sendable>: Sendable {
    @usableFromInline let coordinator: KeepOrderCoordinator<Element, T>
    @usableFromInline let root: Task<Void, Never>

    @inlinable
    init<Source: AsyncSequence & Sendable>(
        source: Source,
        concurrency: Int,
        transform: @concurrent @Sendable @escaping (Element) async -> T
    ) where Source.Element == Element, Source.Failure == Never {
        let coordinator = KeepOrderCoordinator<Element, T>(concurrency: concurrency)
        self.coordinator = coordinator
        // Workers are children of the root's group, so cancelling the root
        // cancels in-flight transforms cooperatively.
        root = Task {
            await withTaskGroup(of: Void.self) { workers in
                var iterator = source.makeAsyncIterator()
                reading: while await coordinator.waitForSlot(),
                    let element = await iterator.next(isolation: #isolation)
                {
                    switch coordinator.admit(element) {
                        case .taken:
                            continue
                        case .start(let work):
                            workers.addTask { await coordinator.work(from: work, transform) }
                        case .cancelled:
                            break reading
                    }
                }
                coordinator.finish()
            }
        }
    }

    deinit {
        // The consumer dropped the stream without cancelling its task.
        cancel()
    }

    @inlinable
    func next() async -> T? {
        await coordinator.next()
    }

    @inlinable
    func cancel() {
        coordinator.cancel()
        root.cancel()
    }
}

/// The state the reader, the workers and the consumer of a
/// `KeepOrderPipeline` share, behind one lock.
///
/// A task waiting on it parks its continuation in the state and is resumed
/// by whichever task changes what it waits for: a waiter never misses a
/// change, since it checks and parks under the same lock that change takes.
///
/// Continuations are resumed while the lock is held, and a parked task takes
/// the lock once more after it is resumed. A continuation resumed before its
/// task reaches the `await` lets that task run on with no synchronization
/// ThreadSanitizer can see, so without the lock it would report the task's
/// next use of the same memory as a race with the resume.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
final class KeepOrderCoordinator<Element: Sendable, T: Sendable>: Sendable {
    /// An admitted element and its position in the source.
    @usableFromInline typealias Work = (index: Int, element: Element)
    @usableFromInline typealias Consumer = UnsafeContinuation<T?, Never>
    /// Resumed with false when the pipeline is cancelled.
    @usableFromInline typealias Reader = UnsafeContinuation<Bool, Never>
    @usableFromInline typealias Worker = UnsafeContinuation<Work?, Never>

    @usableFromInline
    struct State {
        /// Admitted elements no worker has taken yet, from `queueHead` on.
        @usableFromInline var queue: [Work] = []
        @usableFromInline var queueHead = 0
        /// Results that finished before the consumer reached them.
        @usableFromInline var ready: [Int: T] = [:]
        /// Elements read from the source.
        @usableFromInline var admitted = 0
        /// Results the consumer has taken; also the index of the next due.
        @usableFromInline var emitted = 0
        @usableFromInline var workers = 0
        /// The reader stopped, so no element is admitted after `admitted`.
        @usableFromInline var finished = false
        @usableFromInline var cancelled = false
        @usableFromInline var consumer: Consumer?
        /// The reader, waiting for a slot.
        @usableFromInline var reader: Reader?
        /// Workers waiting for an element.
        @usableFromInline var idle: [Worker] = []

        @inlinable
        init(concurrency: Int) {
            ready.reserveCapacity(Swift.min(concurrency, 64))
        }

        @inlinable
        mutating func dequeue() -> Work? {
            guard queueHead < queue.count else { return nil }
            let work = queue[queueHead]
            queueHead += 1
            if queueHead == queue.count {
                queue.removeAll(keepingCapacity: true)
                queueHead = 0
            }
            return work
        }

        /// The consumer's next result: the value when it is ready, nil once
        /// the stream has ended, or no answer when the consumer must wait.
        @inlinable
        mutating func takeNext() -> T?? {
            if cancelled { return .some(nil) }
            if let value = ready.removeValue(forKey: emitted) {
                consumed()
                return value
            }
            if finished && emitted == admitted { return .some(nil) }
            return nil
        }

        /// Records that the consumer took the next due result, which frees a
        /// slot for the reader.
        @inlinable
        mutating func consumed() {
            emitted += 1
            reader?.resume(returning: true)
            reader = nil
        }

        /// Resumes every task waiting on the state but the reader, which
        /// either called this or is waiting for a slot.
        @inlinable
        mutating func endWaits() {
            for worker in idle {
                worker.resume(returning: nil)
            }
            idle = []
            if let consumer, let next = takeNext() {
                consumer.resume(returning: next)
                self.consumer = nil
            }
        }
    }

    @usableFromInline
    enum Admission {
        /// An idle worker took the element, or a busy one takes it when it
        /// finishes its own.
        case taken
        /// Start another worker on the element.
        case start(Work)
        /// The pipeline was cancelled: read no further.
        case cancelled
    }

    @usableFromInline let concurrency: Int
    @usableFromInline let state: Mutex<State>

    @inlinable
    init(concurrency: Int) {
        self.concurrency = concurrency
        state = Mutex(State(concurrency: concurrency))
    }

    /// Suspends the calling task until `decide`, run under the lock, returns
    /// the value to go on with, or, when it parks the task's continuation in
    /// the state and returns nil, until another task resumes it.
    @inlinable
    func wait<Value: Sendable>(
        _ decide: (inout State, UnsafeContinuation<Value, Never>) -> Value?
    ) async -> Value {
        var parked = false
        let value = await withUnsafeContinuation {
            (continuation: UnsafeContinuation<Value, Never>) in
            state.withLock { state in
                if let value = decide(&state, continuation) {
                    continuation.resume(returning: value)
                } else {
                    parked = true
                }
            }
        }
        if parked {
            // Orders everything after this with the resume, for
            // ThreadSanitizer (see the type's documentation).
            state.withLock { _ in }
        }
        return value
    }

    // MARK: Reader

    /// Waits until fewer than `concurrency` elements are admitted but not yet
    /// consumed. Returns false once the pipeline is cancelled.
    @inlinable
    func waitForSlot() async -> Bool {
        await wait { state, reader in
            if state.cancelled { return false }
            if state.admitted - state.emitted < concurrency { return true }
            state.reader = reader
            return nil
        }
    }

    @inlinable
    func admit(_ element: Element) -> Admission {
        state.withLock { state in
            if state.cancelled { return .cancelled }
            let work = (index: state.admitted, element: element)
            state.admitted += 1
            if let worker = state.idle.popLast() {
                worker.resume(returning: work)
                return .taken
            }
            if state.workers < concurrency {
                state.workers += 1
                return .start(work)
            }
            state.queue.append(work)
            return .taken
        }
    }

    /// Records that the reader stopped: idle workers exit, and the consumer
    /// ends once it has taken every result.
    @inlinable
    func finish() {
        state.withLock { state in
            state.finished = true
            state.endWaits()
        }
    }

    // MARK: Workers

    @inlinable
    func work(
        from first: Work,
        _ transform: @concurrent @Sendable (Element) async -> T
    ) async {
        var next: Work? = first
        while let work = next {
            deposit(await transform(work.element), at: work.index)
            next = await nextWork()
        }
    }

    /// Keeps a result for the consumer, or hands it over at once when it is
    /// the next one due and the consumer is waiting.
    @inlinable
    func deposit(_ value: T, at index: Int) {
        state.withLock { state in
            if state.cancelled { return }
            if index == state.emitted, let consumer = state.consumer {
                consumer.resume(returning: value)
                state.consumer = nil
                state.consumed()
            } else {
                state.ready[index] = value
            }
        }
    }

    /// Takes the next admitted element, waiting for the reader if there is
    /// none. Returns nil once the reader finished or the pipeline was
    /// cancelled.
    @inlinable
    func nextWork() async -> Work? {
        await wait { state, worker in
            if state.cancelled { return .some(nil) }
            if let work = state.dequeue() { return work }
            if state.finished { return .some(nil) }
            state.idle.append(worker)
            return nil
        }
    }

    // MARK: Consumer

    /// Takes the next result in source order, waiting for it if it is not
    /// ready. Returns nil after the last one, or once cancelled.
    @inlinable
    func next() async -> T? {
        await wait { state, consumer in
            if let next = state.takeNext() { return next }
            state.consumer = consumer
            return nil
        }
    }

    /// Ends the stream: the reader stops, idle workers exit, and every later
    /// result is dropped.
    @inlinable
    func cancel() {
        state.withLock { state in
            state.cancelled = true
            state.endWaits()
            state.reader?.resume(returning: false)
            state.reader = nil
        }
    }
}
