import XCTest

@testable import fp_swift

final class IOTests: XCTestCase {

    // MARK: - Basic IO functionality tests

    func testIOPure() {
        let io = IO.pure(42)
        let result = io.unsafePerformIO()
        XCTAssertEqual(result, 42)
    }

    func testIOReturn() {
        let io = IO.return("hello")
        let result = io.unsafePerformIO()
        XCTAssertEqual(result, "hello")
    }

    func testIODelay() {
        var sideEffectExecuted = false
        let io = IO.delay {
            sideEffectExecuted = true
            return "delayed"
        }

        // Side effect should not be executed until unsafePerformIO is called
        XCTAssertFalse(sideEffectExecuted)

        let result = io.unsafePerformIO()
        XCTAssertTrue(sideEffectExecuted)
        XCTAssertEqual(result, "delayed")
    }

    func testIOEffect() {
        var counter = 0
        let io = IO<Void>.effect { counter += 1 }

        XCTAssertEqual(counter, 0)
        io.unsafePerformIO()
        XCTAssertEqual(counter, 1)
    }

    // MARK: - Functor tests (map)

    func testIOMap() {
        let io = IO.pure(5)
        let mappedIO = io.map { $0 * 2 }
        let result = mappedIO.unsafePerformIO()
        XCTAssertEqual(result, 10)
    }

    func testIOMapPipeOperator() {
        let io = IO.pure(3)
        let result = (io |> { $0 + 1 }).unsafePerformIO()
        XCTAssertEqual(result, 4)
    }

    func testIOMapChaining() {
        let io = IO.pure(2)
        let result = (io |> { $0 * 3 } |> { $0 + 1 }).unsafePerformIO()
        XCTAssertEqual(result, 7)
    }

    // MARK: - Monad tests (flatMap)

    func testIOFlatMap() {
        let io1 = IO.pure(5)
        let io2 = io1.flatMap { value in
            IO.pure(value * 2)
        }
        let result = io2.unsafePerformIO()
        XCTAssertEqual(result, 10)
    }

    func testIOFlatMapPipeOperator() {
        let io = IO.pure(4)
        let result = (io |> { value in IO.pure(value + 1) }).unsafePerformIO()
        XCTAssertEqual(result, 5)
    }

    func testIOMonadLaws() {
        // Left identity: return a >>= f === f a
        let a = 42
        let f: (Int) -> IO<String> = { IO.pure("\($0)") }

        let leftSide = IO.return(a).flatMap(f)
        let rightSide = f(a)

        XCTAssertEqual(leftSide.unsafePerformIO(), rightSide.unsafePerformIO())

        // Right identity: m >>= return === m
        let m = IO.pure(42)
        let leftSide2 = m.flatMap(IO.return)

        XCTAssertEqual(leftSide2.unsafePerformIO(), m.unsafePerformIO())

        // Associativity: (m >>= f) >>= g === m >>= (\x -> f x >>= g)
        let g: (String) -> IO<Int> = { IO.pure($0.count) }

        let leftSide3 = m.flatMap(f).flatMap(g)
        let rightSide3 = m.flatMap { x in f(x).flatMap(g) }

        XCTAssertEqual(leftSide3.unsafePerformIO(), rightSide3.unsafePerformIO())
    }

    // MARK: - Applicative tests

    func testIOApply() {
        let functionIO = IO.pure { (x: Int) in x * 2 }
        let valueIO = IO.pure(5)
        let result = valueIO.apply(functionIO)

        XCTAssertEqual(result.unsafePerformIO(), 10)
    }

    func testIOApplyOperator() {
        let functionIO = IO.pure { (x: Int) in x + 1 }
        let valueIO = IO.pure(9)
        let result = functionIO <*> valueIO

        XCTAssertEqual(result.unsafePerformIO(), 10)
    }

    // MARK: - Sequencing operations tests

    func testIOThen() {
        var effects: [String] = []

        let io1 = IO<Void>.effect { effects.append("first") }
        let io2 = IO<Void>.effect { effects.append("second") }

        let combined = io1.then(io2)
        combined.unsafePerformIO()

        XCTAssertEqual(effects, ["first", "second"])
    }

    func testIOBefore() {
        var effects: [String] = []

        let io1 = IO {
            effects.append("first")
            return "result1"
        }
        let io2 = IO<Void>.effect { effects.append("second") }

        let combined = io1.before(io2)
        let result = combined.unsafePerformIO()

        XCTAssertEqual(effects, ["first", "second"])
        XCTAssertEqual(result, "result1")
    }

    func testIOSequenceOperators() {
        var counter = 0

        let io1 = IO {
            counter += 1
            return "first"
        }
        let io2 = IO {
            counter += 10
            return "second"
        }

        // Test *> (sequence, keep second result)
        let keepSecond = io1 *> io2
        let result1 = keepSecond.unsafePerformIO()
        XCTAssertEqual(result1, "second")
        XCTAssertEqual(counter, 11)

        counter = 0

        // Test <* (sequence, keep first result)
        let keepFirst = io1 <* io2
        let result2 = keepFirst.unsafePerformIO()
        XCTAssertEqual(result2, "first")
        XCTAssertEqual(counter, 11)
    }

