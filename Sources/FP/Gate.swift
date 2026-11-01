import Synchronization

/// Opens once, with the first value offered or, with `parties` given, when
/// the last of them arrives, and lets one task wait for it to open.
///
/// The combinators run their operations as `async let` children, which live
/// in the parent task's allocator rather than on the heap, and wait on a
/// gate for the outcome that decides the call: the first failure of
/// `withAll`, the first success of `withAny`, the first result of
/// `withTimeout`, or every operation done.
///
/// The waiter is resumed while the lock is held and takes the lock again
/// once it is resumed, so ThreadSanitizer sees the resume ordered before
/// whatever the waiter does next (see `KeepOrderCoordinator`).
@usableFromInline
final class Gate<Value: Sendable>: Sendable {
    @usableFromInline
    struct State {
        @usableFromInline var value: Value?
        @usableFromInline var remaining: Int
        @usableFromInline var waiter: UnsafeContinuation<Value, Never>?

        @inlinable
        init(remaining: Int) {
            self.remaining = remaining
        }

        @inlinable
        mutating func open(with value: Value) {
            guard self.value == nil else { return }
            self.value = value
            waiter?.resume(returning: value)
            waiter = nil
        }
    }

    @usableFromInline let state: Mutex<State>

    /// - Parameter parties: How many calls to `arrive(orOpenWith:)` open the
    ///   gate.
    @inlinable
    init(parties: Int = 0) {
        state = Mutex(State(remaining: parties))
    }

    /// Opens the gate with `value`, unless it is open already.
    @inlinable
    func open(with value: Value) {
        state.withLock { $0.open(with: value) }
    }

    /// Opens the gate with `value` after `duration`, unless it opened first
    /// or the calling task is cancelled before then.
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
    @inlinable
    func open(after duration: Duration, with value: Value) async {
        try? await Task.sleep(for: duration)
        open(with: value)
    }

    /// Counts off one party; the last one opens the gate with `value`.
    @inlinable
    func arrive(orOpenWith value: Value) {
        state.withLock { state in
            state.remaining -= 1
            if state.remaining == 0 {
                state.open(with: value)
            }
        }
    }

    /// Waits for the gate to open and returns the value it opened with.
    @inlinable
    func wait() async -> Value {
        var parked = false
        let value = await withUnsafeContinuation { (waiter: UnsafeContinuation<Value, Never>) in
            state.withLock { state in
                if let value = state.value {
                    waiter.resume(returning: value)
                } else {
                    state.waiter = waiter
                    parked = true
                }
            }
        }
        if parked {
            // Orders what follows after the resume, for ThreadSanitizer.
            state.withLock { _ in }
        }
        return value
    }
}

extension Gate {
    /// Passes an operation's success through. A failure opens the gate with
    /// it, and the last success opens the gate with nil.
    @inlinable
    func success<Success, Failure>(of result: Result<Success, Failure>) -> Success?
    where Value == Failure? {
        switch result {
            case .success(let value):
                arrive(orOpenWith: nil)
                return value
            case .failure(let error):
                open(with: error)
                return nil
        }
    }
}

extension Gate {
    /// Races an operation's result: a success opens the gate with it, and
    /// the last failure opens the gate with that failure.
    @inlinable
    func race<Success, Failure>(_ result: Result<Success, Failure>)
    where Value == Result<Success, Failure> {
        switch result {
            case .success:
                open(with: result)
            case .failure:
                arrive(orOpenWith: result)
        }
    }
}
