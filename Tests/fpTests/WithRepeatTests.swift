import FP
import Synchronization
import Testing

/// A clock that moves only when something sleeps on it or a test advances it,
/// so a test checks the waits of `withRepeat` without waiting them.
///
/// A sleep ends `overshoot` after its deadline, like a late wakeup. A sleep in
/// a cancelled task throws `CancellationError`, like the system clocks.
private final class ManualClock: Clock {
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
        var reads = 0
    }

    private let state = Mutex(State())
    private let overshoot: Duration

    init(overshoot: Duration = .zero) {
        self.overshoot = overshoot
    }

    var now: Instant {
        state.withLock { state in
            state.reads += 1
            return state.now
        }
    }

    var minimumResolution: Duration { .zero }

    /// The time since the clock started. Not counted as a read.
    var elapsed: Duration { state.withLock { $0.now.offset } }

    /// Every duration slept so far, in order: from the time of the sleep to
    /// its deadline.
    var sleeps: [Duration] { state.withLock { $0.sleeps } }

    /// How many times `now` was read.
    var reads: Int { state.withLock { $0.reads } }

    func advance(by duration: Duration) {
        state.withLock { $0.now = $0.now.advanced(by: duration) }
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        state.withLock { state in
            state.sleeps.append(state.now.duration(to: deadline))
            state.now = deadline.advanced(by: overshoot)
        }
    }
}

/// Counts the calls of an operation, and records the clock's time at each.
private final class Calls: Sendable {
    private let times = Mutex<[Duration]>([])
    private let clock: ManualClock?

    init(_ clock: ManualClock? = nil) {
        self.clock = clock
    }

    /// Records a call and returns its number, from 1.
    func record() -> Int {
        let time = clock?.elapsed ?? .zero
        return times.withLock { times in
            times.append(time)
            return times.count
        }
    }

    var count: Int { times.withLock { $0.count } }

    var all: [Duration] { times.withLock { $0 } }
}

private enum TestError: Error, Equatable {
    case even(Int)
}

extension RepeatSequence.Iterator {
    /// The next `count` elements.
    fileprivate mutating func take(_ count: Int) async -> [Element?] {
        var elements: [Element?] = []
        for _ in 0..<count {
            elements.append(await next())
        }
        return elements
    }
}

@Suite("withRepeat")
struct WithRepeatTests {
    @Test("The first element comes at once, and each later one an interval after the one before")
    func firstAtOnceThenEveryInterval() async {
        let clock = ManualClock()
        let calls = Calls(clock)
        let sequence = withRepeat(interval: .seconds(1), clock: clock) {
            calls.record()
        }

        var iterator = sequence.makeAsyncIterator()
        let elements = await iterator.take(3)

        #expect(elements == [1, 2, 3])
        #expect(calls.all == [.zero, .seconds(1), .seconds(2)])
        #expect(clock.sleeps == [.seconds(1), .seconds(1)])
    }

    @Test("Nothing runs until the reader asks")
    func nothingRunsUntilAsked() async {
        let clock = ManualClock()
        let calls = Calls(clock)
        let sequence = withRepeat(interval: .seconds(1), clock: clock) {
            calls.record()
        }

        var iterator = sequence.makeAsyncIterator()
        #expect(calls.count == 0)

        _ = await iterator.next()
        clock.advance(by: .seconds(10))
        #expect(calls.count == 1)

        _ = await iterator.next()
        #expect(calls.count == 2)
    }

    @Test("A reader that asks late gets the element at once, and calls don't pile up")
    func lateReader() async {
        let clock = ManualClock()
        let calls = Calls(clock)
        var iterator = withRepeat(interval: .seconds(1), clock: clock) {
            calls.record()
        }.makeAsyncIterator()

        _ = await iterator.next()
        clock.advance(by: .milliseconds(2500))
        _ = await iterator.take(2)

        #expect(calls.all == [.zero, .milliseconds(2500), .milliseconds(3500)])
        #expect(clock.sleeps == [.seconds(1)])
    }

    @Test("A reader that asks early waits for the rest of the interval")
    func earlyReader() async {
        let clock = ManualClock()
        let calls = Calls(clock)
        var iterator = withRepeat(interval: .seconds(1), clock: clock) {
            calls.record()
        }.makeAsyncIterator()

        _ = await iterator.next()
        clock.advance(by: .milliseconds(400))
        _ = await iterator.next()

        #expect(calls.all == [.zero, .seconds(1)])
        #expect(clock.sleeps == [.milliseconds(600)])
    }

