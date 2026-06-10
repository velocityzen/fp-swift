import Testing

@testable import FP

@Suite("Result+tap Tests")
struct ResultTapTests {
    enum TestError: Error, Equatable {
        case invalid
        case failed
    }

    // MARK: - tap (sync, non-throwing, Void return)

    @Test("tap executes action for success")
    func tapExecutesForSuccess() {
        var sideEffect = 0
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tap { value in
            sideEffect = value
        }

        #expect(tapped == .success(42))
        #expect(sideEffect == 42)
    }

    @Test("tap does not execute action for failure")
    func tapDoesNotExecuteForFailure() {
        var sideEffect = 0
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tap { value in
            sideEffect = value
        }

        #expect(tapped == .failure(.invalid))
        #expect(sideEffect == 0)
    }

    // MARK: - tap (sync, non-throwing, T return)

    @Test("tap with return value executes and ignores result")
    func tapWithReturnValueIgnoresResult() {
        var sideEffect = ""
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tap { value -> String in
            sideEffect = "called"
            return "ignored-\(value)"
        }

        #expect(tapped == .success(42))
        #expect(sideEffect == "called")
    }

    // MARK: - tap (sync, throwing, Void return)

    @Test("tap throwing succeeds when action does not throw")
    func tapThrowingSucceeds() {
        var sideEffect = 0
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tap { value throws in
            sideEffect = value
        }

        switch tapped {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
        #expect(sideEffect == 42)
    }

    @Test("tap throwing captures error when action throws")
    func tapThrowingCapturesError() {
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tap { _ throws in
            throw TestError.failed
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .failed)
        }
    }

    @Test("tap throwing preserves original failure")
    func tapThrowingPreservesFailure() {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tap { _ throws in
            throw TestError.failed
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
    }

    // MARK: - tap (sync, throwing, T return)

    @Test("tap throwing with return value succeeds")
    func tapThrowingWithReturnSucceeds() {
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tap { value throws -> String in
            return "processed-\(value)"
        }

        switch tapped {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("tap throwing with return value captures error")
    func tapThrowingWithReturnCapturesError() {
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tap { _ throws -> String in
            throw TestError.failed
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .failed)
        }
    }

    // MARK: - tap (sync, Result<Void, E> return)

    @Test("tap with Result Void succeeds when action returns success")
    func tapResultVoidSucceeds() {
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tap { _ -> Result<Void, TestError> in
            return .success(())
        }

        #expect(tapped == .success(42))
    }

    @Test("tap with Result Void fails when action returns failure")
    func tapResultVoidFails() {
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tap { _ -> Result<Void, TestError> in
            return .failure(.failed)
        }

        #expect(tapped == .failure(.failed))
    }

    // MARK: - tap (sync, Result<T, E> return)

    @Test("tap with Result T succeeds when action returns success")
    func tapResultTSucceeds() {
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tap { value -> Result<String, TestError> in
            return .success("ignored-\(value)")
        }

        #expect(tapped == .success(42))
    }

    @Test("tap with Result T fails when action returns failure")
    func tapResultTFails() {
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tap { _ -> Result<String, TestError> in
            return .failure(.failed)
        }

        #expect(tapped == .failure(.failed))
    }

    // MARK: - tapAsync (async, non-throwing, Void return)

    @Test("tapAsync executes async action for success")
    func tapAsyncExecutesForSuccess() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapAsync { _ in
            await counter.increment()
        }

        let count = await counter.count
        #expect(tapped == .success(42))
        #expect(count == 1)
    }

    @Test("tapAsync does not execute for failure")
    func tapAsyncDoesNotExecuteForFailure() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapAsync { _ in
            await counter.increment()
        }

        let count = await counter.count
        #expect(tapped == .failure(.invalid))
        #expect(count == 0)
    }

    // MARK: - tapAsync (async, non-throwing, T return)

    @Test("tapAsync with return value ignores result")
    func tapAsyncWithReturnIgnoresResult() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapAsync { _ -> Int in
            return await counter.increment()
        }

