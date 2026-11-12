import Synchronization

// MARK: - The engine of the concurrent maps

// `mapAsyncOrdered`, `mapAsyncUnordered` and their variants share this
// engine. Above `concurrency: 1` it is `ConcurrentMapPipeline`: one reader and
// a pool of workers. The variants differ only in their `DeliveryOrder`.
//
// A transform returns nil to drop an element. A value from `passthrough` is the
// result itself, with no worker or transform.

/// Maps one element each time the consumer asks. Used at `concurrency: 1`.
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
        // Stops when the consumer's task is cancelled, like the pipeline.
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

/// Holds an iterator for an `AsyncStream(unfolding:)` closure. It is
/// `@unchecked Sendable` because an `AsyncStream` has only one consumer.
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

/// The order in which results are given out. It keeps the results that wait
/// for their turn. An `index` counts the admitted elements, from 0.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
protocol DeliveryOrder: SendableMetatype {
    associatedtype Value: Sendable

    init(concurrency: Int, bufferLimit: Int)

    /// Kept results that wait for an earlier element, not for the consumer.
    var early: Int { get }

    /// Whether element `index` may be admitted. There must never be more than
    /// `bufferLimit` early results.
    func mayAdmit(_ index: Int) -> Bool

    /// Whether the result of element `index` is due. If so, it counts as delivered.
    mutating func deliverNow(_ index: Int) -> Bool

    /// Keeps the result of element `index` (nil if dropped) until it is due.
    mutating func keep(_ result: Value?, at index: Int)

    /// Removes the next result due if it is ready. `.some(nil)` is a dropped
    /// element.
    mutating func takeNext() -> Value??
}

/// Results in the order their elements were read from the source.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
struct SourceOrder<Value: Sendable>: DeliveryOrder {
    /// Results that finished before they were due, by index.
    @usableFromInline var ready: RingBuffer<Value?>
    /// The index of the next result due.
    @usableFromInline var due = 0
    /// The index of the first element that has not finished.
    @usableFromInline var frontier = 0
    /// The results in `ready` after `frontier`.
    @usableFromInline var early = 0
    @usableFromInline let bufferLimit: Int

    @inlinable
    init(concurrency: Int, bufferLimit: Int) {
        self.bufferLimit = bufferLimit
        // Every element from `due` on holds a slot or is early, so `ready`
        // never spans more than `concurrency + bufferLimit` indices. Room
        // for all of them is made now, so with a `bufferLimit` it never
        // grows. With no limit, room is made for twice as many early results
        // as `concurrency`, and it grows past that.
        let waiting = Swift.min(concurrency, preallocationLimit)
        let early = bufferLimit == .max ? 2 * waiting : Swift.min(bufferLimit, preallocationLimit)
        ready = RingBuffer(capacity: preallocated(waiting + early))
    }

    @inlinable
    func mayAdmit(_ index: Int) -> Bool {
        // Every element after `frontier` may finish before it, and be early.
        index - frontier <= bufferLimit
    }

    @inlinable
    mutating func deliverNow(_ index: Int) -> Bool {
        guard index == due else {
            return false
        }

        due += 1
        // The element due is the first one that has not finished.
        passFrontier(index)
        return true
    }

    @inlinable
    mutating func keep(_ result: Value?, at index: Int) {
        ready.store(result, at: index, from: due)
        if index == frontier {
            passFrontier(index)
        } else {
            early += 1
        }
    }

    /// Moves `frontier` past element `index` and the early results after it.
    @inlinable
    mutating func passFrontier(_ index: Int) {
        frontier = index + 1
        while early > 0, ready.contains(frontier, from: due) {
            frontier += 1
            early -= 1
        }
    }

    @inlinable
    mutating func takeNext() -> Value?? {
        guard let result = ready.take(due) else {
            return nil
        }

        due += 1
        return result
    }
}

/// Results in the order the transforms finished.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
struct CompletionOrder<Value: Sendable>: DeliveryOrder {
    @usableFromInline var ready: FIFOQueue<Value>

    @inlinable
    init(concurrency: Int, bufferLimit: Int) {
        // Each result here holds a slot until the consumer takes it, so
        // there are never more than `concurrency` of them.
        ready = FIFOQueue(capacity: preallocated(concurrency))
    }

    @inlinable
    var early: Int {
        0
    }

    @inlinable
    func mayAdmit(_ index: Int) -> Bool {
        true
    }

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

// MARK: - Buffers

/// The most slots a buffer of the pipeline makes room for when it is
/// made. A buffer that needs more grows when it fills.
@inlinable
var preallocationLimit: Int {
    1024
}

/// How many slots to make room for when a buffer is made: `count`, up to
/// `preallocationLimit`.
@inlinable
func preallocated(_ count: Int) -> Int {
    Swift.min(count, preallocationLimit)
}

/// Elements stored by index in a ring: index `i` lives in slot `i & mask`.
///
/// The stored indices are all in `start..<(start + capacity)`, where `start`
/// is the lowest index that can still be stored, so no two share a slot.
/// Storing an index further on grows the ring, which is the only time it
/// allocates after it is made.
@usableFromInline
struct RingBuffer<Element> {
    /// The slots, a power of two of them, or none. nil is an empty slot.
    @usableFromInline var slots: [Element?]