    @Test("A slow call does not add to the interval")
    func slowCall() async {
        let clock = ManualClock()
        let calls = Calls(clock)
        var iterator = withRepeat(interval: .seconds(1), clock: clock) {
            let call = calls.record()
            clock.advance(by: .milliseconds(300))
            return call
        }.makeAsyncIterator()

        _ = await iterator.take(3)

        #expect(calls.all == [.zero, .seconds(1), .seconds(2)])
        #expect(clock.sleeps == [.milliseconds(700), .milliseconds(700)])
    }

    @Test("After a late wakeup, the next call still waits the whole interval")
    func lateWakeup() async {
        let clock = ManualClock(overshoot: .milliseconds(50))
        let calls = Calls(clock)
        var iterator = withRepeat(interval: .seconds(1), clock: clock) {
            calls.record()
        }.makeAsyncIterator()

        _ = await iterator.take(3)

        #expect(calls.all == [.zero, .milliseconds(1050), .milliseconds(2100)])
        #expect(clock.sleeps == [.seconds(1), .seconds(1)])
    }

    @Test("An interval of zero runs a call each time the reader asks, and does not use the clock")
    func zeroInterval() async {
        let clock = ManualClock()
        let calls = Calls(clock)
        var iterator = withRepeat(interval: .zero, clock: clock) {
            calls.record()
        }.makeAsyncIterator()

        let elements = await iterator.take(3)

        #expect(elements == [1, 2, 3])
        #expect(clock.reads == 0)
        #expect(clock.sleeps.isEmpty)
    }

    @Test("Each loop over the sequence makes its own calls, and its first element comes at once")
    func eachLoopHasItsOwnCalls() async {
        let clock = ManualClock()
        let calls = Calls(clock)
        let sequence = withRepeat(interval: .seconds(1), clock: clock) {
            calls.record()
        }

        var first = sequence.makeAsyncIterator()
        var second = sequence.makeAsyncIterator()
        let a = await first.next()
        let b = await second.next()

        #expect([a, b] == [1, 2])
        #expect(clock.sleeps.isEmpty)
    }

    @Test("The operation can be async and return a Result, and a failure does not end the sequence")
    func asyncResults() async {
        let counter = AsyncCounter()
        let sequence = withRepeat(interval: .zero) { () async -> Result<Int, TestError> in
            let n = await counter.increment()
            return n.isMultiple(of: 2) ? .failure(.even(n)) : .success(n)
        }

        var values: [Int] = []
        for await value in sequence.successes() {
            values.append(value)
            if values.count == 3 { break }
        }

        #expect(values == [1, 3, 5])
    }

    @Test("Cancelling the reader's task ends a wait at once", .hangGuard)
    func cancellingEndsWait() async {
        let calls = Calls()
        let sequence = withRepeat(interval: .seconds(3600)) {
            calls.record()
        }
        let (received, signal) = AsyncStream.makeStream(of: Void.self)

        let reader = Task {
            var elements: [Int] = []
            for await element in sequence {
                elements.append(element)
                signal.yield()
            }
            return elements
        }
        for await _ in received { break }
        reader.cancel()

        #expect(await reader.value == [1])
        #expect(calls.count == 1)
    }

    @Test("A cancelled reader gets nil without a call, and nil after that")
    func cancelledReader() async {
        let calls = Calls()
        let sequence = withRepeat(interval: .zero) {
            calls.record()
        }

        let (first, ended) = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var iterator = sequence.makeAsyncIterator()
            let first = await iterator.next()
            return (first, iterator)
        }.value
        // A task that is not cancelled: the sequence stays ended.
        var iterator = ended
        let later = await iterator.next()

        #expect(first == nil)
        #expect(later == nil)
        #expect(calls.count == 0)
    }

    @Test("A call that runs when the task is cancelled still gives its element")
    func cancelledDuringCall() async {
        let sequence = withRepeat(interval: .zero) { () -> Int in
            withUnsafeCurrentTask { $0?.cancel() }
            return 1
        }

        let elements = await Task {
            var iterator = sequence.makeAsyncIterator()
            return await iterator.take(2)
        }.value

        #expect(elements == [1, nil])
    }

    #if compiler(>=6.4)
        @available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
        @Test("Inside a cancellation shield, the sequence goes on", .hangGuard)
        func cancellationShield() async {
            let calls = Calls()
            // The real clock, whose sleep a cancellation would end.
            let sequence = withRepeat(interval: .milliseconds(50)) {
                calls.record()
            }
            let (received, signal) = AsyncStream.makeStream(of: Void.self)

            let reader = Task {
                await withTaskCancellationShield {
                    var iterator = sequence.makeAsyncIterator()
                    var elements = [await iterator.next()]
                    signal.yield()
                    // Cancelled before or during the wait for the second.
                    elements += await iterator.take(2)
                    return elements
                }
            }
            for await _ in received { break }
            reader.cancel()

            #expect(await reader.value == [1, 2, 3])
        }
    #endif
}
