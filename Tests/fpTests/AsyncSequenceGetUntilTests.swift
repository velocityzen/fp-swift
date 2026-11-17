import Synchronization
import Testing

@testable import FP

@Suite("AsyncSequence get, untilFailure and untilSuccess")
struct AsyncSequenceGetUntilTests {
    enum TestError: Error, Equatable {
        case failed
        case other
    }

    struct ReadError: Error, Equatable {}

    typealias Element = Result<Int, TestError>

    // MARK: get

    @Test("get gives every value of a sequence with no failure")
    func getValues() async throws {
        var values: [Int] = []
        for try await value in CountingSource([.success(1), .success(2)]).get() {
            values.append(value)
        }
        #expect(values == [1, 2])

        var empty: [Int] = []
        for try await value in CountingSource([]).get() { empty.append(value) }
        #expect(empty.isEmpty)
    }

    @Test("get throws the first failure with its own type, after the values before it")
    func getThrowsTheFirstFailure() async {
        var values: [Int] = []
        do throws(TestError) {
            for try await value in CountingSource([
                .success(1), .failure(.failed), .failure(.other),
            ]).get() {
                values.append(value)
            }
            Issue.record("expected a failure")
        } catch {
            #expect(error == .failed)
        }
        #expect(values == [1])
    }

    @Test("After the failure, get ends and reads no more")
    func getEndsAfterTheFailure() async throws {
        let source = CountingSource([.success(1), .failure(.failed), .success(3)])
        var iterator = source.get().makeAsyncIterator()
        #expect(try await iterator.next() == 1)
        await #expect(throws: TestError.failed) { try await iterator.next() }
        #expect(try await iterator.next() == nil)
        #expect(source.reads.value == 2)
    }

    @Test("asResults then get gives back the values and the error")
    func getUndoesAsResults() async {
        let stream = AsyncThrowingStream<Int, any Error> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.finish(throwing: ReadError())
        }
        var values: [Int] = []
        await #expect(throws: ReadError.self) {
            for try await value in stream.asResults().get() { values.append(value) }
        }
        #expect(values == [1, 2])
    }

    @Test("get stops a concurrent map before it")
    func getStopsAConcurrentMap() async {
        let source = CountingSource((1...100).map { $0 == 2 ? .failure(.failed) : .success($0) })
        let values = source.mapAsyncOrdered(concurrency: 2) { (value: Int) in value }.get()
        await #expect(throws: TestError.failed) {
            for try await _ in values {}
        }
        #expect(source.reads.value < 100)
    }

    // MARK: untilFailure and untilSuccess

    @Test("untilFailure gives the elements up to and including the first failure")
    func untilFailure() async {
        let source = CountingSource([.success(1), .success(2), .failure(.failed), .success(3)])
        #expect(
            await source.untilFailure().toArray() == [.success(1), .success(2), .failure(.failed)]
        )
        #expect(source.reads.value == 3)
    }

    @Test("untilSuccess gives the elements up to and including the first success")
    func untilSuccess() async {
        let source = CountingSource([
            .failure(.failed), .failure(.other), .success(1), .failure(.failed),
        ])
        #expect(
            await source.untilSuccess().toArray() == [
                .failure(.failed), .failure(.other), .success(1),
            ]
        )
        #expect(source.reads.value == 3)
    }

    @Test("Without the element they wait for, they give every element")
    func untilWithoutTheStop() async {
        let successes: [Element] = [.success(1), .success(2)]
        let failures: [Element] = [.failure(.failed), .failure(.other)]
        #expect(await CountingSource(successes).untilFailure().toArray() == successes)
        #expect(await CountingSource(failures).untilSuccess().toArray() == failures)
        #expect(await CountingSource([]).untilSuccess().toArray() == [])
    }

    @Test("After the element they wait for, they end and read no more")
    func untilEndsAfterTheStop() async {
        let source = CountingSource([.success(1), .success(2)])
        var iterator = source.untilSuccess().makeAsyncIterator()
        #expect(await iterator.next() == .success(1))
        #expect(await iterator.next() == nil)
        #expect(await iterator.next() == nil)
        #expect(source.reads.value == 1)
    }

    @Test("untilSuccess ends a withRepeat poll at the first success")
    func untilSuccessWithRepeat() async {
        let calls = Atomic(0)
        let polls = withRepeat(interval: .zero) { () -> Element in
            calls.add(1, ordering: .relaxed).oldValue < 2 ? .failure(.failed) : .success(7)
        }
        #expect(
            await polls.untilSuccess().toArray() == [
                .failure(.failed), .failure(.failed), .success(7),
            ]
        )
        #expect(calls.load(ordering: .relaxed) == 3)
    }

    @Test("untilFailure throws what the sequence throws")
    func untilThrowsTheBaseError() async {
        let stream = AsyncThrowingStream<Element, any Error> { continuation in
            continuation.yield(.success(1))
            continuation.finish(throwing: ReadError())
        }
        await #expect(throws: ReadError.self) { try await stream.untilFailure().toArray() }
    }

    @Test("They read on the caller's actor")
    @MainActor
    func readsOnTheCallersActor() async throws {
        let elements: [Element] = [.success(1), .failure(.failed)]
        for try await _ in CountingSource([.success(1)]).get() { MainActor.assertIsolated() }
        for await _ in CountingSource(elements).untilFailure() { MainActor.assertIsolated() }
    }
}

/// Counts reads from any thread.
private final class ReadCounter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func add() {
        count.withLock { $0 += 1 }
    }
}

/// A source of results that counts how many elements were read.
private struct CountingSource: AsyncSequence, Sendable {
    typealias Element = AsyncSequenceGetUntilTests.Element
    typealias Failure = Never

    let elements: [Element]
    let reads = ReadCounter()

    init(_ elements: [Element]) {
        self.elements = elements
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(source: self)
    }

    struct Iterator: AsyncIteratorProtocol {
        let source: CountingSource
        var index = 0

        mutating func next() async -> Element? {
            guard index < source.elements.count else { return nil }
            defer { index += 1 }
            source.reads.add()
            return source.elements[index]
        }
    }
}
