import Testing

@testable import FP

@Suite("Result+DoAsync Tests")
struct ResultDoAsyncTests {
    enum TestError: Error, Equatable {
        case invalid
        case notFound
    }

    // MARK: - Basic bindAsync

    @Test("bindAsync with single bind returns success")
    func doSingleBindAsync() async {
        let result = await ResultDo<TestError>()
            .bindAsync { Result<Int, TestError>.success(42) }

        #expect(result == .success(42))
    }

    @Test("bindAsync with single bind returns failure")
    func doSingleBindAsyncFailure() async {
        let result = await ResultDo<TestError>()
            .bindAsync { Result<Int, TestError>.failure(.invalid) }

        #expect(result == .failure(.invalid))
    }

    @Test("bindAsync accumulates two values")
    func bindAsyncAccumulatesPair() async {
        let result = await ResultDo<TestError>()
            .bindAsync {
                await Task.yield()
                return Result<Int, TestError>.success(1)
            }
            .bindAsync { a in
                await Task.yield()
                return Result<String, TestError>.success("v-\(a)")
            }
            .map { a, b in "\(a):\(b)" }

        #expect(result == .success("1:v-1"))
    }

    @Test("bindAsync accumulates three values")
    func bindAsyncAccumulatesTriple() async {
        let result = await ResultDo<TestError>()
            .bindAsync { Result<Int, TestError>.success(1) }
            .bindAsync { a in Result<String, TestError>.success("v-\(a)") }
            .bindAsync { a, b in Result<Bool, TestError>.success(a > 0) }
            .map { a, b, c in "\(a):\(b):\(c)" }

        #expect(result == .success("1:v-1:true"))
    }

    @Test("bindAsync accumulates four values")
    func bindAsyncAccumulatesFour() async {
        let result = await ResultDo<TestError>()
            .bindAsync { Result<Int, TestError>.success(10) }
            .bindAsync { a in Result<Int, TestError>.success(a + 20) }
            .bindAsync { a, b in Result<Int, TestError>.success(a + b) }
            .bindAsync { a, b, c in Result<String, TestError>.success("\(a)+\(b)=\(c)") }
            .map { a, b, c, d in d }

        #expect(result == .success("10+30=40"))
    }

    @Test("bindAsync accumulates five values")
    func bindAsyncAccumulatesFive() async {
        let result = await ResultDo<TestError>()
            .bindAsync { Result<Int, TestError>.success(1) }
            .bindAsync { _ in Result<Int, TestError>.success(2) }
            .bindAsync { _, _ in Result<Int, TestError>.success(3) }
            .bindAsync { _, _, _ in Result<Int, TestError>.success(4) }
            .map { a, b, c, d in a + b + c + d }

        #expect(result == .success(10))
    }

    // MARK: - Short-circuiting

    @Test("bindAsync short-circuits on first failure")
    func bindAsyncShortCircuits() async {
        let counter = AsyncCounter()

        let result = await ResultDo<TestError>()
            .bindAsync { Result<Int, TestError>.success(1) }
            .bindAsync { _ -> Result<Int, TestError> in .failure(.invalid) }
            .bindAsync { _, _ -> Result<Int, TestError> in
                await counter.increment()
                return .success(3)
            }
            .map { a, b, c in a + b + c }

        #expect(result == .failure(.invalid))
        let count = await counter.count
        #expect(count == 0)
    }

    // MARK: - letAsync

    @Test("letAsync adds an async pure value")
    func letAsyncAddsPureValue() async {
        let result = await ResultDo<TestError>()
            .bindAsync { Result<Int, TestError>.success(42) }
            .letAsync { a in
                await Task.yield()
                return a * 2
            }
            .map { a, doubled in "\(a)->\(doubled)" }

        #expect(result == .success("42->84"))
    }

    @Test("letAsync works at the start of the chain")
    func letAsyncAtStart() async {
        let result = await ResultDo<TestError>()
            .letAsync {
                await Task.yield()
                return 42
            }

        #expect(result == .success(42))
    }

    @Test("letAsync is skipped on failure")
    func letAsyncSkippedOnFailure() async {
        let counter = AsyncCounter()

        let result = await ResultDo<TestError>()
            .bindAsync { Result<Int, TestError>.failure(.invalid) }
            .letAsync { _ -> Int in
                await counter.increment()
                return 42
            }
            .map { a, b in a + b }

        #expect(result == .failure(.invalid))
        let count = await counter.count
        #expect(count == 0)
    }