    /// Makes room for `capacity` elements, rounded up to a power of two.
    @inlinable
    init(capacity: Int) {
        slots = Array(repeating: nil, count: Self.roundedUp(capacity))
    }

    @inlinable
    static func roundedUp(_ capacity: Int) -> Int {
        capacity <= 0 ? 0 : 1 << (Int.bitWidth - (capacity - 1).leadingZeroBitCount)
    }

    @inlinable
    var mask: Int {
        slots.count - 1
    }

    /// Whether an element is stored at `index`. `start` is the lowest index
    /// that can still be stored.
    @inlinable
    func contains(_ index: Int, from start: Int) -> Bool {
        index - start < slots.count && slots[index & mask] != nil
    }

    /// Stores `element` at `index`. `start` is the lowest index that can
    /// still be stored.
    @inlinable
    mutating func store(_ element: Element, at index: Int, from start: Int) {
        if index - start >= slots.count {
            grow(toFit: index, from: start)
        }
        slots[index & mask] = element
    }

    /// Removes the element at `index` and returns it, or returns nil if there
    /// is none. `index` must be in `start..<(start + capacity)`.
    @inlinable
    mutating func take(_ index: Int) -> Element? {
        slots[index & mask].take()
    }

    /// Moves the elements from `start` on to a ring with room for `index`.
    @inlinable
    mutating func grow(toFit index: Int, from start: Int) {
        var grown = [Element?](repeating: nil, count: Self.roundedUp(index - start + 1))
        let grownMask = grown.count - 1
        for stored in start..<(start + slots.count) {
            grown[stored & grownMask] = slots[stored & mask].take()
        }
        slots = grown
    }
}

/// A first-in, first-out queue in a `RingBuffer`. It allocates only when it
/// holds more elements than it has room for, and keeps no element it gave
/// out.
@usableFromInline
struct FIFOQueue<Element> {
    @usableFromInline var ring: RingBuffer<Element>
    /// The index of the first element.
    @usableFromInline var head = 0
    /// The index the next element is stored at.
    @usableFromInline var tail = 0

    @inlinable
    init(capacity: Int = 0) {
        ring = RingBuffer(capacity: capacity)
    }

    @inlinable
    mutating func append(_ element: Element) {
        ring.store(element, at: tail, from: head)
        tail += 1
    }

    @inlinable
    mutating func popFirst() -> Element? {
        guard head < tail else {
            return nil
        }

        defer { head += 1 }
        return ring.take(head)
    }
}

// MARK: - The concurrent pipeline

/// Runs the concurrent maps above `concurrency: 1`. Its task reads the source
/// and runs the transforms. It stops when the consumer is cancelled or drops
/// the pipeline.
///
/// An element takes a slot while it is transformed or its result waits for the
/// consumer. The reader admits an element only while a slot is free, so a slow
/// consumer pauses the source. Early results take no slot, so a slow element
/// does not stop the workers. Only `bufferLimit` limits them.
///
/// Up to `concurrency` workers start as needed, and each one loops over
/// elements. Handoffs resume continuations, and the buffers are made with
/// room for every element in flight (up to `preallocationLimit`), so once the
/// workers run, an element needs no allocation.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
final class ConcurrentMapPipeline<Element: Sendable, Order: DeliveryOrder>: Sendable {
    @usableFromInline let coordinator: ConcurrentMapCoordinator<Element, Order>
    @usableFromInline let root: Task<Void, Never>

    @inlinable
    init<Source: AsyncSequence & Sendable>(
        source: Source,
        concurrency: Int,
        bufferLimit: Int = .max,
        passthrough: (@Sendable (Element) -> Order.Value?)?,
        transform: @concurrent @Sendable @escaping (Element) async -> Order.Value?
    ) where Source.Element == Element, Source.Failure == Never {
        let coordinator = ConcurrentMapCoordinator<Element, Order>(
            concurrency: concurrency,
            bufferLimit: bufferLimit
        )
        self.coordinator = coordinator
        // Workers are children of the root task, so cancelling the root
        // cancels the running transforms.
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

    /// Cancels from a task cancellation handler, in a new task.
    ///
    /// The runtime holds a lock on the cancelled task while its handlers run,
    /// and resuming that task takes the same lock. The coordinator resumes
    /// tasks under its own lock, so a handler that took the coordinator's lock
    /// could wait for a worker that waits for the handler.
    @inlinable
    func cancelFromHandler() {
        Task.detached { [self] in
            cancel()
        }
    }
}

/// The state that the reader, the workers and the consumer of a
/// `ConcurrentMapPipeline` share, behind one lock.
///
/// A waiting task parks its continuation in the state. The task that changes
/// what it waits for resumes it. Both happen under the lock, so no change is
/// missed.
///
/// A parked task can be resumed before it reaches its `await`. ThreadSanitizer
/// then sees no sync and reports a false race. So resumes happen under the
/// lock, and a resumed task takes the lock once more.
///
/// Resuming a task takes the runtime's lock on that task, so this lock must
/// never be taken while the runtime holds one: never in a task cancellation
/// handler. Handlers call `ConcurrentMapPipeline.cancelFromHandler()`.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
@usableFromInline
final class ConcurrentMapCoordinator<Element: Sendable, Order: DeliveryOrder>: Sendable {
    @usableFromInline typealias Value = Order.Value
    @usableFromInline typealias Work = (index: Int, element: Element)
    @usableFromInline typealias Consumer = UnsafeContinuation<Value?, Never>
    /// Resumed with false when the pipeline is cancelled.
    @usableFromInline typealias Reader = UnsafeContinuation<Bool, Never>
    @usableFromInline typealias Worker = UnsafeContinuation<Work?, Never>

