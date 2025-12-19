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
}
