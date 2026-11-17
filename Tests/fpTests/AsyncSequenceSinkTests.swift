import Synchronization
import Testing

@testable import FP

@Suite("AsyncSequence sinks")
struct AsyncSequenceSinkTests {
    enum TestError: Error, Equatable {
        case failed
        case other
    }

    struct StreamError: Error {}

    typealias Element = Result<Int, TestError>

    let mixed: [Element] = [.success(1), .failure(.failed), .success(2), .failure(.other)]

    @Test("toResult gives every value, or the first failure")
    func toResult() async {
        #expect(await stream([.success(1), .success(2)]).toResult() == .success([1, 2]))
        #expect(await stream(mixed).toResult() == .failure(.failed))
        #expect(await stream([]).toResult() == .success([]))
    }

    @Test("toArray gives every element in order")
    func toArray() async {
        #expect(await stream(mixed).toArray() == mixed)
        #expect(await stream([]).toArray() == [])
    }

    @Test("separate splits the values and the errors, each in order")
    func separate() async {
        let (successes, failures) = await stream(mixed).separate()
        #expect(successes == [1, 2])
        #expect(failures == [.failed, .other])

        let empty = await stream([]).separate()
        #expect(empty.successes.isEmpty)
        #expect(empty.failures.isEmpty)
    }

    @Test("first gives the first element, success or failure")
    func first() async {
        #expect(await stream(mixed).first() == .success(1))
        #expect(await stream(Array(mixed.dropFirst())).first() == .failure(.failed))
        #expect(await stream([]).first() == nil)
    }

    @Test("firstSuccess skips failures")
    func firstSuccess() async {
        #expect(await stream(Array(mixed.dropFirst())).firstSuccess() == 2)
        #expect(await stream([.failure(.failed)]).firstSuccess() == nil)
    }

    @Test("firstError skips successes")
    func firstError() async {
        #expect(await stream(mixed).firstError() == .failed)
        #expect(await stream([.success(1)]).firstError() == nil)
    }

    @Test("firstSuccessOrLastError gives the first success, or else the last failure")
    func firstSuccessOrLastError() async {
        #expect(await stream(mixed).firstSuccessOrLastError() == .success(1))
        #expect(await stream(Array(mixed.dropFirst())).firstSuccessOrLastError() == .success(2))
        let failures: [Element] = [.failure(.failed), .failure(.other)]
        #expect(await stream(failures).firstSuccessOrLastError() == .failure(.other))
        #expect(await stream([]).firstSuccessOrLastError() == nil)

        // It stops at the first success, and reads to the end without one.
        let source = Source([.failure(.failed), .success(1), .failure(.other)])
        _ = await source.firstSuccessOrLastError()
        #expect(source.reads.value == 2)
        let allFail = Source(failures)
        _ = await allFail.firstSuccessOrLastError()
        #expect(allFail.reads.value == 2)
    }

    @Test("last gives the last element, success or failure")
    func last() async {
        #expect(await stream(mixed).last() == .failure(.other))
        #expect(await stream(Array(mixed.dropLast())).last() == .success(2))
        #expect(await stream([]).last() == nil)
    }

    @Test("lastSuccess skips failures")
    func lastSuccess() async {
        #expect(await stream(mixed).lastSuccess() == 2)
        #expect(await stream([.failure(.failed)]).lastSuccess() == nil)
    }

    @Test("lastError skips successes")
    func lastError() async {
        #expect(await stream(mixed).lastError() == .other)
        #expect(await stream([.success(1)]).lastError() == nil)
    }

    @Test("reduce combines values in order, or gives the first failure")
    func reduce() async {
        let digits = await stream([.success(1), .success(2), .success(3)])
            .reduce(0) { number, digit in number * 10 + digit }
        #expect(digits == .success(123))
        #expect(await stream(mixed).reduce(0, +) == .failure(.failed))
        #expect(await stream([]).reduce(7, +) == .success(7))
    }

