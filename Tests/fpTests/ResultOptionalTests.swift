import Testing

@testable import fp_swift

@Suite("Result+Optional Tests")
struct ResultOptionalTests {
    enum TestError: Error, Equatable {
        case missing
        case notFound
        case invalid(String)
    }

    // MARK: - fromOptional with error value

    @Test("fromOptional returns success when optional has value")
    func fromOptionalSuccessWithValue() {
        let optional: Int? = 42

        let result = Result<Int, TestError>.fromOptional(optional, error: .missing)

        #expect(result == .success(42))
    }

    @Test("fromOptional returns failure when optional is nil")
    func fromOptionalFailureWhenNil() {
        let optional: Int? = nil

        let result = Result<Int, TestError>.fromOptional(optional, error: .missing)

        #expect(result == .failure(.missing))
    }

    @Test("fromOptional works with string type")
    func fromOptionalWithString() {
        let optional: String? = "hello"

        let result = Result<String, TestError>.fromOptional(optional, error: .notFound)

        #expect(result == .success("hello"))
    }

    @Test("fromOptional returns correct error type")
    func fromOptionalCorrectErrorType() {
        let optional: String? = nil

        let result = Result<String, TestError>.fromOptional(optional, error: .notFound)

        #expect(result == .failure(.notFound))
    }

    @Test("fromOptional works with complex types")
    func fromOptionalComplexType() {
        struct User: Equatable {
            let id: Int
            let name: String
        }

        let optional: User? = User(id: 1, name: "Alice")

        let result = Result<User, TestError>.fromOptional(optional, error: .missing)

        #expect(result == .success(User(id: 1, name: "Alice")))
    }

    // MARK: - fromOptional with error closure

    @Test("fromOptional with closure returns success when optional has value")
    func fromOptionalClosureSuccessWithValue() {
        let optional: Int? = 42

        let result = Result<Int, TestError>.fromOptional(optional) {
            .missing
        }

        #expect(result == .success(42))
    }

    @Test("fromOptional with closure returns failure when optional is nil")
    func fromOptionalClosureFailureWhenNil() {
        let optional: Int? = nil

        let result = Result<Int, TestError>.fromOptional(optional) {
            .missing
        }

        #expect(result == .failure(.missing))
    }

    @Test("fromOptional closure is not called when optional has value")
    func fromOptionalClosureNotCalledForValue() {
        var closureCalled = false
        let optional: Int? = 42

        _ = Result<Int, TestError>.fromOptional(optional) {
            closureCalled = true
            return .missing
        }

        #expect(closureCalled == false)
    }

    @Test("fromOptional closure is called when optional is nil")
    func fromOptionalClosureCalledForNil() {
        var closureCalled = false
        let optional: Int? = nil

        _ = Result<Int, TestError>.fromOptional(optional) {
            closureCalled = true
            return .missing
        }

        #expect(closureCalled == true)
    }

    @Test("fromOptional closure can construct dynamic error")
    func fromOptionalClosureDynamicError() {
        let fieldName = "email"
        let optional: String? = nil

        let result = Result<String, TestError>.fromOptional(optional) {
            .invalid(fieldName)
        }

        #expect(result == .failure(.invalid("email")))
    }

    @Test("fromOptional closure captures external state")
    func fromOptionalClosureCapturesState() {
        var errorCount = 0
        let optional: Int? = nil

        let result = Result<Int, TestError>.fromOptional(optional) {
            errorCount += 1
            return .missing
        }

        #expect(result == .failure(.missing))
        #expect(errorCount == 1)
    }

    @Test("fromOptional with closure works with string type")
    func fromOptionalClosureWithString() {
        let optional: String? = "hello"

        let result = Result<String, TestError>.fromOptional(optional) {
            .notFound
        }

        #expect(result == .success("hello"))
    }

    // MARK: - fromOptional curried (returns function) with error value

    @Test("fromOptional curried returns function that converts value to success")
    func fromOptionalCurriedSuccessWithValue() {
        let toResult = Result<Int, TestError>.fromOptional(error: .missing)

        let result = toResult(42)

        #expect(result == .success(42))
    }

    @Test("fromOptional curried returns function that converts nil to failure")
    func fromOptionalCurriedFailureWhenNil() {
        let toResult = Result<Int, TestError>.fromOptional(error: .missing)

        let result = toResult(nil)

        #expect(result == .failure(.missing))
    }

    @Test("fromOptional curried function can be reused")
    func fromOptionalCurriedReusable() {
        let toResult = Result<String, TestError>.fromOptional(error: .notFound)

        let result1 = toResult("hello")
        let result2 = toResult(nil)
        let result3 = toResult("world")

        #expect(result1 == .success("hello"))
        #expect(result2 == .failure(.notFound))
        #expect(result3 == .success("world"))
    }

    @Test("fromOptional curried works with pipe operator")
    func fromOptionalCurriedWithPipe() {
        let optional: Int? = 42

        let result = optional |> Result<Int, TestError>.fromOptional(error: .missing)

        #expect(result == .success(42))
    }

    // MARK: - fromOptional curried (returns function) with error closure

    @Test("fromOptional curried with closure returns function that converts value to success")
    func fromOptionalCurriedClosureSuccessWithValue() {
        let toResult = Result<Int, TestError>.fromOptional { .missing }

        let result = toResult(42)

        #expect(result == .success(42))
    }

    @Test("fromOptional curried with closure returns function that converts nil to failure")
    func fromOptionalCurriedClosureFailureWhenNil() {
        let toResult = Result<Int, TestError>.fromOptional { .missing }

        let result = toResult(nil)

        #expect(result == .failure(.missing))
    }

    @Test("fromOptional curried closure is not called when optional has value")
    func fromOptionalCurriedClosureNotCalledForValue() {
        var closureCalled = false
        let toResult = Result<Int, TestError>.fromOptional {
            closureCalled = true
            return .missing
        }

        _ = toResult(42)

        #expect(closureCalled == false)
    }

    @Test("fromOptional curried closure is called when optional is nil")
    func fromOptionalCurriedClosureCalledForNil() {
        var closureCalled = false
        let toResult = Result<Int, TestError>.fromOptional {
            closureCalled = true
            return .missing
        }

        _ = toResult(nil)

        #expect(closureCalled == true)
    }

    @Test("fromOptional curried with closure can construct dynamic error")
    func fromOptionalCurriedClosureDynamicError() {
        var callCount = 0
        let toResult = Result<String, TestError>.fromOptional {
            callCount += 1
            return .invalid("attempt-\(callCount)")
        }

        let result1 = toResult(nil)
        let result2 = toResult(nil)

        #expect(result1 == .failure(.invalid("attempt-1")))
        #expect(result2 == .failure(.invalid("attempt-2")))
    }

    @Test("fromOptional curried with closure works with pipe operator")
    func fromOptionalCurriedClosureWithPipe() {
        let optional: Int? = nil

        let result = optional |> Result<Int, TestError>.fromOptional { .notFound }

        #expect(result == .failure(.notFound))
    }
}