    @usableFromInline
    struct State {
        /// Admitted elements that no worker has taken yet. It is made with no
        /// room: the reader waits for a free slot, and a free slot means a
        /// worker is idle or another may start.
        @usableFromInline var queue = FIFOQueue<Work>()
        @usableFromInline var results: Order
        @usableFromInline var admitted = 0
        /// Admitted elements not dropped and not yet taken by the consumer.
        @usableFromInline var pending = 0
        @usableFromInline var workers = 0
        @usableFromInline let concurrency: Int
        /// The reader stopped. No more elements are admitted.
        @usableFromInline var finished = false
        @usableFromInline var cancelled = false
        @usableFromInline var consumer: Consumer?
        /// The reader, waiting for a slot.
        @usableFromInline var reader: Reader?
        /// Workers waiting for an element.
        @usableFromInline var idle: [Worker] = []

        @inlinable
        init(concurrency: Int, bufferLimit: Int) {
            self.concurrency = concurrency
            results = Order(concurrency: concurrency, bufferLimit: bufferLimit)
            // Room for every worker (up to `preallocationLimit`), so parking
            // one does not allocate.
            idle.reserveCapacity(preallocated(concurrency))
        }

        /// Whether a slot is free and the delivery order allows another element.
        @inlinable
        var mayAdmit: Bool {
            pending - results.early < concurrency && results.mayAdmit(admitted)
        }

        /// The consumer's next result: the value, `.some(nil)` at the end, or
        /// nil if the consumer must wait.
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

        /// Gives the result of element `index` to the waiting consumer if it
        /// is due, or keeps it.
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
                    // The reader may go on: an early result frees a slot,
                    // or `frontier` moved.
                    wakeReader()
                }
            } else if results.deliverNow(index) {
                // The consumer may be waiting for this dropped element.
                freeSlot()
                wakeConsumer()
            } else {
                results.keep(nil, at: index)
                wakeReader()
            }
        }

        @inlinable
        mutating func freeSlot() {
            pending -= 1
            wakeReader()
        }

        @inlinable
        mutating func wakeReader() {
            if let reader, mayAdmit {
                reader.resume(returning: true)
                self.reader = nil
            }
        }

        @inlinable
        mutating func wakeConsumer() {
            if let consumer, let next = takeNext() {
                consumer.resume(returning: next)
                self.consumer = nil
            }
        }

        /// Resumes all waiting tasks but the reader. The reader called this
        /// (`finish()`), or `cancel()` resumes it.
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
        /// An idle worker took the element, or a busy one takes it later.
        case taken
        case start(Work)
        case cancelled
    }

    @usableFromInline let state: Mutex<State>

    @inlinable
    init(concurrency: Int, bufferLimit: Int) {
        state = Mutex(State(concurrency: concurrency, bufferLimit: bufferLimit))
    }

    /// Runs `decide` under the lock and goes on with the value it returns. If
    /// `decide` parks the continuation and returns nil, waits to be resumed.
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
            // For ThreadSanitizer. See the type's documentation.
            state.withLock { _ in }
        }
        return outcome
    }

    // MARK: Reader

    /// Waits until the reader may admit an element. Returns false once cancelled.
    @inlinable
    func waitForSlot() async -> Bool {
        await wait { state, reader in
            if state.cancelled {
                return false
            }

            if state.mayAdmit {
                return true
            }

            state.reader = reader
            return nil
        }
    }

    /// Takes a slot for `element` and gives it to a worker.
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

            if state.workers < state.concurrency {
                state.workers += 1
                return .start(work)
            }

            state.queue.append(work)
            return .taken
        }
    }

    /// Takes a slot for an element that `passthrough` turned into `value`.
    /// Returns false once the pipeline is cancelled.
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

    /// Records that the reader stopped. Idle workers exit, and the consumer
    /// ends after it takes every result.
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

    /// Hands over a result, then takes the next element or waits for one, under
    /// the same lock. Returns nil when the reader finished or once cancelled.
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

    /// Takes the next result due, or waits for it. Returns nil at the end or
    /// once cancelled.
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

    /// Ends the stream. The reader stops, idle workers exit, and every later
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
    /// Returns the failure with a new success type, or nil for a success. The
    /// maps over `Result`s use it as `passthrough`.
    @inlinable
    func passthroughFailure<NewSuccess>() -> Result<NewSuccess, Failure>? {
        guard case .failure(let error) = self else {
            return nil
        }

        return .failure(error)
    }
}
