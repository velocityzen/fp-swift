import Synchronization

/// A one-time signal that one task can wait for.
///
/// It opens with the first value given, or when the last of `parties` arrives.
/// `withAll`, `withAny` and `withTimeout` run their operations as `async let`
/// children, which need no heap allocation, and wait on a gate for the result
/// that decides the call.
///
/// The waiter is resumed under the lock and takes it again, for ThreadSanitizer
/// (see `ConcurrentMapCoordinator`).
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

    /// - Parameter parties: How many `arrive(orOpenWith:)` calls open the gate.
    @inlinable
    init(parties: Int = 0) {
        state = Mutex(State(remaining: parties))
    }

    /// Opens the gate with `value`, unless it is open already.
    @inlinable
    func open(with value: Value) {
        state.withLock { $0.open(with: value) }
    }

    /// Opens the gate with `value` after `duration`, or at once if the task is
    /// cancelled. Does nothing if the gate is already open.
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
    @inlinable
    func open(after duration: Duration, with value: Value) async {
        try? await Task.sleep(for: duration)
        open(with: value)
    }

    /// Counts one party as arrived. The last one opens the gate with `value`.
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
            // For ThreadSanitizer. See the type's documentation.
            state.withLock { _ in }
        }
        return value
    }
}

extension Gate {
    /// Returns the success value, or nil for a failure. A failure opens the gate
    /// with it, and the last success opens it with nil.
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
    /// Counts an operation's result in a race. A success opens the gate with
    /// it, and the last failure opens it with that failure.
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
