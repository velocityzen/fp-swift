import Synchronization
import Testing

@testable import FP

@Suite("AsyncSequence asResults")
struct AsyncSequenceAsResultsTests {
    struct ReadError: Error, Equatable {
        let line: Int
    }

    @Test("Each element becomes a success")
    func wrapsEachElement() async {
        let numbers = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.finish()
        }
        #expect(await numbers.asResults().toArray() == [.success(1), .success(2)])
        #expect(
            await TypedSource([1, 2], throwing: nil).asResults().toResult() == .success([1, 2])
        )
    }

    @Test("The error the sequence throws becomes the last element, a failure")
    func thrownErrorBecomesAFailure() async {
        let output = await TypedSource([1, 2], throwing: ReadError(line: 3)).asResults().toArray()
        #expect(output == [.success(1), .success(2), .failure(ReadError(line: 3))])
        #expect(
            await TypedSource([], throwing: ReadError(line: 1)).asResults().toArray() == [
                .failure(ReadError(line: 1))
            ]
        )
    }

    @Test("After the failure, it ends and does not read again")
    func endsAfterTheFailure() async {
        let source = TypedSource([1], throwing: ReadError(line: 2))
        var iterator = source.asResults().makeAsyncIterator()
        #expect(await iterator.next() == .success(1))
        #expect(await iterator.next() == .failure(ReadError(line: 2)))
        #expect(await iterator.next() == nil)
        #expect(source.calls.value == 2)
    }

    @Test("The sinks read it without try, and the error keeps its type")
    func sinksKeepTheErrorType() async {
        let all: Result<[Int], ReadError> = await TypedSource(
            [1, 2, 3],
            throwing: ReadError(line: 4)
        )
        .asResults()
        .toResult()
        #expect(all == .failure(ReadError(line: 4)))
        #expect(
            await TypedSource([1, 2], throwing: ReadError(line: 3)).asResults().firstSuccess() == 1
        )
    }

    @Test("A stream that throws any Error gives results of any Error")
    func untypedStream() async {
        let lines = AsyncThrowingStream<String, any Error> { continuation in
            continuation.yield("a")
            continuation.finish(throwing: ReadError(line: 2))
        }
        let output = await lines.asResults().toResult()
        #expect(throws: ReadError(line: 2)) { try output.get() }
    }

    @Test("With failOnCancellation, a cancelled read ends with the given failure")
    func withFailOnCancellation() async {
        // Never finished: only the cancellation ends it.
        let (lines, continuation) = AsyncThrowingStream.makeStream(of: String.self)
        continuation.yield("a")
        let output = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await lines.asResults().failOnCancellation(with: CancellationError()).toResult()
        }.value
        #expect(throws: CancellationError.self) { try output.get() }
        continuation.finish()
    }
}

/// Counts calls from any thread.
private final class CallCounter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func add() {
        count.withLock { $0 += 1 }
    }
}

/// A sequence of `elements` with a typed error, thrown where it would end. It counts calls to
/// `next`.
private struct TypedSource: AsyncSequence, Sendable {
    typealias Element = Int
    typealias Failure = AsyncSequenceAsResultsTests.ReadError

    let elements: [Int]
    let error: Failure?
    let calls = CallCounter()

    init(_ elements: [Int], throwing error: Failure?) {
        self.elements = elements
        self.error = error
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(source: self)
    }

    struct Iterator: AsyncIteratorProtocol {
        typealias Failure = AsyncSequenceAsResultsTests.ReadError

        let source: TypedSource
        var index = 0

        mutating func next() async throws(Failure) -> Int? {
            source.calls.add()
            guard index < source.elements.count else {
                if let error = source.error { throw error }
                return nil
            }
            defer { index += 1 }
            return source.elements[index]
        }
    }
}
