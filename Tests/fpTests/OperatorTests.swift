import Testing

@testable import FP

@Suite("Operator Tests")
struct OperatorTests {

    // MARK: - |> (forward pipe)

    @Test("|> pipes value into function")
    func forwardPipe() {
        let result = 5 |> { $0 * 2 }
        #expect(result == 10)
    }

    @Test("|> chains multiple pipes")
    func forwardPipeChaining() {
        let result = 5 |> { $0 * 2 } |> { $0 + 1 } |> String.init
        #expect(result == "11")
    }

    @Test("|> works with string transformations")
    func forwardPipeStrings() {
        let result = "hello" |> { $0.uppercased() } |> { $0 + "!" }
        #expect(result == "HELLO!")
    }

    // MARK: - |>> (pipe into second argument)

    @Test("|>> pipes value as second argument")
    func pipeIntoSecond() {
        func join(_ separator: String, _ value: String) -> String {
            return separator + value
        }

        let result = "world" |>> (join, "hello ")
        #expect(result == "hello world")
    }

    @Test("|>> works with numeric operations")
    func pipeIntoSecondNumeric() {
        func subtract(_ a: Int, _ b: Int) -> Int {
            return a - b
        }

        let result = 3 |>> (subtract, 10)
        #expect(result == 7)
    }

    // MARK: - |>>> (pipe into third argument)

    @Test("|>>> pipes value as third argument")
    func pipeIntoThird() {
        func combine(_ a: String, _ b: String, _ c: String) -> String {
            return a + b + c
        }

        let result = "!" |>>> (combine, "hello", " world")
        #expect(result == "hello world!")
    }

    // MARK: - |< (pipe into last argument, same as |>)

    @Test("|< pipes value into function")
    func pipeIntoLast() {
        let result = 42 |< { $0 * 2 }
        #expect(result == 84)
    }

    @Test("|< chains with |>")
    func pipeIntoLastChaining() {
        let result = 5 |> { $0 * 2 } |< { $0 + 1 }
        #expect(result == 11)
    }

    // MARK: - prefix |> (flow operator)

    @Test("prefix |> creates a function from another function")
    func flowOperator() {
        let double: (Int) -> Int = (|>)({ $0 * 2 })
        #expect(double(5) == 10)
    }

    @Test("prefix |> composed function works in pipe chain")
    func flowOperatorInChain() {
        let addOne: (Int) -> Int = (|>)({ $0 + 1 })
        let result = 5 |> addOne
        #expect(result == 6)
    }
}
