import Testing

@testable import FP

@Suite("Result+Bool Tests")
struct ResultBoolTests {
    enum TestError: Error, Equatable {
        case missing
        case notFound
    }

    @Test("isSuccess returns true for success")
    func isSuccessReturnsTrueForSuccess() {
        let result: Result<Int, TestError> = .success(42)

        #expect(result.isSuccess == true)
    }

    @Test("isSuccess returns false for failure")
    func isSuccessReturnsFalseForFailure() {
        let result: Result<Int, TestError> = .failure(.missing)

        #expect(result.isSuccess == false)
    }

    @Test("isFailure returns true for failure")
    func isFailureReturnsTrueForFailure() {
        let result: Result<Int, TestError> = .failure(.missing)

        #expect(result.isFailure == true)
    }

    @Test("isFailure returns false for success")
    func isFailureReturnsFalseForSuccess() {
        let result: Result<Int, TestError> = .success(42)

        #expect(result.isFailure == false)
    }

    @Test("isSuccess works with Void success type")
    func isSuccessWithVoidSuccess() {
        let result: Result<Void, TestError> = .success(())

        #expect(result.isSuccess == true)
    }

    @Test("isSuccess works with different error types")
    func isSuccessWithDifferentErrors() {
        let result1: Result<Int, TestError> = .failure(.missing)
        let result2: Result<Int, TestError> = .failure(.notFound)

        #expect(result1.isSuccess == false)
        #expect(result2.isSuccess == false)
    }
}