    // MARK: - Mixing sync and async

    @Test("sync bind chains with bindAsync")
    func syncThenAsync() async {
        let result = await ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(10) }
            .bindAsync { a in
                await Task.yield()
                return Result<Int, TestError>.success(a * 2)
            }
            .map { a, b in a + b }

        #expect(result == .success(30))
    }

    @Test("bindAsync chains with sync bind")
    func asyncThenSync() async {
        let result = await ResultDo<TestError>()
            .bindAsync {
                await Task.yield()
                return Result<Int, TestError>.success(10)
            }
            .bind { a in Result<Int, TestError>.success(a * 2) }
            .map { a, b in a + b }

        #expect(result == .success(30))
    }

    @Test("mixed sync let and letAsync")
    func mixedLetAndLetAsync() async {
        let result = await ResultDo<TestError>()
            .bind { Result<Int, TestError>.success(10) }
            .let { a in a * 2 }
            .letAsync { a, b in
                await Task.yield()
                return "\(a)->\(b)"
            }
            .map { a, b, str in str }

        #expect(result == .success("10->20"))
    }

    // MARK: - Chain ends with mapAsync

    @Test("chain ends with mapAsync")
    func chainEndsWithMapAsync() async {
        let result = await ResultDo<TestError>()
            .bindAsync { Result<Int, TestError>.success(5) }
            .bindAsync { a in Result<Int, TestError>.success(a * 3) }
            .mapAsync { (a, b) in
                await Task.yield()
                return "\(a) * 3 = \(b)"
            }

        #expect(result == .success("5 * 3 = 15"))
    }

    // MARK: - Full arity ladder

    @Test("bindAsync accumulates ten values, exercising every arity")
    func bindAsyncAccumulatesTen() async {
        let result = await ResultDo<TestError>()
            .bindAsync { Result<Int, TestError>.success(1) }
            .bindAsync { _ in Result<Int, TestError>.success(2) }
            .bindAsync { _, _ in Result<Int, TestError>.success(3) }
            .bindAsync { _, _, _ in Result<Int, TestError>.success(4) }
            .bindAsync { _, _, _, _ in Result<Int, TestError>.success(5) }
            .bindAsync { _, _, _, _, _ in Result<Int, TestError>.success(6) }
            .bindAsync { _, _, _, _, _, _ in Result<Int, TestError>.success(7) }
            .bindAsync { _, _, _, _, _, _, _ in Result<Int, TestError>.success(8) }
            .bindAsync { _, _, _, _, _, _, _, _ in Result<Int, TestError>.success(9) }
            .bindAsync { _, _, _, _, _, _, _, _, _ in Result<Int, TestError>.success(10) }
            .map { a, b, c, d, e, f, g, h, i, j in a + b + c + d + e + f + g + h + i + j }

        #expect(result == .success(55))
    }

    @Test("letAsync accumulates ten values, exercising every arity")
    func letAsyncAccumulatesTen() async {
        // typed step-by-step: a single 10-deep chain exceeds the
        // type checker's inference budget
        let one: Result<Int, TestError> = await ResultDo<TestError>().letAsync { 1 }
        let two: Result<(Int, Int), TestError> = await one.letAsync { a in a + 1 }
        let three: Result<(Int, Int, Int), TestError> = await two.letAsync { _, b in b + 1 }
        let four: Result<(Int, Int, Int, Int), TestError> =
            await three.letAsync { _, _, c in c + 1 }
        let five: Result<(Int, Int, Int, Int, Int), TestError> =
            await four.letAsync { _, _, _, d in d + 1 }
        let six: Result<(Int, Int, Int, Int, Int, Int), TestError> =
            await five.letAsync { _, _, _, _, e in e + 1 }
        let seven: Result<(Int, Int, Int, Int, Int, Int, Int), TestError> =
            await six.letAsync { _, _, _, _, _, f in f + 1 }
        let eight: Result<(Int, Int, Int, Int, Int, Int, Int, Int), TestError> =
            await seven.letAsync { _, _, _, _, _, _, g in g + 1 }
        let nine: Result<(Int, Int, Int, Int, Int, Int, Int, Int, Int), TestError> =
            await eight.letAsync { _, _, _, _, _, _, _, h in h + 1 }
        let ten: Result<(Int, Int, Int, Int, Int, Int, Int, Int, Int, Int), TestError> =
            await nine.letAsync { _, _, _, _, _, _, _, _, i in i + 1 }

        let result = ten.map { a, b, c, d, e, f, g, h, i, j in
            a + b + c + d + e + f + g + h + i + j
        }
        #expect(result == .success(55))
    }

    @Test("ten-step async chain short-circuits at a late failure")
    func tenStepAsyncChainShortCircuitsLate() async {
        let counter = AsyncCounter()
        func step(_ n: Int) async -> Result<Int, TestError> {
            await counter.increment()
            return n == 7 ? .failure(.invalid) : .success(n)
        }

        let result = await ResultDo<TestError>()
            .bindAsync { await step(1) }
            .bindAsync { _ in await step(2) }
            .bindAsync { _, _ in await step(3) }
            .bindAsync { _, _, _ in await step(4) }
            .bindAsync { _, _, _, _ in await step(5) }
            .bindAsync { _, _, _, _, _ in await step(6) }
            .bindAsync { _, _, _, _, _, _ in await step(7) }
            .bindAsync { _, _, _, _, _, _, _ in await step(8) }
            .bindAsync { _, _, _, _, _, _, _, _ in await step(9) }
            .bindAsync { _, _, _, _, _, _, _, _, _ in await step(10) }
            .map { a, _, _, _, _, _, _, _, _, _ in a }

        let stepsRun = await counter.count
        #expect(result == .failure(.invalid))
        #expect(stepsRun == 7)
    }

    @Test("ten-step async chain passes a first-step failure through every bindAsync arity")
    func tenStepAsyncChainShortCircuitsEarly() async {
        let counter = AsyncCounter()
        func step(_ n: Int) async -> Result<Int, TestError> {
            await counter.increment()
            return n == 1 ? .failure(.notFound) : .success(n)
        }

        let result = await ResultDo<TestError>()
            .bindAsync { await step(1) }
            .bindAsync { _ in await step(2) }
            .bindAsync { _, _ in await step(3) }
            .bindAsync { _, _, _ in await step(4) }
            .bindAsync { _, _, _, _ in await step(5) }
            .bindAsync { _, _, _, _, _ in await step(6) }
            .bindAsync { _, _, _, _, _, _ in await step(7) }
            .bindAsync { _, _, _, _, _, _, _ in await step(8) }
            .bindAsync { _, _, _, _, _, _, _, _ in await step(9) }
            .bindAsync { _, _, _, _, _, _, _, _, _ in await step(10) }
            .map { a, _, _, _, _, _, _, _, _, _ in a }

        let stepsRun = await counter.count
        #expect(result == .failure(.notFound))
        #expect(stepsRun == 1)
    }

    @Test("letAsync passes an existing failure through every arity")
    func letAsyncPassesFailureThroughAllArities() async {
        let one: Result<Int, TestError> = await ResultDo<TestError>()
            .bindAsync { Result<Int, TestError>.failure(.invalid) }
        let two: Result<(Int, Int), TestError> = await one.letAsync { a in a + 1 }
        let three: Result<(Int, Int, Int), TestError> = await two.letAsync { _, b in b + 1 }
        let four: Result<(Int, Int, Int, Int), TestError> =
            await three.letAsync { _, _, c in c + 1 }
        let five: Result<(Int, Int, Int, Int, Int), TestError> =
            await four.letAsync { _, _, _, d in d + 1 }
        let six: Result<(Int, Int, Int, Int, Int, Int), TestError> =
            await five.letAsync { _, _, _, _, e in e + 1 }
        let seven: Result<(Int, Int, Int, Int, Int, Int, Int), TestError> =
            await six.letAsync { _, _, _, _, _, f in f + 1 }
        let eight: Result<(Int, Int, Int, Int, Int, Int, Int, Int), TestError> =
            await seven.letAsync { _, _, _, _, _, _, g in g + 1 }
        let nine: Result<(Int, Int, Int, Int, Int, Int, Int, Int, Int), TestError> =
            await eight.letAsync { _, _, _, _, _, _, _, h in h + 1 }
        let ten: Result<(Int, Int, Int, Int, Int, Int, Int, Int, Int, Int), TestError> =
            await nine.letAsync { _, _, _, _, _, _, _, _, i in i + 1 }

        let result = ten.map { a, _, _, _, _, _, _, _, _, _ in a }
        #expect(result == .failure(.invalid))
    }
}
