import Synchronization
import Testing

@testable import FP

/// Non-Sendable state owned by the main actor. Capturing it in a closure
/// passed to an FP combinator only compiles if the combinator is
/// `nonisolated(nonsending)` and keeps the closure on the caller's actor.
private final class Log {
    var entries: [String] = []

    func record(_ entry: String) {
        MainActor.assertIsolated()
        entries.append(entry)
    }
}

/// A `Log` that `@Sendable` closures can capture.
private final class SendableLog: Sendable {
    let entries = Mutex<[String]>([])

    func record(_ entry: String) {
        MainActor.assertIsolated()
        entries.withLock { $0.append(entry) }
    }
}

@MainActor
@Suite("Async combinators run on the caller's actor")
struct AsyncIsolationTests {
    enum TestError: Error, Equatable {
        case boom
    }

    // MARK: - Result map

    @Test("Result.mapAsync runs on the caller's actor")
    func resultMapAsync() async {
        let log = Log()
        let ok: Result<Int, TestError> = .success(1)

        let mapped = await ok.mapAsync { value in
            log.record("map")
            return value + 1
        }
        let mappedThrowing = await Result<Int, Error>.success(1).mapAsync { value throws in
            log.record("mapThrowing")
            return value + 1
        }

        #expect(mapped == .success(2))
        #expect((try? mappedThrowing.get()) == 2)
        #expect(log.entries == ["map", "mapThrowing"])
    }

    @Test("Result.mapErrorAsync runs on the caller's actor")
    func resultMapErrorAsync() async {
        let log = Log()
        let failed: Result<Int, TestError> = .failure(.boom)

        let mapped = await failed.mapErrorAsync { error in
            log.record("mapError")
            return error
        }

        #expect(mapped == .failure(.boom))
        #expect(log.entries == ["mapError"])
    }

    @Test("Result.flatMapAsync runs on the caller's actor")
    func resultFlatMapAsync() async {
        let log = Log()
        let ok: Result<Int, TestError> = .success(1)

        let mapped = await ok.flatMapAsync { value in
            log.record("flatMap")
            return .success(value + 1)
        }

        #expect(mapped == .success(2))
        #expect(log.entries == ["flatMap"])
    }

    @Test("Result.fromAsync runs on the caller's actor")
    func resultFromAsync() async {
        let log = Log()

        let result = await Result.fromAsync {
            log.record("fromAsync")
            return 1
        }

        #expect((try? result.get()) == 1)
        #expect(log.entries == ["fromAsync"])
    }

    // MARK: - Result tap

    @Test("Result.tapAsync runs on the caller's actor")
    func resultTapAsync() async {
        let log = Log()
        let ok: Result<Int, TestError> = .success(1)

        _ = await ok.tapAsync { _ in log.record("tap") }
        _ = await ok.tapAsync { _ throws in log.record("tapThrowing") }
        _ = await ok.tapAsync { _ -> Result<Void, TestError> in
            log.record("tapResult")
            return .success(())
        }

        #expect(log.entries == ["tap", "tapThrowing", "tapResult"])
    }

    @Test("Result.tapErrorAsync runs on the caller's actor")
    func resultTapErrorAsync() async {
        let log = Log()
        let failed: Result<Int, TestError> = .failure(.boom)

        _ = await failed.tapErrorAsync { _ in log.record("tapError") }
        _ = await failed.tapErrorAsync { _ throws in log.record("tapErrorThrowing") }

        #expect(log.entries == ["tapError", "tapErrorThrowing"])
    }

    // MARK: - Result match, recovery, do-notation

    @Test("Result.matchAsync runs on the caller's actor")
    func resultMatchAsync() async {
        let log = Log()
        let ok: Result<Int, TestError> = .success(1)

        let value = await ok.matchAsync(
            { value in
                log.record("onSuccess")
                return value
            },
            { _ in
                log.record("onFailure")
                return 0
            }
        )

        #expect(value == 1)
        #expect(log.entries == ["onSuccess"])
    }

