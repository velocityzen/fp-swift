import Testing

@testable import FP

@Suite("Result+Tuple Tests")
struct ResultTupleTests {
    enum TestError: Error, Equatable {
        case failed
        case other
    }

    // MARK: - Flatten 2

    @Test("flatten 2 succeeds with both results")
    func flatten2Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("hello")

        let result = flatten(a, b)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "hello")
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("flatten 2 fails when first fails")
    func flatten2FailsFirst() {
        let a: Result<Int, TestError> = .failure(.failed)
        let b: Result<String, TestError> = .success("hello")

        let result = flatten(a, b)

        if case .failure(let error) = result {
            #expect(error == .failed)
        } else {
            Issue.record("Expected failure")
        }
    }

    @Test("flatten 2 fails when second fails")
    func flatten2FailsSecond() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .failure(.other)

        let result = flatten(a, b)

        if case .failure(let error) = result {
            #expect(error == .other)
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - Flatten 3

    @Test("flatten 3 succeeds with all results")
    func flatten3Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("hello")
        let c: Result<Double, TestError> = .success(3.14)

        let result = flatten(a, b, c)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "hello")
            #expect(value.2 == 3.14)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("flatten 3 fails when any fails")
    func flatten3Fails() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .failure(.failed)
        let c: Result<Double, TestError> = .success(3.14)

        let result = flatten(a, b, c)

        if case .failure(let error) = result {
            #expect(error == .failed)
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - Flatten 4

    @Test("flatten 4 succeeds with all results")
    func flatten4Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("hello")
        let c: Result<Double, TestError> = .success(3.14)
        let d: Result<Bool, TestError> = .success(true)

        let result = flatten(a, b, c, d)

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "hello")
            #expect(value.2 == 3.14)
            #expect(value.3 == true)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("flatten 4 fails when any fails")
    func flatten4Fails() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("hello")
        let c: Result<Double, TestError> = .success(3.14)
        let d: Result<Bool, TestError> = .failure(.other)

        let result = flatten(a, b, c, d)

        if case .failure(let error) = result {
            #expect(error == .other)
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - Flatten 5

    @Test("flatten 5 succeeds with all results")
    func flatten5Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("a")
        let c: Result<Int, TestError> = .success(2)
        let d: Result<String, TestError> = .success("b")
        let f: Result<Int, TestError> = .success(3)

        let result = flatten(a, b, c, d, f)

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

    // MARK: - Flatten 6

    @Test("flatten 6 succeeds with all results")
    func flatten6Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("a")
        let c: Result<Int, TestError> = .success(2)
        let d: Result<String, TestError> = .success("b")
        let f: Result<Int, TestError> = .success(3)
        let g: Result<String, TestError> = .success("c")

        let result = flatten(a, b, c, d, f, g)

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

    @Test("flatten with named tuple via map")
    func flattenWithNamedTuple() {
        let a: Result<Int, TestError> = .success(42)
        let b: Result<String, TestError> = .success("hello")

        let result = flatten(a, b).map { (id: $0, name: $1) }

        if case .success(let value) = result {
            #expect(value.id == 42)
            #expect(value.name == "hello")
        } else {
            Issue.record("Expected success")
        }
    }

    // MARK: - Flatten 7

    @Test("flatten 7 succeeds with all results")
    func flatten7Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("a")
        let c: Result<Int, TestError> = .success(2)
        let d: Result<String, TestError> = .success("b")
        let f: Result<Int, TestError> = .success(3)
        let g: Result<String, TestError> = .success("c")
        let h: Result<Int, TestError> = .success(4)

        let result = flatten(a, b, c, d, f, g, h)

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

    // MARK: - Flatten 8

    @Test("flatten 8 succeeds with all results")
    func flatten8Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("a")
        let c: Result<Int, TestError> = .success(2)
        let d: Result<String, TestError> = .success("b")
        let f: Result<Int, TestError> = .success(3)
        let g: Result<String, TestError> = .success("c")
        let h: Result<Int, TestError> = .success(4)
        let i: Result<String, TestError> = .success("d")

        let result = flatten(a, b, c, d, f, g, h, i)

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

    // MARK: - Flatten 9

    @Test("flatten 9 succeeds with all results")
    func flatten9Succeeds() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .success("a")
        let c: Result<Int, TestError> = .success(2)
        let d: Result<String, TestError> = .success("b")
        let f: Result<Int, TestError> = .success(3)
        let g: Result<String, TestError> = .success("c")
        let h: Result<Int, TestError> = .success(4)
        let i: Result<String, TestError> = .success("d")
        let j: Result<Int, TestError> = .success(5)

        let result = flatten(a, b, c, d, f, g, h, i, j)

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

    // MARK: - Flatten 10

    @Test("flatten 10 succeeds with all results")
    func flatten10Succeeds() {
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

        let result = flatten(a, b, c, d, f, g, h, i, j, k)

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

    @Test("flatten preserves typed error")
    func flattenPreservesErrorType() {
        let a: Result<Int, TestError> = .success(1)
        let b: Result<String, TestError> = .failure(.failed)

        let result: Result<(Int, String), TestError> = flatten(a, b)

        if case .failure(let error) = result {
            #expect(error == .failed)
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - Async flattenAsync Tests

    @Test("flattenAsync 2 succeeds with both async results")
    func flattenAsync2Succeeds() async {
        let getInt: @Sendable () async -> Result<Int, TestError> = { .success(1) }
        let getString: @Sendable () async -> Result<String, TestError> = { .success("hello") }

        let result = await flattenAsync(await getInt(), await getString())

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "hello")
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("flattenAsync 2 fails when any async result fails")
    func flattenAsync2Fails() async {
        let getInt: @Sendable () async -> Result<Int, TestError> = { .success(1) }
        let getString: @Sendable () async -> Result<String, TestError> = { .failure(.failed) }

        let result = await flattenAsync(await getInt(), await getString())

        if case .failure(let error) = result {
            #expect(error == .failed)
        } else {
            Issue.record("Expected failure")
        }
    }

    @Test("flattenAsync 3 succeeds with all async results")
    func flattenAsync3Succeeds() async {
        let getA: @Sendable () async -> Result<Int, TestError> = { .success(1) }
        let getB: @Sendable () async -> Result<String, TestError> = { .success("a") }
        let getC: @Sendable () async -> Result<Double, TestError> = { .success(3.14) }

        let result = await flattenAsync(await getA(), await getB(), await getC())

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "a")
            #expect(value.2 == 3.14)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("flattenAsync 4 succeeds with all async results")
    func flattenAsync4Succeeds() async {
        let getA: @Sendable () async -> Result<Int, TestError> = { .success(1) }
        let getB: @Sendable () async -> Result<String, TestError> = { .success("a") }
        let getC: @Sendable () async -> Result<Double, TestError> = { .success(3.14) }
        let getD: @Sendable () async -> Result<Bool, TestError> = { .success(true) }

        let result = await flattenAsync(await getA(), await getB(), await getC(), await getD())

        if case .success(let value) = result {
            #expect(value.0 == 1)
            #expect(value.1 == "a")
            #expect(value.2 == 3.14)
            #expect(value.3 == true)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test("flattenAsync preserves typed error for async operations")
    func flattenAsyncPreservesError() async {
        let getInt: @Sendable () async -> Result<Int, TestError> = { .failure(.other) }
        let getString: @Sendable () async -> Result<String, TestError> = { .success("hello") }

        let result: Result<(Int, String), TestError> = await flattenAsync(
            await getInt(),
            await getString()
        )

        if case .failure(let error) = result {
            #expect(error == .other)
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - Flatten 10 (full arity ladder)

    @Test("flatten combines ten results, exercising every arity")
    func flattenTenSuccess() {
        let result = flatten(
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

    @Test("flatten of ten returns the first failure")
    func flattenTenFirstFailure() {
        let result = flatten(
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

    @Test("flatten of ten returns a failure in the last position")
    func flattenTenLastFailure() {
        let result = flatten(
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

    // MARK: - FlattenAsync 6-10

    @Test("flattenAsync combines six async results in parallel")
    func flattenAsyncSix() async {
        @Sendable func val(_ n: Int) async -> Result<Int, TestError> {
            await Task.yield()
            return .success(n)
        }

        let result = await flattenAsync(
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

    @Test("flattenAsync combines seven async results in parallel")
    func flattenAsyncSeven() async {
        @Sendable func val(_ n: Int) async -> Result<Int, TestError> {
            await Task.yield()
            return .success(n)
        }

        let result = await flattenAsync(
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

    @Test("flattenAsync combines eight async results in parallel")
    func flattenAsyncEight() async {
        @Sendable func val(_ n: Int) async -> Result<Int, TestError> {
            await Task.yield()
            return .success(n)
        }

        let result = await flattenAsync(
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

    @Test("flattenAsync combines nine async results in parallel")
    func flattenAsyncNine() async {
        @Sendable func val(_ n: Int) async -> Result<Int, TestError> {
            await Task.yield()
            return .success(n)
        }

        let result = await flattenAsync(
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

    @Test("flattenAsync combines ten async results in parallel")
    func flattenAsyncTen() async {
        @Sendable func val(_ n: Int) async -> Result<Int, TestError> {
            await Task.yield()
            return .success(n)
        }

        let result = await flattenAsync(
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