    // MARK: - Repetition and conditional tests

    func testIORepeated() {
        var counter = 0
        let io = IO {
            counter += 1
            return counter
        }

        let repeated = io.repeated(3)
        let results = repeated.unsafePerformIO()

        XCTAssertEqual(results, [1, 2, 3])
        XCTAssertEqual(counter, 3)
    }

    func testIORepeatedZeroTimes() {
        let io = IO.pure(42)
        let repeated = io.repeated(0)
        let results = repeated.unsafePerformIO()

        XCTAssertEqual(results, [])
    }

    func testIOWhen() {
        var executed = false
        let action = IO<Void>.effect { executed = true }

        // When condition is true
        IO<Void>.when(true, action).unsafePerformIO()
        XCTAssertTrue(executed)

        executed = false

        // When condition is false
        IO<Void>.when(false, action).unsafePerformIO()
        XCTAssertFalse(executed)
    }

    func testIOIfThenElse() {
        let thenAction = IO.pure("then")
        let elseAction = IO.pure("else")

        let result1 = IO<String>.ifThenElse(true, thenAction, elseAction).unsafePerformIO()
        XCTAssertEqual(result1, "then")

        let result2 = IO<String>.ifThenElse(false, thenAction, elseAction).unsafePerformIO()
        XCTAssertEqual(result2, "else")
    }

    // MARK: - Sequence and traverse tests

    func testIOSequence() {
        let ios = [
            IO.pure(1),
            IO.pure(2),
            IO.pure(3),
        ]

        let sequenced = IO.sequence(ios)
        let results = sequenced.unsafePerformIO()

        XCTAssertEqual(results, [1, 2, 3])
    }

    func testIOTraverse() {
        let numbers = [1, 2, 3]
        let traversed = IO<[Int]>.traverse(numbers) { IO.pure($0 * 2) }
        let results = traversed.unsafePerformIO()

        XCTAssertEqual(results, [2, 4, 6])
    }

    // MARK: - Common IO operations tests

    func testIOPrint() {
        // Note: This test doesn't verify actual console output
        // In a real scenario, you might want to redirect stdout for testing
        let printIO = IO.print("Hello, World!")

        // Should not crash
        printIO.unsafePerformIO()
    }

    func testIOTimed() {
        let io = IO {
            Thread.sleep(forTimeInterval: 0.1)
            return "done"
        }
        let timedIO = io.timed()

        let (result, timeInterval) = timedIO.unsafePerformIO()

        XCTAssertEqual(result, "done")
        XCTAssertGreaterThan(timeInterval, 0.05)  // Should be at least ~0.1 seconds
    }

    // MARK: - Error handling and retry tests

    func testIORetry() {
        var attemptCount = 0
        let io = IO {
            attemptCount += 1
            return attemptCount
        }

        let retried = io.retry(3)
        let result = retried.unsafePerformIO()

        // Since our IO doesn't actually fail, it should succeed on first attempt
        XCTAssertEqual(result, 1)
        XCTAssertEqual(attemptCount, 1)
    }

    // MARK: - Side effect isolation tests

    func testIOSideEffectIsolation() {
        var counter = 0

        // Create IO actions but don't execute them
        let io1 = IO<Void>.effect { counter += 1 }
        let io2 = IO<Void>.effect { counter += 10 }
        let io3 = io1.then(io2)

        // Counter should still be 0 since we haven't executed any IO
        XCTAssertEqual(counter, 0)

        // Now execute one of them
        io1.unsafePerformIO()
        XCTAssertEqual(counter, 1)

        // The combined IO should still execute both effects
        counter = 0
        io3.unsafePerformIO()
        XCTAssertEqual(counter, 11)
    }

    // MARK: - Complex composition tests

    func testComplexIOComposition() {
        var log: [String] = []

        let logIO = { (message: String) in
            IO<Void>.effect { log.append(message) }
        }

        let step1 = logIO("Starting computation")
        let step2 = step1 *> IO.pure(5)
        let step3 =
            step2 |> { value in
                logIO("Got value: \(value)") *> IO.pure(value * 2)
            }
        let step4 =
            step3 |> { doubled in
                logIO("Doubled to: \(doubled)").then(IO.pure(doubled + 1))
            }
        let computation = step4 <* logIO("Computation complete")

        let result = computation.unsafePerformIO()

        XCTAssertEqual(result, 11)
        XCTAssertEqual(
            log,
            [
                "Starting computation",
                "Got value: 5",
                "Doubled to: 10",
                "Computation complete",
            ])
    }

    // MARK: - Description tests

    func testIODescription() {
        let io = IO.pure(42)
        XCTAssertEqual(io.description, "IO<Int>")
        XCTAssertTrue(io.debugDescription.contains("IO<Int>"))
        XCTAssertTrue(io.debugDescription.contains("deferred"))
    }
}
