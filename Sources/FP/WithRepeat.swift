// MARK: - Run an operation again and again

/// Returns an async sequence that runs `operation` each time the reader asks for an
/// element, at most once per `interval`.
///
/// The first element comes at once. Each later call starts once `interval` has passed
/// since the call before it started, or at once if it has passed when the reader asks.
/// Nothing runs until the reader asks, so a slow reader or a slow call never makes calls
/// pile up.
///
/// The sequence never ends by itself. Cancelling the reader's task ends it: a wait stops
/// at once, and no new call starts. A running call sees the cancellation only if it checks
/// for it, and its element is still given out. Inside `withTaskCancellationShield`, the
/// sequence goes on.
///
/// `operation` runs on the actor that reads the sequence. It can be sync or async, and it
/// can't throw. To go on after a failure, return a `Result`.
///
/// Each `for await` loop over the sequence makes its own calls, and its first element
/// comes at once.
///
/// ```swift
/// let statuses = withRepeat(interval: .seconds(5)) {
///     await fetchStatus()
/// }
///
/// for await status in statuses {
///     show(status)
/// }
/// ```
///
/// - Parameters:
///   - interval: The shortest time from the start of one call to the start of the next.
///     Must be zero or more.
///   - clock: The clock for the waits. An interval of zero does not use it.
///   - operation: Makes one element.
@inlinable
public func withRepeat<Element, C: Clock<Duration>>(
    interval: Duration,
    clock: C = ContinuousClock(),
    _ operation: @Sendable @escaping () async -> Element
) -> RepeatSequence<Element, C> {
    precondition(interval >= .zero, "interval must be zero or more")
    return RepeatSequence(interval: interval, clock: clock, operation: operation)
}

/// An async sequence that runs an operation each time the reader asks for an element, at
/// most once per interval.
///
/// ``withRepeat(interval:clock:_:)`` returns it. It never ends by itself, and ends when
/// the reader's task is cancelled.
@frozen
public struct RepeatSequence<Element, C: Clock<Duration>>: AsyncSequence, Sendable {
    public typealias Failure = Never

    @usableFromInline let interval: Duration
    @usableFromInline let clock: C
    @usableFromInline let operation: @Sendable () async -> Element

    @inlinable
    init(
        interval: Duration,
        clock: C,
        operation: @escaping @Sendable () async -> Element
    ) {
        self.interval = interval
        self.clock = clock
        self.operation = operation
    }

    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(self)
    }

    @frozen
    public struct Iterator: AsyncIteratorProtocol, Sendable {
        @usableFromInline let interval: Duration
        /// Whether the interval is above zero, so calls may have to wait.
        @usableFromInline let waits: Bool
        @usableFromInline let clock: C
        @usableFromInline let operation: @Sendable () async -> Element
        /// When the next call may start. Nil before the first call.
        @usableFromInline var deadline: C.Instant?
        @usableFromInline var finished = false

        @inlinable
        init(_ sequence: RepeatSequence) {
            interval = sequence.interval
            waits = sequence.interval > .zero
            clock = sequence.clock
            operation = sequence.operation
        }

        @inlinable
        public mutating func next() async -> Element? {
            await next(isolation: #isolation)
        }

        @inlinable
        public mutating func next(isolation actor: isolated (any Actor)?) async -> Element? {
            guard !finished, !Task.isCancelled else {
                finished = true
                return nil
            }
            // An interval of zero never reads the clock, and a call that is due
            // makes no extra async call.
            if waits, let deadline = due() {
                guard await sleep(until: deadline) else {
                    finished = true
                    return nil
                }
            }
            return await operation()
        }

        /// The deadline to sleep until before the next call, or nil if the call may
        /// start now. Then it sets the deadline for the call after it.
        @inlinable
        mutating func due() -> C.Instant? {
            let now = clock.now
            if let deadline, now < deadline {
                return deadline
            }
            deadline = now.advanced(by: interval)
            return nil
        }

        /// Sleeps until `deadline`, and sets the deadline for the call after the next.
        /// Returns false if the task is cancelled.
        @inlinable
        mutating func sleep(until deadline: C.Instant) async -> Bool {
            do {
                try await clock.sleep(until: deadline, tolerance: nil)
            } catch {
                return false
            }
            // From when the sleep ended, not from the deadline: after a late wakeup,
            // the next call still waits the whole interval.
            self.deadline = clock.now.advanced(by: interval)
            return true
        }
    }
}
