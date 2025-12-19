import Testing

@testable import FP

@Suite("Result+Task Tests")
struct ResultTaskTests {
    enum TestError: Error, Equatable {
        case invalid
        case notFound
    }

    // MARK: - fromTask with throwing Task

    @Test("fromTask captures successful value from throwing Task")
    func fromTaskThrowingSuccess() async {
        let task = Task<Int, Error> {
            await Task.yield()
            return 42
        }

        let result = await Result.fromTask(task)

        switch result {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("fromTask captures error from throwing Task")
    func fromTaskThrowingError() async {
        let task = Task<Int, Error> {
            await Task.yield()
            throw TestError.invalid
        }

        let result = await Result.fromTask(task)

        switch result {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
    }

    @Test("fromTask with throwing Task works with complex types")
    func fromTaskThrowingComplexType() async {
        struct User: Equatable, Sendable {
            let id: Int
            let name: String
        }

        let task = Task<User, Error> {
            await Task.yield()
            return User(id: 1, name: "Alice")
        }

        let result = await Result.fromTask(task)

        switch result {
            case .success(let user):
                #expect(user == User(id: 1, name: "Alice"))
            case .failure:
                Issue.record("Expected success")
        }
    }

    // MARK: - fromTask with non-throwing Task

    @Test("fromTask captures value from non-throwing Task")
    func fromTaskNonThrowingSuccess() async {
        let task = Task<Int, Never> {
            await Task.yield()
            return 42
        }

        let result = await Result.fromTask(task)

        switch result {
            case .success(let value):
                #expect(value == 42)
        }
    }

    @Test("fromTask with non-throwing Task works with complex types")
    func fromTaskNonThrowingComplexType() async {
        struct Data: Equatable, Sendable {
            let value: String
        }

        let task = Task<Data, Never> {
            await Task.yield()
            return Data(value: "test")
        }

        let result = await Result.fromTask(task)

        switch result {
            case .success(let data):
                #expect(data == Data(value: "test"))
        }
    }

    // MARK: - fromTask with Task returning Result

    @Test("fromTask unwraps success Result from Task")
    func fromTaskResultSuccess() async {
        let task = Task<Result<Int, Error>, Never> {
            await Task.yield()
            return .success(42)
        }

        let result: Result<Int, Error> = await Result<Int, Error>.fromTask(task)

        switch result {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("fromTask unwraps failure Result from Task")
    func fromTaskResultFailure() async {
        let task = Task<Result<Int, Error>, Never> {
            await Task.yield()
            return .failure(TestError.notFound)
        }

        let result: Result<Int, Error> = await Result<Int, Error>.fromTask(task)

        switch result {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .notFound)
        }
    }

    @Test("fromTask with Result Task works with complex types")
    func fromTaskResultComplexType() async {
        struct Response: Equatable, Sendable {
            let status: Int
            let body: String
        }

        let task = Task<Result<Response, Error>, Never> {
            await Task.yield()
            return .success(Response(status: 200, body: "OK"))
        }

        let result: Result<Response, Error> = await Result<Response, Error>.fromTask(task)

        switch result {
            case .success(let response):
                #expect(response == Response(status: 200, body: "OK"))
            case .failure:
                Issue.record("Expected success")
        }
    }

    // MARK: - fromTask with closure syntax

    @Test("fromTask closure syntax with throwing Task success")
    func fromTaskClosureThrowingSuccess() async {
        let result: Result<Int, Error> = await Result.fromTask {
            Task {
                await Task.yield()
                return 42
            }
        }

        switch result {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("fromTask closure syntax with throwing Task error")
    func fromTaskClosureThrowingError() async {
        let result: Result<Int, Error> = await Result.fromTask {
            Task {
                await Task.yield()
                throw TestError.invalid
            }
        }

        switch result {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
    }

    @Test("fromTask closure syntax with non-throwing Task")
    func fromTaskClosureNonThrowing() async {
        let result: Result<Int, Never> = await Result.fromTask {
            Task {
                await Task.yield()
                return 42
            }
        }

        switch result {
            case .success(let value):
                #expect(value == 42)
        }
    }

    @Test("fromTask closure syntax with Result Task")
    func fromTaskClosureResult() async {
        let result: Result<Int, Error> = await Result<Int, Error>.fromTask {
            Task {
                await Task.yield()
                return .success(42)
            }
        }

        switch result {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }
}
