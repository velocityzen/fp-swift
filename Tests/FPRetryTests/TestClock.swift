import Synchronization

/// A clock whose sleeps return at once and are recorded, so a test checks
/// the delays a retry waits without waiting them.
///
/// Its time moves only when something sleeps on it. A sleep in a cancelled
/// task throws `CancellationError`, like the system clocks.
final class TestClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleeps: [Duration] = []
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }

    var minimumResolution: Duration { .zero }

    /// Every duration slept so far, in order.
    var sleeps: [Duration] { state.withLock { $0.sleeps } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        state.withLock { state in
            state.sleeps.append(state.now.duration(to: deadline))
            state.now = deadline
        }
    }
}
