import Synchronization
import Testing

@testable import FP

@Suite("AsyncSequence failOnCancellation")
struct AsyncSequenceFailOnCancellationTests {
    enum TestError: Error, Equatable {
        case failed
        case cancelled
    }

    struct StreamError: Error {}

    typealias Element = Result<Int, TestError>

    let mixed: [Element] = [.success(1), .failure(.failed), .success(2)]

    @Test("Without a cancellation, every element passes through")
    func passesThrough() async {
        let source = CancellingSource(mixed)
        #expect(await source.failOnCancellation(with: .cancelled).toArray() == mixed)
        #expect(source.reads.value == 3)
        #expect(await CancellingSource([]).failOnCancellation(with: .cancelled).toArray() == [])
    }

    @Test("In a task cancelled before it reads, it gives the failure and reads nothing")
    func cancelledBeforeReading() async {
        let source = CancellingSource(mixed)
        let output = await inCancelledTask {
            await source.failOnCancellation(with: .cancelled).toArray()
        }
        #expect(output == [.failure(.cancelled)])
        #expect(source.reads.value == 0)
    }

    @Test("A cancellation between reads ends the sequence with the failure")
    func cancelledBetweenReads() async {
        let source = CancellingSource(mixed, cancelAfter: 1)
        let output = await Task {
            await source.failOnCancellation(with: .cancelled).toArray()
        }.value
        #expect(output == [.success(1), .failure(.cancelled)])
        #expect(source.reads.value == 1)
    }

    @Test("A sequence that ends on the cancellation ends with the failure")
    func sequenceEndsOnTheCancellation() async {
        // Like `AsyncStream`: the cancellation comes during a read, which returns nil.
        let source = CancellingSource(mixed, cancelAfter: 1, endsOnCancellation: true)
        let output = await Task {
            await source.failOnCancellation(with: .cancelled).toArray()
        }.value
        #expect(output == [.success(1), .failure(.cancelled)])
        #expect(source.reads.value == 1)
    }

    @Test("After the failure, it ends and reads no more")
    func endsAfterTheFailure() async {
        let source = CancellingSource(mixed, cancelAfter: 1)
        let output = await Task {
            var iterator = source.failOnCancellation(with: .cancelled).makeAsyncIterator()
            let first = await iterator.next()
            let second = await iterator.next()
            let third = await iterator.next()
            return [first, second, third]
        }.value
        #expect(output == [.success(1), .failure(.cancelled), nil])
        #expect(source.reads.value == 1)
    }

    @Test("A cancellation after the last element still gives the failure")
    func cancelledAfterTheLastElement() async {
        let source = CancellingSource(mixed, cancelAfter: mixed.count)
        let output = await Task {
            await source.failOnCancellation(with: .cancelled).toArray()
        }.value
        #expect(output == mixed + [.failure(.cancelled)])
    }

    @Test("toResult gives the failure, not a partial success, for an unfinished stream")
    func unfinishedStream() async {
        let (plain, plainContinuation) = AsyncStream.makeStream(of: Element.self)
        let (guarded, guardedContinuation) = AsyncStream.makeStream(of: Element.self)
        for continuation in [plainContinuation, guardedContinuation] {
            continuation.yield(.success(1))
            continuation.yield(.success(2))
        }

        // Without it, a cancelled reader gets what was sent as if the stream had finished.
        #expect(await inCancelledTask { await plain.toResult() } == .success([1, 2]))
        let output = await inCancelledTask {
            await guarded.failOnCancellation(with: .cancelled).toResult()
        }
        #expect(output == .failure(.cancelled))

        plainContinuation.finish()
        guardedContinuation.finish()
    }

    @Test("withAny over cancelled streams gives the failure, not a partial success")
    func withAnyInACancelledTask() async {
        let (a, aContinuation) = AsyncStream.makeStream(of: Element.self)
        let (b, bContinuation) = AsyncStream.makeStream(of: Element.self)
        aContinuation.yield(.success(1))
        bContinuation.yield(.success(2))

        let result = await inCancelledTask {
            await withAny(
                await a.failOnCancellation(with: .cancelled).toResult(),
                await b.failOnCancellation(with: .cancelled).toResult()
            )
        }
        #expect(result == .failure(.cancelled))

        aContinuation.finish()
        bContinuation.finish()
    }

    @Test("It throws what the sequence throws")
    func throwsTheBaseError() async {
        let stream = AsyncThrowingStream<Element, Error> { continuation in
            continuation.yield(.success(1))
            continuation.finish(throwing: StreamError())
        }
        await #expect(throws: StreamError.self) {
            try await stream.failOnCancellation(with: .cancelled).toArray()
        }
    }

    // Linux only. On Apple platforms `withTaskCancellationShield` is emitted
    // into the caller and links the runtime's shield entry points strongly,
    // so before macOS 27 the whole test bundle fails to load, and
    // `@available` can't prevent that.
    #if compiler(>=6.4) && os(Linux)
        @Test("Inside a cancellation shield, every element passes through")
        func cancellationShield() async {
            let source = CancellingSource(mixed, cancelAfter: 1)
            let output = await Task {
                await withTaskCancellationShield {
                    await source.failOnCancellation(with: .cancelled).toArray()
                }
            }.value
            #expect(output == mixed)
        }
    #endif
}

/// Runs `operation` in a new task that is cancelled before it starts.
private func inCancelledTask<T: Sendable>(
    _ operation: @escaping @Sendable () async -> T
) async -> T {
    await Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await operation()
    }.value
}

/// Counts reads from any thread.
private final class ReadCounter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func add() {
        count.withLock { $0 += 1 }
    }
}

/// A source that counts reads, and cancels the task that reads it after `cancelAfter` reads.
///
/// It cancels right after that read, or, when `endsOnCancellation`, in the next read, which
/// then returns `nil` the way `AsyncStream` does.
private struct CancellingSource: AsyncSequence, Sendable {
    typealias Element = AsyncSequenceFailOnCancellationTests.Element
    typealias Failure = Never

    let elements: [Element]
    let cancelAfter: Int?
    let endsOnCancellation: Bool
    let reads = ReadCounter()

    init(_ elements: [Element], cancelAfter: Int? = nil, endsOnCancellation: Bool = false) {
        self.elements = elements
        self.cancelAfter = cancelAfter
        self.endsOnCancellation = endsOnCancellation
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(source: self)
    }

    struct Iterator: AsyncIteratorProtocol {
        let source: CancellingSource
        var index = 0

        mutating func next() async -> Element? {
            if source.endsOnCancellation, index == source.cancelAfter {
                withUnsafeCurrentTask { $0?.cancel() }
                return nil
            }
            guard index < source.elements.count else { return nil }
            defer { index += 1 }
            source.reads.add()
            if !source.endsOnCancellation, index + 1 == source.cancelAfter {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return source.elements[index]
        }
    }
}