    @Test("Result recovery combinators run on the caller's actor")
    func resultRecoveryAsync() async {
        let log = Log()
        let failed: Result<Int, TestError> = .failure(.boom)

        let alt = await failed.altAsync {
            log.record("alt")
            return .success(1)
        }
        let orElse = await failed.orElseAsync { _ -> Result<Int, Never> in
            log.record("orElse")
            return .success(2)
        }
        let getOrElse = await failed.getOrElseAsync { _ in
            log.record("getOrElse")
            return 3
        }

        #expect(alt == .success(1))
        #expect(orElse == .success(2))
        #expect(getOrElse == 3)
        #expect(log.entries == ["alt", "orElse", "getOrElse"])
    }

    @Test("Result do-notation runs on the caller's actor")
    func resultDoAsync() async {
        let log = Log()
        let ok: Result<Int, TestError> = .success(1)

        let result =
            await ok
            .bindAsync { value -> Result<Int, TestError> in
                log.record("bind")
                return .success(value + 1)
            }
            .letAsync { a, b in
                log.record("let")
                return a + b
            }

        #expect(result.map { $0.2 } == .success(3))
        #expect(log.entries == ["bind", "let"])
    }

    // MARK: - Array

    @Test("Array async combinators run on the caller's actor")
    func arrayAsync() async {
        let log = Log()
        let values = [1, 2]

        let mapped = await values.mapAsync { value in
            log.record("map")
            return value * 2
        }
        let flatMapped = await values.flatMapAsync { value in
            log.record("flatMap")
            return [value]
        }
        let compacted = await values.compactMapAsync { value -> Int? in
            log.record("compactMap")
            return value
        }
        let traversed = await values.traverseAsync { value -> Result<Int, TestError> in
            log.record("traverse")
            return .success(value)
        }

        #expect(mapped == [2, 4])
        #expect(flatMapped == [1, 2])
        #expect(compacted == [1, 2])
        #expect(traversed == .success([1, 2]))
        #expect(log.entries.count == 8)
    }

    // MARK: - Optional

    @Test("Optional async combinators run on the caller's actor")
    func optionalAsync() async {
        let log = Log()
        let some: Int? = 1

        let mapped = await some.mapAsync { value in
            log.record("map")
            return value + 1
        }
        let flatMapped = await some.flatMapAsync { value -> Int? in
            log.record("flatMap")
            return value + 1
        }
        let matched = await some.matchAsync(
            { value in
                log.record("match")
                return value
            },
            0
        )
        let finished = await some.finallyAsync { log.record("finally") }

        #expect(mapped == 2)
        #expect(flatMapped == 2)
        #expect(matched == 1)
        #expect(finished == 1)
        #expect(log.entries == ["map", "flatMap", "match", "finally"])
    }

    // MARK: - Operators

    @Test("Async pipe operator runs on the caller's actor")
    func asyncPipe() async {
        let log = Log()
        let transform: (Int) async -> Int = { value in
            log.record("pipe")
            return value + 1
        }

        let result = await (1 |> transform)

        #expect(result == 2)
        #expect(log.entries == ["pipe"])
    }

    // MARK: - AsyncSequence

    @Test("AsyncSequence Result operators run on the iterating actor")
    func asyncSequenceResult() async {
        let log = SendableLog()
        let stream = AsyncStream<Result<Int, TestError>> { continuation in
            continuation.yield(.success(1))
            continuation.yield(.failure(.boom))
            continuation.finish()
        }

        let sequence =
            stream
            .map { (value: Int) in
                log.record("map")
                return value
            }
            .mapError { error in
                log.record("mapError")
                return error
            }
            .flatMap { value in
                log.record("flatMap")
                return .success(value)
            }
            .tap { _ in log.record("tap") }
            .tapError { _ in log.record("tapError") }
            .mapAsync { value in
                log.record("mapAsync")
                return value
            }
            .mapErrorAsync { error in
                log.record("mapErrorAsync")
                return error
            }
            .flatMapAsync { value in
                log.record("flatMapAsync")
                return .success(value)
            }
            .tapAsync { _ in log.record("tapAsync") }
            .tapErrorAsync { _ in log.record("tapErrorAsync") }
            .successes()

        var values: [Int] = []
        for await value in sequence {
            values.append(value)
        }

        #expect(values == [1])
        #expect(
            log.entries.withLock { $0 } == [
                "map", "flatMap", "tap", "mapAsync", "flatMapAsync", "tapAsync",
                "mapError", "tapError", "mapErrorAsync", "tapErrorAsync",
            ]
        )
    }
}