    @Test("reduce(into:) updates one value in place, or gives the first failure")
    func reduceInto() async {
        let doubled = await stream([.success(1), .success(2), .success(3)])
            .reduce(into: [Int]()) { values, value in values.append(value * 2) }
        #expect(doubled == .success([2, 4, 6]))

        let counts = await stream([.success(1), .success(2), .success(1)])
            .reduce(into: [Int: Int]()) { counts, value in counts[value, default: 0] += 1 }
        #expect(counts == .success([1: 2, 2: 1]))

        #expect(await stream(mixed).reduce(into: [Int]()) { $0.append($1) } == .failure(.failed))
        #expect(await stream([]).reduce(into: 7) { $0 += $1 } == .success(7))

        let source = Source([.success(1), .failure(.failed), .success(2)])
        _ = await source.reduce(into: 0) { $0 += $1 }
        #expect(source.reads.value == 2)
    }

    @Test("A sink stops reading where it says")
    func stopsReading() async {
        let elements: [Element] = [.success(1), .failure(.failed), .success(2)]
        let source = Source(elements)
        _ = await source.toResult()
        #expect(source.reads.value == 2)

        let another = Source(elements)
        _ = await another.first()
        #expect(another.reads.value == 1)

        let toTheEnd = Source(elements)
        _ = await toTheEnd.lastError()
        #expect(toTheEnd.reads.value == 3)
    }

    @Test("A sink throws the sequence's error only when it reads that far")
    func throwsTheBaseError() async throws {
        func throwing(_ elements: [Element]) -> AsyncThrowingStream<Element, Error> {
            AsyncThrowingStream { continuation in
                for element in elements {
                    continuation.yield(element)
                }
                continuation.finish(throwing: StreamError())
            }
        }

        await #expect(throws: StreamError.self) {
            try await throwing([.success(1)]).toResult()
        }
        await #expect(throws: StreamError.self) {
            try await throwing([.success(1)]).firstError()
        }
        #expect(try await throwing(mixed).toResult() == .failure(.failed))
        #expect(try await throwing(mixed).firstSuccess() == 1)
    }

    @Test("A sink reads with the caller's isolation")
    @MainActor
    func readsOnTheCallersActor() async {
        var seen: [Int] = []
        let total = await stream([.success(1), .success(2)]).reduce(0) { sum, value in
            MainActor.assertIsolated()
            seen.append(value)
            return sum + value
        }
        #expect(total == .success(3))
        #expect(seen == [1, 2])

        let pair = stream([.success(1), .success(2)])
        let collected = await pair.reduce(into: [Int]()) { values, value in
            MainActor.assertIsolated()
            values.append(value)
        }
        #expect(collected == .success([1, 2]))
    }

    @Test("A sink reads a concurrent map")
    func readsAConcurrentMap() async {
        let doubled = await stream((1...20).map { .success($0) })
            .mapAsyncOrdered(concurrency: 4) { $0 * 2 }
            .toResult()
        #expect(doubled == .success((1...20).map { $0 * 2 }))
    }
}

private func stream(
    _ elements: [AsyncSequenceSinkTests.Element]
) -> AsyncStream<AsyncSequenceSinkTests.Element> {
    AsyncStream { continuation in
        for element in elements {
            continuation.yield(element)
        }
        continuation.finish()
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

/// A source that counts how many elements were read from it.
private struct Source: AsyncSequence, Sendable {
    typealias Element = AsyncSequenceSinkTests.Element
    typealias Failure = Never

    let elements: [Element]
    let reads = ReadCounter()

    init(_ elements: [Element]) {
        self.elements = elements
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(elements: elements, reads: reads)
    }

    struct Iterator: AsyncIteratorProtocol {
        let elements: [Element]
        let reads: ReadCounter
        var index = 0

        mutating func next() async -> Element? {
            guard index < elements.count else { return nil }
            defer { index += 1 }
            reads.add()
            return elements[index]
        }
    }
}
