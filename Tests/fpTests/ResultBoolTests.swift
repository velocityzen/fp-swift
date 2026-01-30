import Testing

@testable import FP

@Suite("Result+Bool Tests")
struct ResultBoolTests {
    enum TestError: Error, Equatable {
        case missing
        case notFound
    }

    @Test("toBool returns true for success")
    func toBoolSuccessReturnsTrue() {
        let result: Result<Int, TestError> = .success(42)

        #expect(result.toBool == true)
    }

    @Test("toBool returns false for failure")
    func toBoolFailureReturnsFalse() {
        let result: Result<Int, TestError> = .failure(.missing)

        #expect(result.toBool == false)
    }

    @Test("toBool works with Void success type")
    func toBoolWithVoidSuccess() {
        let result: Result<Void, TestError> = .success(())

        #expect(result.toBool == true)
    }

    @Test("toBool works with different error types")
    func toBoolWithDifferentErrors() {
        let result1: Result<Int, TestError> = .failure(.missing)
        let result2: Result<Int, TestError> = .failure(.notFound)

        #expect(result1.toBool == false)
        #expect(result2.toBool == false)
    }

}
