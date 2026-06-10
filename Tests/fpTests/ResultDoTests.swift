import Testing

@testable import FP

@Suite("Result+Do Tests")
struct ResultDoTests {
    enum TestError: Error, Equatable {
        case invalid
        case notFound
    }

    // MARK: - Basic Do / bind

    @Test("Do with single bind returns success")
    func doSingleBind() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(42) }

        #expect(result == .success(42))
    }

    @Test("Do with single bind returns failure")
    func doSingleBindFailure() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.failure(.invalid) }

        #expect(result == .failure(.invalid))
    }

    @Test("bind accumulates two values into a pair")
    func bindAccumulatesPair() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(1) }
            .bind { a in Result<String, TestError>.success("v-\(a)") }
            .map { a, b in "\(a):\(b)" }

        #expect(result == .success("1:v-1"))
    }

    @Test("bind accumulates three values into a triple")
    func bindAccumulatesTriple() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(1) }
            .bind { a in Result<String, TestError>.success("v-\(a)") }
            .bind { a, b in Result<Bool, TestError>.success(a > 0) }
            .map { a, b, c in "\(a):\(b):\(c)" }

        #expect(result == .success("1:v-1:true"))
    }

    @Test("bind accumulates four values")
    func bindAccumulatesFour() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(10) }
            .bind { a in Result<Int, TestError>.success(a + 20) }
            .bind { a, b in Result<Int, TestError>.success(a + b) }
            .bind { a, b, c in Result<String, TestError>.success("\(a)+\(b)=\(c)") }
            .map { a, b, c, d in "\(a),\(b),\(c),\(d)" }

        #expect(result == .success("10,30,40,10+30=40"))
    }

    @Test("bind accumulates five values")
    func bindAccumulatesFive() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(1) }
            .bind { _ in Result<Int, TestError>.success(2) }
            .bind { _, _ in Result<Int, TestError>.success(3) }
            .bind { _, _, _ in Result<Int, TestError>.success(4) }
            .map { a, b, c, d in a + b + c + d }

        #expect(result == .success(10))
    }

    // MARK: - Short-circuiting

    @Test("bind short-circuits on first failure")
    func bindShortCircuits() {
        var reached = false

        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(1) }
            .bind { _ -> Result<Int, TestError> in .failure(.invalid) }
            .bind { _, _ -> Result<Int, TestError> in
                reached = true
                return .success(3)
            }
            .map { a, b, c in a + b + c }

        #expect(result == .failure(.invalid))
        #expect(reached == false)
    }

    @Test("bind returns first failure when multiple would fail")
    func bindReturnsFirstFailure() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.failure(.notFound) }
            .bind { _ in Result<Int, TestError>.failure(.invalid) }
            .map { a, b in a + b }

        #expect(result == .failure(.notFound))
    }

    // MARK: - let

    @Test("let adds a pure value to the chain")
    func letAddsPureValue() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(42) }
            .let { a in a * 2 }
            .map { a, doubled in "\(a)->\(doubled)" }

        #expect(result == .success("42->84"))
    }

    @Test("let works at the start of the chain")
    func letAtStart() {
        let result = ResultDo<TestError>()
            .let { 42 }

        #expect(result == .success(42))
    }

    @Test("let accumulates with bind")
    func letAccumulatesWithBind() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(10) }
            .let { a in a * 2 }
            .bind { a, doubled in Result<String, TestError>.success("\(a)->\(doubled)") }
            .map { a, doubled, str in str }

        #expect(result == .success("10->20"))
    }

    @Test("let is skipped on failure")
    func letSkippedOnFailure() {
        var reached = false

        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.failure(.invalid) }
            .let { _ -> Int in
                reached = true
                return 42
            }
            .map { a, b in a + b }

        #expect(result == .failure(.invalid))
        #expect(reached == false)
    }

    // MARK: - Chaining with map / flatMap

    @Test("chain ends with map to extract final value")
    func chainEndsWithMap() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(10) }
            .bind { a in Result<Int, TestError>.success(a * 2) }
            .map { a, b in a + b }

        #expect(result == .success(30))
    }

    @Test("chain ends with flatMap")
    func chainEndsWithFlatMap() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(5) }
            .bind { a in Result<Int, TestError>.success(a * 3) }
            .flatMap { (a, b) -> Result<String, TestError> in
                b > 10
                    ? .success("\(a) * 3 = \(b)")
                    : .failure(.invalid)
            }

        #expect(result == .success("5 * 3 = 15"))
    }

    // MARK: - Mixed types

    @Test("bind works with different Success types across steps")
    func bindDifferentTypes() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(42) }
            .bind { _ in Result<String, TestError>.success("hello") }
            .bind { _, _ in Result<Bool, TestError>.success(true) }
            .map { num, str, flag in flag ? "\(str)-\(num)" : "none" }

        #expect(result == .success("hello-42"))
    }

    // MARK: - Nested Do

    @Test("Do blocks can be nested")
    func doNested() {
        let inner = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(10) }
            .bind { a in Result<Int, TestError>.success(a * 2) }
            .map { _, b in b }

        let result = ResultDo<TestError>()
            .bind { inner }
            .bind { value in Result<String, TestError>.success("result: \(value)") }
            .map { _, str in str }

        #expect(result == .success("result: 20"))
    }

    @Test("nested Do propagates inner failure")
    func doNestedPropagatesFailure() {
        let inner = ResultDo<TestError>()
            .bind { Result<Int, TestError>.failure(.notFound) }

        let result = ResultDo<TestError>()
            .bind { inner }
            .bind { _ in Result<String, TestError>.success("unreachable") }
            .map { _, str in str }

        #expect(result == .failure(.notFound))
    }

    // MARK: - Full arity ladder

    @Test("bind accumulates ten values, exercising every arity")
    func bindAccumulatesTen() {
        let result = ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(1) }
            .bind { _ in Result<Int, TestError>.success(2) }
            .bind { _, _ in Result<Int, TestError>.success(3) }
            .bind { _, _, _ in Result<Int, TestError>.success(4) }
            .bind { _, _, _, _ in Result<Int, TestError>.success(5) }
            .bind { _, _, _, _, _ in Result<Int, TestError>.success(6) }
            .bind { _, _, _, _, _, _ in Result<Int, TestError>.success(7) }
            .bind { _, _, _, _, _, _, _ in Result<Int, TestError>.success(8) }
            .bind { _, _, _, _, _, _, _, _ in Result<Int, TestError>.success(9) }
            .bind { _, _, _, _, _, _, _, _, _ in Result<Int, TestError>.success(10) }
            .map { a, b, c, d, e, f, g, h, i, j in a + b + c + d + e + f + g + h + i + j }

        #expect(result == .success(55))
    }

    @Test("let accumulates ten values, exercising every arity")
    func letAccumulatesTen() {
        // typed step-by-step: a single 10-deep chain exceeds the
        // type checker's inference budget
        let one: Result<Int, TestError> = ResultDo<TestError>().let { 1 }
        let two: Result<(Int, Int), TestError> = one.let { a in a + 1 }
        let three: Result<(Int, Int, Int), TestError> = two.let { _, b in b + 1 }
        let four: Result<(Int, Int, Int, Int), TestError> = three.let { _, _, c in c + 1 }
        let five: Result<(Int, Int, Int, Int, Int), TestError> =
            four.let { _, _, _, d in d + 1 }
        let six: Result<(Int, Int, Int, Int, Int, Int), TestError> =
            five.let { _, _, _, _, e in e + 1 }
        let seven: Result<(Int, Int, Int, Int, Int, Int, Int), TestError> =
            six.let { _, _, _, _, _, f in f + 1 }
        let eight: Result<(Int, Int, Int, Int, Int, Int, Int, Int), TestError> =
            seven.let { _, _, _, _, _, _, g in g + 1 }
        let nine: Result<(Int, Int, Int, Int, Int, Int, Int, Int, Int), TestError> =
            eight.let { _, _, _, _, _, _, _, h in h + 1 }
        let ten: Result<(Int, Int, Int, Int, Int, Int, Int, Int, Int, Int), TestError> =
            nine.let { _, _, _, _, _, _, _, _, i in i + 1 }

        let result = ten.map { a, b, c, d, e, f, g, h, i, j in
            a + b + c + d + e + f + g + h + i + j
        }
        #expect(result == .success(55))
    }

    @Test("ten-step chain short-circuits at a late failure")
    func tenStepChainShortCircuitsLate() {
        nonisolated(unsafe) var stepsRun = 0
        func step(_ n: Int) -> Result<Int, TestError> {
            stepsRun += 1
            return n == 7 ? .failure(.invalid) : .success(n)
        }

        let result = ResultDo<TestError>()
            .bind { step(1) }
            .bind { _ in step(2) }
            .bind { _, _ in step(3) }
            .bind { _, _, _ in step(4) }
            .bind { _, _, _, _ in step(5) }
            .bind { _, _, _, _, _ in step(6) }
            .bind { _, _, _, _, _, _ in step(7) }
            .bind { _, _, _, _, _, _, _ in step(8) }
            .bind { _, _, _, _, _, _, _, _ in step(9) }
            .bind { _, _, _, _, _, _, _, _, _ in step(10) }
            .map { a, _, _, _, _, _, _, _, _, _ in a }

        #expect(result == .failure(.invalid))
        #expect(stepsRun == 7)
    }

    // MARK: - Result.Do accessor

    @Test("Result.Do starts a chain")
    func resultDoAccessorStartsChain() {
        let result = Result<Int, TestError>.Do
            .bind { Result<Int, TestError>.success(21) }
            .let { a in a * 2 }
            .map { _, b in b }

        #expect(result == .success(42))
    }
}
