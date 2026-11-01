import Synchronization

// MARK: - The engine of the concurrent maps

// `mapAsyncKeepOrder`, `mapAsyncUnordered` and their variants share one
// engine. At `concurrency: 1` it is `SequentialMapIterator`, which reads and
// transforms an element only when the consumer asks for the next result.
// Above that it is `ConcurrentMapPipeline`, a reader and a pool of workers;
// the operators differ only in the `DeliveryOrder` it hands results over in.
//
// Every transform returns an optional: nil drops the element. And an element
// `passthrough` maps to a value is admitted with that value as its result,
// with no worker or transform.

/// Maps elements one at a time, each when the consumer asks for the next
/// result: the concurrent maps at `concurrency: 1`.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
struct SequentialMapIterator<Base: AsyncIteratorProtocol, Value>: AsyncIteratorProtocol
where Base.Element: Sendable, Base.Failure == Never {
    @usableFromInline var base: Base
    @usableFromInline let passthrough: (@Sendable (Base.Element) -> Value?)?
    @usableFromInline let transform: @concurrent @Sendable (Base.Element) async -> Value?

    @inlinable
    init(
        _ base: Base,
        passthrough: (@Sendable (Base.Element) -> Value?)?,
        transform: @concurrent @Sendable @escaping (Base.Element) async -> Value?
    ) {
        self.base = base
        self.passthrough = passthrough
        self.transform = transform
    }

    @inlinable
    mutating func next() async -> Value? {
        await next(isolation: #isolation)
    }

    @inlinable
    mutating func next(isolation actor: isolated (any Actor)?) async -> Value? {
        // Ends once the consumer is cancelled, as the concurrent pipeline does.
        while !Task.isCancelled, let element = await base.next(isolation: actor) {
            if let passthrough, let value = passthrough(element) {
                return value
            }

            if let value = await transform(element) {
                return value
            }
        }
        return nil
    }
}

/// Shares an iterator with the `AsyncStream(unfolding:)` closure.
///
/// `@unchecked Sendable`: an `AsyncStream` has a single consumer, so `next()`
/// is never called concurrently.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
final class SharedIterator<Base: AsyncIteratorProtocol>: @unchecked Sendable
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

// MARK: - Delivery orders

/// The order a `ConcurrentMapCoordinator` hands results over in, and the
/// results that finished before the consumer could take them.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
protocol DeliveryOrder: SendableMetatype {
    associatedtype Value: Sendable

    init(concurrency: Int)

    /// Whether the result of the element admitted `index`-th is the next one
    /// due, in which case it counts as delivered.
    mutating func deliverNow(_ index: Int) -> Bool

    /// Keeps the result of the element admitted `index`-th, nil when the
    /// element was dropped, until it is due.
    mutating func keep(_ result: Value?, at index: Int)

    /// Removes the next result due if it is ready: `.some(nil)` for a
    /// dropped element.
    mutating func takeNext() -> Value??
}

/// Results in the order their elements were read from the source.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
struct SourceOrder<Value: Sendable>: DeliveryOrder {
    /// Results that finished before they were due, by admission index.
    @usableFromInline var ready: [Int: Value?] = [:]
    /// The admission index of the next result due.
    @usableFromInline var due = 0

    @inlinable
    init(concurrency: Int) {
        ready.reserveCapacity(Swift.min(concurrency, 64))
    }

    @inlinable
    mutating func deliverNow(_ index: Int) -> Bool {
        guard index == due else {
            return false
        }

        due += 1
        return true
    }

    @inlinable
    mutating func keep(_ result: Value?, at index: Int) {
        ready[index] = .some(result)
    }

    @inlinable
    mutating func takeNext() -> Value?? {
        guard let result = ready.removeValue(forKey: due) else {
            return nil
        }

        due += 1
        return result
    }
}

/// Results in the order their transforms finished.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
struct CompletionOrder<Value: Sendable>: DeliveryOrder {
    @usableFromInline var ready = FIFOQueue<Value>()

    @inlinable
    init(concurrency: Int) {}

    @inlinable
    func deliverNow(_ index: Int) -> Bool {
        true
    }

    @inlinable
    mutating func keep(_ result: Value?, at index: Int) {
        // A dropped element is always due, so it never gets here.
        if let result {
            ready.append(result)
        }
    }

    @inlinable
    mutating func takeNext() -> Value?? {
        ready.popFirst().map { .some($0) }
    }
}

/// A first-in, first-out queue that reuses its storage once it empties.
@usableFromInline
struct FIFOQueue<Element> {
    /// The queued elements, from `head` on.
    @usableFromInline var items: [Element] = []
    @usableFromInline var head = 0

    @inlinable
    init() {}

    @inlinable
    mutating func append(_ element: Element) {
        items.append(element)
    }

    @inlinable
    mutating func popFirst() -> Element? {
        guard head < items.count else {
            return nil
        }

        let element = items[head]
        head += 1

        if head == items.count {
            items.removeAll(keepingCapacity: true)
            head = 0
        }
        return element
    }
}

// MARK: - The concurrent pipeline

/// The concurrent maps above `concurrency: 1`: owns the task that reads the
/// source and runs the transforms, and stops it when the consumer is
/// cancelled or drops the pipeline.
///
/// A reader admits a source element only while fewer than `concurrency` are
/// being transformed or waiting to be consumed, so a slow consumer pauses the
/// source; in source order, a slow early element also bounds how many later
/// results wait behind it. Admitted elements go to a pool of at most
/// `concurrency` workers, started as they are needed, each of which loops:
/// transform, hand the result over, take the next element.
///
/// Every handoff between the reader, the workers and the consumer resumes a
/// continuation, so after the pool has started an element costs its
/// transform and a few wakeups, with no task, stream or other allocation.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
final class ConcurrentMapPipeline<Element: Sendable, Order: DeliveryOrder>: Sendable {
    @usableFromInline let coordinator: ConcurrentMapCoordinator<Element, Order>
    @usableFromInline let root: Task<Void, Never>

    @inlinable
    init<Source: AsyncSequence & Sendable>(
        source: Source,
        concurrency: Int,
        passthrough: (@Sendable (Element) -> Order.Value?)?,
        transform: @concurrent @Sendable @escaping (Element) async -> Order.Value?
    ) where Source.Element == Element, Source.Failure == Never {
        let coordinator = ConcurrentMapCoordinator<Element, Order>(concurrency: concurrency)
        self.coordinator = coordinator
        // Workers are children of the root's group, so cancelling the root
        // cancels in-flight transforms cooperatively.
        root = Task {
            await withTaskGroup(of: Void.self) { workers in
                var iterator = source.makeAsyncIterator()
                reading: while await coordinator.waitForSlot(),
                    let element = await iterator.next(isolation: #isolation)
                {
                    if let passthrough, let value = passthrough(element) {
                        if coordinator.admit(result: value) {
                            continue
                        }
                        break reading
                    }

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
        // The consumer dropped the pipeline without cancelling its task.
        cancel()
    }

    @inlinable
    func next() async -> Order.Value? {
        await coordinator.next()
    }

    @inlinable
    func cancel() {
        coordinator.cancel()
        root.cancel()
    }
}

/// The state the reader, the workers and the consumer of a
/// `ConcurrentMapPipeline` share, behind one lock.
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
final class ConcurrentMapCoordinator<Element: Sendable, Order: DeliveryOrder>: Sendable {
    @usableFromInline typealias Value = Order.Value
    /// An admitted element and its position in the source.
    @usableFromInline typealias Work = (index: Int, element: Element)
    @usableFromInline typealias Consumer = UnsafeContinuation<Value?, Never>
    /// Resumed with false when the pipeline is cancelled.
    @usableFromInline typealias Reader = UnsafeContinuation<Bool, Never>
    @usableFromInline typealias Worker = UnsafeContinuation<Work?, Never>

    @usableFromInline
    struct State {
        /// Admitted elements no worker has taken yet.
        @usableFromInline var queue = FIFOQueue<Work>()
        @usableFromInline var results: Order
        /// Elements read from the source.
        @usableFromInline var admitted = 0
        /// Admitted elements whose result the consumer has not taken and
        /// that were not dropped: the slots in use.
        @usableFromInline var pending = 0
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
            results = Order(concurrency: concurrency)
        }

        /// The consumer's next result: the value when it is ready, nil once
        /// the stream has ended, or no answer when the consumer must wait.
        @inlinable
        mutating func takeNext() -> Value?? {
            if cancelled {
                return .some(nil)
            }

            while let result = results.takeNext() {
                freeSlot()
                if let value = result {
                    return value
                }
            }

            if finished && pending == 0 {
                return .some(nil)
            }
            return nil
        }

        /// Hands the result of the element admitted `index`-th to the waiting
        /// consumer when it is due, or keeps it until it is.
        @inlinable
        mutating func complete(_ result: Value?, at index: Int) {
            if cancelled {
                return
            }

            if let value = result {
                if let consumer, results.deliverNow(index) {
                    consumer.resume(returning: value)
                    self.consumer = nil
                    freeSlot()
                } else {
                    results.keep(value, at: index)
                }
            } else if results.deliverNow(index) {
                // A dropped element whose turn has come frees its slot at
                // once, and may be all the consumer was waiting on.
                freeSlot()
                wakeConsumer()
            } else {
                results.keep(nil, at: index)
            }
        }

        /// Gives back a slot, which lets the reader admit another element.
        @inlinable
        mutating func freeSlot() {
            pending -= 1
            reader?.resume(returning: true)
            reader = nil
        }

        /// Resumes the consumer if what it waits for has arrived.
        @inlinable
        mutating func wakeConsumer() {
            if let consumer, let next = takeNext() {
                consumer.resume(returning: next)
                self.consumer = nil
            }
        }

        /// Resumes every task waiting on the state but the reader, which
        /// either called this or is waiting for a slot.
        @inlinable
        mutating func endWaits() {
            for worker in idle {
                worker.resume(returning: nil)
            }
            idle = []
            wakeConsumer()
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
    func wait<Outcome: Sendable>(
        _ decide: (inout State, UnsafeContinuation<Outcome, Never>) -> Outcome?
    ) async -> Outcome {
        var parked = false
        let outcome = await withUnsafeContinuation {
            (continuation: UnsafeContinuation<Outcome, Never>) in
            state.withLock { state in
                if let outcome = decide(&state, continuation) {
                    continuation.resume(returning: outcome)
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
        return outcome
    }

    // MARK: Reader

    /// Waits until fewer than `concurrency` slots are in use. Returns false
    /// once the pipeline is cancelled.
    @inlinable
    func waitForSlot() async -> Bool {
        await wait { state, reader in
            if state.cancelled {
                return false
            }

            if state.pending < concurrency {
                return true
            }

            state.reader = reader
            return nil
        }
    }

    /// Takes a slot for `element` and hands it to a worker.
    @inlinable
    func admit(_ element: Element) -> Admission {
        state.withLock { state in
            if state.cancelled {
                return .cancelled
            }

            let work = (index: state.admitted, element: element)
            state.admitted += 1
            state.pending += 1
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

    /// Takes a slot for an element `passthrough` produced `value` for, which
    /// needs no worker. Returns false once the pipeline is cancelled.
    @inlinable
    func admit(result value: Value) -> Bool {
        state.withLock { state in
            if state.cancelled {
                return false
            }

            let index = state.admitted
            state.admitted += 1
            state.pending += 1
            state.complete(value, at: index)
            return true
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
        _ transform: @concurrent @Sendable (Element) async -> Value?
    ) async {
        var next: Work? = first
        while let work = next {
            next = await complete(await transform(work.element), at: work.index)
        }
    }

    /// Hands a finished result over, then takes the next admitted element,
    /// under the same lock, waiting for the reader if there is none. Returns
    /// nil once the reader finished or the pipeline was cancelled.
    @inlinable
    func complete(_ result: Value?, at index: Int) async -> Work? {
        await wait { state, worker in
            state.complete(result, at: index)
            if state.cancelled {
                return .some(nil)
            }

            if let work = state.queue.popFirst() {
                return work
            }

            if state.finished {
                return .some(nil)
            }

            state.idle.append(worker)
            return nil
        }
    }

    // MARK: Consumer

    /// Takes the next result due, waiting for it if it is not ready. Returns
    /// nil after the last one, or once cancelled.
    @inlinable
    func next() async -> Value? {
        await wait { state, consumer in
            if let next = state.takeNext() {
                return next
            }

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

extension Result {
    /// The failure re-typed under another success type, or nil for a
    /// success: the `passthrough` of the concurrent maps over `Result`s,
    /// which transform only successes.
    @inlinable
    func passthroughFailure<NewSuccess>() -> Result<NewSuccess, Failure>? {
        guard case .failure(let error) = self else {
            return nil
        }

        return .failure(error)
    }
}