        let count = await counter.count
        #expect(tapped == .success(42))
        #expect(count == 1)
    }

    // MARK: - tapAsync (async, throwing, Void return)

    @Test("tapAsync throwing succeeds when action does not throw")
    func tapAsyncThrowingSucceeds() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapAsync { _ async throws in
            await counter.increment()
        }

        let count = await counter.count
        switch tapped {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
        #expect(count == 1)
    }

    @Test("tapAsync throwing captures error")
    func tapAsyncThrowingCapturesError() async {
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapAsync { _ async throws in
            await Task.yield()
            throw TestError.failed
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .failed)
        }
    }

    @Test("tapAsync throwing preserves original failure")
    func tapAsyncThrowingPreservesFailure() async {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapAsync { _ async throws in
            await Task.yield()
            throw TestError.failed
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
    }

    // MARK: - tapAsync (async, throwing, T return)

    @Test("tapAsync throwing with return succeeds")
    func tapAsyncThrowingWithReturnSucceeds() async {
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapAsync { value async throws -> String in
            await Task.yield()
            return "processed-\(value)"
        }

        switch tapped {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }

    // MARK: - tapAsync (async, Result<Void, E> return)

    @Test("tapAsync with Result Void succeeds")
    func tapAsyncResultVoidSucceeds() async {
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapAsync { _ -> Result<Void, TestError> in
            await Task.yield()
            return .success(())
        }

        #expect(tapped == .success(42))
    }

    @Test("tapAsync with Result Void fails")
    func tapAsyncResultVoidFails() async {
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapAsync { _ -> Result<Void, TestError> in
            await Task.yield()
            return .failure(.failed)
        }

        #expect(tapped == .failure(.failed))
    }

    // MARK: - tapAsync (async, Result<T, E> return)

    @Test("tapAsync with Result T succeeds")
    func tapAsyncResultTSucceeds() async {
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapAsync { value -> Result<String, TestError> in
            await Task.yield()
            return .success("ignored-\(value)")
        }

        #expect(tapped == .success(42))
    }

    @Test("tapAsync with Result T fails")
    func tapAsyncResultTFails() async {
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapAsync { _ -> Result<String, TestError> in
            await Task.yield()
            return .failure(.failed)
        }

        #expect(tapped == .failure(.failed))
    }

    // MARK: - tapError (sync, non-throwing, Void return)

    @Test("tapError executes action for failure")
    func tapErrorExecutesForFailure() {
        var capturedError: TestError?
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tapError { error in
            capturedError = error
        }

        #expect(tapped == .failure(.invalid))
        #expect(capturedError == .invalid)
    }

    @Test("tapError does not execute for success")
    func tapErrorDoesNotExecuteForSuccess() {
        var called = false
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tapError { _ in
            called = true
        }

        #expect(tapped == .success(42))
        #expect(called == false)
    }

    // MARK: - tapError (sync, non-throwing, T return)

    @Test("tapError with return value ignores result")
    func tapErrorWithReturnIgnoresResult() {
        var called = false
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tapError { error -> String in
            called = true
            return "error: \(error)"
        }

        #expect(tapped == .failure(.invalid))
        #expect(called == true)
    }

    // MARK: - tapError (sync, throwing)

    @Test("tapError throwing preserves failure when action succeeds")
    func tapErrorThrowingPreservesFailure() {
        var called = false
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tapError { _ throws in
            called = true
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
        #expect(called == true)
    }

    @Test("tapError throwing preserves success")
    func tapErrorThrowingPreservesSuccess() {
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tapError { _ throws in
            throw TestError.failed
        }

        switch tapped {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("tapError throwing replaces failure with thrown error")
    func tapErrorThrowingReplacesFailureWithThrownError() {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tapError { _ throws in
            throw TestError.failed
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .failed)
        }
    }

    @Test("tapError throwing with return value replaces failure with thrown error")
    func tapErrorThrowingWithReturnReplacesFailure() {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tapError { _ throws -> String in
            throw TestError.failed
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .failed)
        }
    }

    // MARK: - tapError (sync, Result return)

    @Test("tapError Result-returning preserves original failure when action succeeds")
    func tapErrorResultActionSucceedsPreservesOriginal() {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tapError { _ -> Result<String, TestError> in
            .success("logged")
        }

        #expect(tapped == .failure(.invalid))
    }

    @Test("tapError Result-returning replaces failure when action fails")
    func tapErrorResultActionFailsReplacesOriginal() {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tapError { _ -> Result<String, TestError> in
            .failure(.failed)
        }

        #expect(tapped == .failure(.failed))
    }

    @Test("tapError Result-returning preserves success")
    func tapErrorResultPreservesSuccess() {
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tapError { _ -> Result<String, TestError> in
            .failure(.failed)
        }

        #expect(tapped == .success(42))
    }

    // MARK: - tapErrorAsync (async, non-throwing)

    @Test("tapErrorAsync executes async action for failure")
    func tapErrorAsyncExecutesForFailure() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapErrorAsync { _ in
            await counter.increment()
        }

        let count = await counter.count
        #expect(tapped == .failure(.invalid))
        #expect(count == 1)
    }

    @Test("tapErrorAsync does not execute for success")
    func tapErrorAsyncDoesNotExecuteForSuccess() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapErrorAsync { _ in
            await counter.increment()
        }

        let count = await counter.count
        #expect(tapped == .success(42))
        #expect(count == 0)
    }

    // MARK: - tapErrorAsync (async, non-throwing, T return)

    @Test("tapErrorAsync with return value ignores result")
    func tapErrorAsyncWithReturnIgnoresResult() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapErrorAsync { _ -> Int in
            return await counter.increment()
        }

        let count = await counter.count
        #expect(tapped == .failure(.invalid))
        #expect(count == 1)
    }

    // MARK: - tapErrorAsync (async, throwing)

    @Test("tapErrorAsync throwing preserves failure")
    func tapErrorAsyncThrowingPreservesFailure() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapErrorAsync { _ async throws in
            await counter.increment()
        }

        let count = await counter.count
        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
        #expect(count == 1)
    }

    @Test("tapErrorAsync throwing preserves success")
    func tapErrorAsyncThrowingPreservesSuccess() async {
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapErrorAsync { _ async throws in
            await Task.yield()
            throw TestError.failed
        }

        switch tapped {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("tapErrorAsync throwing replaces failure with thrown error")
    func tapErrorAsyncThrowingReplacesFailureWithThrownError() async {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapErrorAsync { _ async throws in
            await Task.yield()
            throw TestError.failed
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .failed)
        }
    }

    @Test("tapErrorAsync throwing with return value replaces failure with thrown error")
    func tapErrorAsyncThrowingWithReturnReplacesFailure() async {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapErrorAsync { _ async throws -> String in
            await Task.yield()
            throw TestError.failed
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .failed)
        }
    }

    // MARK: - tapErrorAsync (async, Result return)

    @Test("tapErrorAsync Result-returning preserves original failure when action succeeds")
    func tapErrorAsyncResultActionSucceedsPreservesOriginal() async {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapErrorAsync { _ -> Result<String, TestError> in
            await Task.yield()
            return .success("logged")
        }

        #expect(tapped == .failure(.invalid))
    }

    @Test("tapErrorAsync Result-returning replaces failure when action fails")
    func tapErrorAsyncResultActionFailsReplacesOriginal() async {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapErrorAsync { _ -> Result<String, TestError> in
            await Task.yield()
            return .failure(.failed)
        }

        #expect(tapped == .failure(.failed))
    }

    // MARK: - Chaining

    @Test("tap methods can be chained")
    func tapChaining() {
        var log: [String] = []
        let result: Result<Int, TestError> = .success(42)

        let tapped =
            result
            .tap { log.append("first: \($0)") }
            .tap { log.append("second: \($0)") }

        #expect(tapped == .success(42))
        #expect(log == ["first: 42", "second: 42"])
    }

    @Test("tapAsync methods can be chained")
    func tapAsyncChaining() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .success(42)

        let tapped =
            await result
            .tapAsync { _ in await counter.increment() }

        let tapped2 =
            await tapped
            .tapAsync { _ in await counter.increment() }

        let count = await counter.count
        #expect(tapped2 == .success(42))
        #expect(count == 2)
    }

    // MARK: - finally

    @Test("finally runs action on success and returns self")
    func finallyRunsOnSuccess() {
        var ran = false
        let result: Result<Int, TestError> = .success(42)

        let returned = result.finally { ran = true }

        #expect(ran)
        #expect(returned == .success(42))
    }

    @Test("finally runs action on failure and returns self")
    func finallyRunsOnFailure() {
        var ran = false
        let result: Result<Int, TestError> = .failure(.invalid)

        let returned = result.finally { ran = true }

        #expect(ran)
        #expect(returned == .failure(.invalid))
    }

    @Test("finally composes with tap and tapError")
    func finallyComposesWithTaps() {
        var events: [String] = []
        let result: Result<Int, TestError> = .success(42)

        let _ =
            result
            .tap { _ in events.append("tap") }
            .tapError { _ in events.append("tapError") }
            .finally { events.append("finally") }

        #expect(events == ["tap", "finally"])
    }

    @Test("finally still runs on failure when tap is skipped")
    func finallyRunsAfterSkippedTap() {
        var events: [String] = []
        let result: Result<Int, TestError> = .failure(.failed)

        let _ =
            result
            .tap { _ in events.append("tap") }
            .tapError { _ in events.append("tapError") }
            .finally { events.append("finally") }

        #expect(events == ["tapError", "finally"])
    }

    // MARK: - finallyAsync

    @Test("finallyAsync runs action on success and returns self")
    func finallyAsyncRunsOnSuccess() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .success(42)

        let returned = await result.finallyAsync { await counter.increment() }

        let count = await counter.count
        #expect(count == 1)
        #expect(returned == .success(42))
    }

    @Test("finallyAsync runs action on failure and returns self")
    func finallyAsyncRunsOnFailure() async {
        let counter = AsyncCounter()
        let result: Result<Int, TestError> = .failure(.invalid)

        let returned = await result.finallyAsync { await counter.increment() }

        let count = await counter.count
        #expect(count == 1)
        #expect(returned == .failure(.invalid))
    }

    // MARK: - Remaining branch coverage

    @Test("tap throwing with return value passes failure through")
    func tapThrowingWithReturnPassesFailureThrough() {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tap { value throws -> String in "ignored-\(value)" }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
    }

    @Test("tap Result-returning passes failure through")
    func tapResultVoidPassesFailureThrough() {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tap { _ -> Result<Void, TestError> in .success(()) }

        #expect(tapped == .failure(.invalid))
    }

    @Test("tap Result-returning with value passes failure through")
    func tapResultValuePassesFailureThrough() {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tap { _ -> Result<String, TestError> in .success("x") }

        #expect(tapped == .failure(.invalid))
    }

    @Test("tapAsync throwing void action succeeds when action does not throw")
    func tapAsyncThrowingVoidSucceeds() async {
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapAsync { _ async throws in
            await Task.yield()
        }

        switch tapped {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("tapAsync throwing with return value captures thrown error")
    func tapAsyncThrowingWithReturnCapturesError() async {
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapAsync { _ async throws -> String in
            await Task.yield()
            throw TestError.failed
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .failed)
        }
    }

    @Test("tapAsync throwing with return value passes failure through")
    func tapAsyncThrowingWithReturnPassesFailureThrough() async {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapAsync { _ async throws -> String in "x" }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
    }

    @Test("tapAsync Result-returning passes failure through")
    func tapAsyncResultVoidPassesFailureThrough() async {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapAsync { _ -> Result<Void, TestError> in .success(()) }

        #expect(tapped == .failure(.invalid))
    }

    @Test("tapAsync Result-returning with value passes failure through")
    func tapAsyncResultValuePassesFailureThrough() async {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapAsync { _ -> Result<String, TestError> in .success("x") }

        #expect(tapped == .failure(.invalid))
    }

    @Test("tapError throwing with return value preserves success")
    func tapErrorThrowingWithReturnPreservesSuccess() {
        let result: Result<Int, TestError> = .success(42)

        let tapped = result.tapError { _ throws -> String in "logged" }

        switch tapped {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("tapError throwing with return value preserves failure when action succeeds")
    func tapErrorThrowingWithReturnPreservesFailure() {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = result.tapError { _ throws -> String in "logged" }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
    }

    @Test("tapErrorAsync throwing void action preserves failure when action does not throw")
    func tapErrorAsyncThrowingVoidPreservesFailure() async {
        let result: Result<Int, TestError> = .failure(.invalid)

        let tapped = await result.tapErrorAsync { _ async throws in
            await Task.yield()
        }

        switch tapped {
            case .success:
                Issue.record("Expected failure")
            case .failure(let error):
                #expect(error as? TestError == .invalid)
        }
    }

    @Test("tapErrorAsync throwing with return value preserves success")
    func tapErrorAsyncThrowingWithReturnPreservesSuccess() async {
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapErrorAsync { _ async throws -> String in "logged" }

        switch tapped {
            case .success(let value):
                #expect(value == 42)
            case .failure:
                Issue.record("Expected success")
        }
    }

    @Test("tapErrorAsync Result-returning preserves success")
    func tapErrorAsyncResultPreservesSuccess() async {
        let result: Result<Int, TestError> = .success(42)

        let tapped = await result.tapErrorAsync { _ -> Result<String, TestError> in
            .failure(.failed)
        }

        #expect(tapped == .success(42))
    }

}
