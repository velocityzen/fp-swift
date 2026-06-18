import Testing

@testable import FP

@Suite("Result+Tuple Tests")
struct ResultTupleTests {
    enum TestError: Error, Equatable {
        case failed
        case other
    }

    // MARK: - All 2

    @Test("all 2 succeeds with both results")
    func all2Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("hello")

        let result = all(a, b)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "hello")
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("all 2 fails when first fails")
    func all2FailsFirst() {
        let a: Result<Int, TestError> = .failure(.failed)
        let b: Result<String, TestError> = .success("hello")

        let result = all(a, b)

        if case .failure(let error) = result {
            #expect(error == .failed)
        } else {
            Issue.record("Expected failure")
        }
    }

    @Test("all 2 fails when second fails")
    func all2FailsSecond() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .failure(.other)

        let result = all(a, b)

        if case .failure(let error) = result {
            #expect(error == .other)
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - All 3

    @Test("all 3 succeeds with all results")
    func all3Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("hello")
        let c: Result<Double, TestError> = .success(3.14)

        let result = all(a, b, c)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "hello")
            #expect(value.2 == 3.14)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("all 3 fails when any fails")
    func all3Fails() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .failure(.failed)
        let c: Result<Double, TestError> = .success(3.14)

        let result = all(a, b, c)

        if case .failure(let error) = result {
            #expect(error == .failed)
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - All 4

    @Test("all 4 succeeds with all results")
    func all4Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("hello")
        let c: Result<Double, TestError> = .success(3.14)
        let d: Result<Bool, TestError> = .success(true)

        let result = all(a, b, c, d)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "hello")
            #expect(value.2 == 3.14)
            #expect(value.3 == true)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("all 4 fails when any fails")
    func all4Fails() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("hello")
        let c: Result<Double, TestError> = .success(3.14)
        let d: Result<Bool, TestError> = .failure(.other)

        let result = all(a, b, c, d)

        if case .failure(let error) = result {
            #expect(error == .other)
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - All 5

    @Test("all 5 succeeds with all results")
    func all5Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("a")
        let c: Result<Int, TestError> = .success(2)
        let d: Result<String, TestError> = .success("b")
        let f: Result<Int, TestError> = .success(3)

        let result = all(a, b, c, d, f)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "a")
            #expect(value.2 == 2)
            #expect(value.3 == "b")
            #expect(value.4 == 3)
        } else {
            Issue.record("Expected success")
        }
    }

    // MARK: - All 6

    @Test("all 6 succeeds with all results")
    func all6Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("a")
        let c: Result<Int, TestError> = .success(2)
        let d: Result<String, TestError> = .success("b")
        let f: Result<Int, TestError> = .success(3)
        let g: Result<String, TestError> = .success("c")

        let result = all(a, b, c, d, f, g)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "a")
            #expect(value.2 == 2)
            #expect(value.3 == "b")
            #expect(value.4 == 3)
            #expect(value.5 == "c")
        } else {
            Issue.record("Expected success")
        }
    }

    // MARK: - Named tuple with map

    @Test("all with named tuple via map")
    func allWithNamedTuple() {
        let a: Result<Int, TestError> = .success(42)
        let b: Result<String, TestError> = .success("hello")

        let result = all(a, b).map { (id: $0, name: $1) }

        if case .success(let value) = result {
            #expect(value.id == 42)
            #expect(value.name == "hello")
        } else {
            Issue.record("Expected success")
        }
    }

    // MARK: - All 7

    @Test("all 7 succeeds with all results")
    func all7Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("a")
        let c: Result<Int, TestError> = .success(2)
        let d: Result<String, TestError> = .success("b")
        let f: Result<Int, TestError> = .success(3)
        let g: Result<String, TestError> = .success("c")
        let h: Result<Int, TestError> = .success(4)

        let result = all(a, b, c, d, f, g, h)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "a")
            #expect(value.2 == 2)
            #expect(value.3 == "b")
            #expect(value.4 == 3)
            #expect(value.5 == "c")
            #expect(value.6 == 4)
        } else {
            Issue.record("Expected success")
        }
    }

    // MARK: - All 8

    @Test("all 8 succeeds with all results")
    func all8Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("a")
        let c: Result<Int, TestError> = .success(2)
        let d: Result<String, TestError> = .success("b")
        let f: Result<Int, TestError> = .success(3)
        let g: Result<String, TestError> = .success("c")
        let h: Result<Int, TestError> = .success(4)
        let i: Result<String, TestError> = .success("d")

        let result = all(a, b, c, d, f, g, h, i)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "a")
            #expect(value.2 == 2)
            #expect(value.3 == "b")
            #expect(value.4 == 3)
            #expect(value.5 == "c")
            #expect(value.6 == 4)
            #expect(value.7 == "d")
        } else {
            Issue.record("Expected success")
        }
    }

    // MARK: - All 9

    @Test("all 9 succeeds with all results")
    func all9Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("a")
        let c: Result<Int, TestError> = .success(2)
        let d: Result<String, TestError> = .success("b")
        let f: Result<Int, TestError> = .success(3)
        let g: Result<String, TestError> = .success("c")
        let h: Result<Int, TestError> = .success(4)
        let i: Result<String, TestError> = .success("d")
        let j: Result<Int, TestError> = .success(5)

        let result = all(a, b, c, d, f, g, h, i, j)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "a")
            #expect(value.2 == 2)
            #expect(value.3 == "b")
            #expect(value.4 == 3)
            #expect(value.5 == "c")
            #expect(value.6 == 4)
            #expect(value.7 == "d")
            #expect(value.8 == 5)
        } else {
            Issue.record("Expected success")
        }
    }

    // MARK: - All 10

    @Test("all 10 succeeds with all results")
    func all10Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("a")
        let c: Result<Int, TestError> = .success(2)
        let d: Result<String, TestError> = .success("b")
        let f: Result<Int, TestError> = .success(3)
        let g: Result<String, TestError> = .success("c")
        let h: Result<Int, TestError> = .success(4)
        let i: Result<String, TestError> = .success("d")
        let j: Result<Int, TestError> = .success(5)
        let k: Result<String, TestError> = .success("e")

        let result = all(a, b, c, d, f, g, h, i, j, k)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "a")
            #expect(value.2 == 2)
            #expect(value.3 == "b")
            #expect(value.4 == 3)
            #expect(value.5 == "c")
            #expect(value.6 == 4)
            #expect(value.7 == "d")
            #expect(value.8 == 5)
            #expect(value.9 == "e")
        } else {
            Issue.record("Expected success")
        }
    }

    // MARK: - Preserves error type

    @Test("all preserves typed error")
    func allPreservesErrorType() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .failure(.failed)

        let result: Result<(Int, String), TestError> = all(a, b)

        if case .failure(let error) = result {
            #expect(error == .failed)
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - Async allAsync Tests

    @Test("allAsync 2 succeeds with both async results")
    func allAsync2Succeeds() async {
        let getInt: @Sendable () async -> Result<Int, TestError> = { .success(1) }
        let getString: @Sendable () async -> Result<String, TestError> = { .success("hello") }

        let result = await allAsync(await getInt(), await getString())

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "hello")
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("allAsync 2 fails when any async result fails")
    func allAsync2Fails() async {
        let getInt: @Sendable () async -> Result<Int, TestError> = { .success(1) }
        let getString: @Sendable () async -> Result<String, TestError> = { .failure(.failed) }

        let result = await allAsync(await getInt(), await getString())

        if case .failure(let error) = result {
            #expect(error == .failed)
        } else {
            Issue.record("Expected failure")
        }
    }

    @Test("allAsync 3 succeeds with all async results")
    func allAsync3Succeeds() async {
        let getA: @Sendable () async -> Result<Int, TestError> = { .success(1) }
        let getB: @Sendable () async -> Result<String, TestError> = { .success("a") }
        let getC: @Sendable () async -> Result<Double, TestError> = { .success(3.14) }

        let result = await allAsync(await getA(), await getB(), await getC())

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "a")
            #expect(value.2 == 3.14)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("allAsync 4 succeeds with all async results")
    func allAsync4Succeeds() async {
        let getA: @Sendable () async -> Result<Int, TestError> = { .success(1) }
        let getB: @Sendable () async -> Result<String, TestError> = { .success("a") }
        let getC: @Sendable () async -> Result<Double, TestError> = { .success(3.14) }
        let getD: @Sendable () async -> Result<Bool, TestError> = { .success(true) }

        let result = await allAsync(await getA(), await getB(), await getC(), await getD())

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "a")
            #expect(value.2 == 3.14)
            #expect(value.3 == true)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("allAsync preserves typed error for async operations")
    func allAsyncPreservesError() async {
        let getInt: @Sendable () async -> Result<Int, TestError> = { .failure(.other) }
        let getString: @Sendable () async -> Result<String, TestError> = { .success("hello") }

        let result: Result<(Int, String), TestError> = await allAsync(
            await getInt(),
            await getString()
        )

        if case .failure(let error) = result {
            #expect(error == .other)
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - All 10 (full arity ladder)

    @Test("all combines ten results, exercising every arity")
    func allTenSuccess() {
        let result = all(
            Result<Int, TestError>.success(1),
            Result<Int, TestError>.success(2),
            Result<Int, TestError>.success(3),
            Result<Int, TestError>.success(4),
            Result<Int, TestError>.success(5),
            Result<Int, TestError>.success(6),
            Result<Int, TestError>.success(7),
            Result<Int, TestError>.success(8),
            Result<Int, TestError>.success(9),
            Result<Int, TestError>.success(10)
        )

        let sum = result.map { a, b, c, d, e, f, g, h, i, j in
            a + b + c + d + e + f + g + h + i + j
        }
        #expect(sum == .success(55))
    }

    @Test("all of ten returns the first failure")
    func allTenFirstFailure() {
        let result = all(
            Result<Int, TestError>.failure(.failed),
            Result<Int, TestError>.success(2),
            Result<Int, TestError>.success(3),
            Result<Int, TestError>.success(4),
            Result<Int, TestError>.success(5),
            Result<Int, TestError>.success(6),
            Result<Int, TestError>.success(7),
            Result<Int, TestError>.success(8),
            Result<Int, TestError>.success(9),
            Result<Int, TestError>.success(10)
        )

        let mapped = result.map { _, _, _, _, _, _, _, _, _, _ in 0 }
        #expect(mapped == .failure(.failed))
    }

    @Test("all of ten returns a failure in the last position")
    func allTenLastFailure() {
        let result = all(
            Result<Int, TestError>.success(1),
            Result<Int, TestError>.success(2),
            Result<Int, TestError>.success(3),
            Result<Int, TestError>.success(4),
            Result<Int, TestError>.success(5),
            Result<Int, TestError>.success(6),
            Result<Int, TestError>.success(7),
            Result<Int, TestError>.success(8),
            Result<Int, TestError>.success(9),
            Result<Int, TestError>.failure(.other)
        )

        let mapped = result.map { _, _, _, _, _, _, _, _, _, _ in 0 }
        #expect(mapped == .failure(.other))
    }

    // MARK: - AllAsync 6-10

    @Test("allAsync combines six async results in parallel")
    func allAsyncSix() async {
        @Sendable func val(_ n: Int) async -> Result<Int, TestError> {
            await Task.yield()
            return .success(n)
        }

        let result = await allAsync(
            await val(1),
            await val(2),
            await val(3),
            await val(4),
            await val(5),
            await val(6)
        )

        let sum = result.map { a, b, c, d, e, f in a + b + c + d + e + f }
        #expect(sum == .success(21))
    }

    @Test("allAsync combines seven async results in parallel")
    func allAsyncSeven() async {
        @Sendable func val(_ n: Int) async -> Result<Int, TestError> {
            await Task.yield()
            return .success(n)
        }

        let result = await allAsync(
            await val(1),
            await val(2),
            await val(3),
            await val(4),
            await val(5),
            await val(6),
            await val(7)
        )

        let sum = result.map { a, b, c, d, e, f, g in a + b + c + d + e + f + g }
        #expect(sum == .success(28))
    }

    @Test("allAsync combines eight async results in parallel")
    func allAsyncEight() async {
        @Sendable func val(_ n: Int) async -> Result<Int, TestError> {
            await Task.yield()
            return .success(n)
        }

        let result = await allAsync(
            await val(1),
            await val(2),
            await val(3),
            await val(4),
            await val(5),
            await val(6),
            await val(7),
            await val(8)
        )

        let sum = result.map { a, b, c, d, e, f, g, h in a + b + c + d + e + f + g + h }
        #expect(sum == .success(36))
    }

    @Test("allAsync combines nine async results in parallel")
    func allAsyncNine() async {
        @Sendable func val(_ n: Int) async -> Result<Int, TestError> {
            await Task.yield()
            return .success(n)
        }

        let result = await allAsync(
            await val(1),
            await val(2),
            await val(3),
            await val(4),
            await val(5),
            await val(6),
            await val(7),
            await val(8),
            await val(9)
        )

        let sum = result.map { a, b, c, d, e, f, g, h, i in a + b + c + d + e + f + g + h + i }
        #expect(sum == .success(45))
    }

    @Test("allAsync combines ten async results in parallel")
    func allAsyncTen() async {
        @Sendable func val(_ n: Int) async -> Result<Int, TestError> {
            await Task.yield()
            return .success(n)
        }

        let result = await allAsync(
            await val(1),
            await val(2),
            await val(3),
            await val(4),
            await val(5),
            await val(6),
            await val(7),
            await val(8),
            await val(9),
            await val(10)
        )

        let sum = result.map { a, b, c, d, e, f, g, h, i, j in a + b + c + d + e + f + g + h + i + j
        }
        #expect(sum == .success(55))
    }

}
