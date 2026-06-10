import Testing

@testable import FP

@Suite("Result+Failure Tests")
struct ResultFailureTests {
    enum TestError: Error, Equatable {
        case primary
        case fallback
    }

    enum OtherError: Error, Equatable {
        case wrapped
        case other
    }

    // MARK: - alt

    @Test("alt returns self when self is success, regardless of alternative")
    func altSuccessKeepsSelf() {
        let success: Result<Int, TestError> = .success(1)

        let altSuccess = success.alt { .success(2) }
        let altFailure = success.alt { .failure(.fallback) }

        #expect(altSuccess == .success(1))
        #expect(altFailure == .success(1))
    }

    @Test("alt returns alternative success when self is failure")
    func altFailureReturnsAlternativeSuccess() {
        let failure: Result<Int, TestError> = .failure(.primary)

        let result = failure.alt { .success(2) }

        #expect(result == .success(2))
    }

    @Test("alt returns alternative failure when both sides fail")
    func altBothFailuresReturnsAlternative() {
        let failure: Result<Int, TestError> = .failure(.primary)

        let result = failure.alt { .failure(.fallback) }

        #expect(result == .failure(.fallback))
    }

    @Test("alt does not evaluate alternative when self is success")
    func altDoesNotEvaluateAlternativeOnSuccess() {
        let success: Result<Int, TestError> = .success(1)
        nonisolated(unsafe) var evaluated = false

        _ = success.alt {
            evaluated = true
            return .success(2)
        }

        #expect(evaluated == false)
    }

    // MARK: - altAsync

    @Test("altAsync returns self when self is success")
    func altAsyncSuccessKeepsSelf() async {
        let success: Result<Int, TestError> = .success(1)

        let result = await success.altAsync {
            await Task.yield()
            return .success(2)
        }

        #expect(result == .success(1))
    }

    @Test("altAsync returns alternative success when self is failure")
    func altAsyncFailureReturnsAlternativeSuccess() async {
        let failure: Result<Int, TestError> = .failure(.primary)

        let result = await failure.altAsync {
            await Task.yield()
            return .success(2)
        }

        #expect(result == .success(2))
    }

    @Test("altAsync returns alternative failure when both sides fail")
    func altAsyncBothFailuresReturnsAlternative() async {
        let failure: Result<Int, TestError> = .failure(.primary)

        let result = await failure.altAsync {
            await Task.yield()
            return .failure(.fallback)
        }

        #expect(result == .failure(.fallback))
    }

    @Test("altAsync does not evaluate alternative when self is success")
    func altAsyncDoesNotEvaluateAlternativeOnSuccess() async {
        let success: Result<Int, TestError> = .success(1)
        let counter = AsyncCounter()

        _ = await success.altAsync {
            await counter.increment()
            return .success(2)
        }

        let count = await counter.count
        #expect(count == 0)
    }

    // MARK: - orElse

    @Test("orElse returns self when self is success, regardless of recovery")
    func orElseSuccessKeepsSelf() {
        let success: Result<Int, TestError> = .success(1)

        let recovered: Result<Int, OtherError> = success.orElse { _ in .success(2) }
        let stillFailing: Result<Int, OtherError> = success.orElse { _ in .failure(.wrapped) }

        #expect(recovered == .success(1))
        #expect(stillFailing == .success(1))
    }

    @Test("orElse returns recovery success when self is failure")
    func orElseFailureReturnsRecoverySuccess() {
        let failure: Result<Int, TestError> = .failure(.primary)

        let result: Result<Int, OtherError> = failure.orElse { _ in .success(2) }

        #expect(result == .success(2))
    }

    @Test("orElse receives the failure value and can branch on it")
    func orElseReceivesFailureValue() {
        let failure: Result<Int, TestError> = .failure(.primary)

        let result: Result<Int, OtherError> = failure.orElse { error in
            error == .primary ? .failure(.wrapped) : .failure(.other)
        }

        #expect(result == .failure(.wrapped))
    }

    @Test("orElse can change the Failure type")
    func orElseChangesFailureType() {
        let failure: Result<Int, TestError> = .failure(.fallback)

        let result: Result<Int, OtherError> = failure.orElse { _ in .failure(.other) }

        #expect(result == .failure(.other))
    }

    @Test("orElse does not evaluate recovery when self is success")
    func orElseDoesNotEvaluateOnSuccess() {
        let success: Result<Int, TestError> = .success(1)
        nonisolated(unsafe) var evaluated = false

        let _: Result<Int, OtherError> = success.orElse { _ in
            evaluated = true
            return .failure(.wrapped)
        }

        #expect(evaluated == false)
    }

    // MARK: - orElseAsync

    @Test("orElseAsync returns self when self is success")
    func orElseAsyncSuccessKeepsSelf() async {
        let success: Result<Int, TestError> = .success(1)

        let result: Result<Int, OtherError> = await success.orElseAsync { _ in
            await Task.yield()
            return .success(2)
        }

        #expect(result == .success(1))
    }

    @Test("orElseAsync returns recovery success when self is failure")
    func orElseAsyncFailureReturnsRecoverySuccess() async {
        let failure: Result<Int, TestError> = .failure(.primary)

        let result: Result<Int, OtherError> = await failure.orElseAsync { _ in
            await Task.yield()
            return .success(2)
        }

        #expect(result == .success(2))
    }

    @Test("orElseAsync can change the Failure type")
    func orElseAsyncChangesFailureType() async {
        let failure: Result<Int, TestError> = .failure(.primary)

        let result: Result<Int, OtherError> = await failure.orElseAsync { error in
            await Task.yield()
            return error == .primary ? .failure(.wrapped) : .failure(.other)
        }

        #expect(result == .failure(.wrapped))
    }

    @Test("orElseAsync does not evaluate recovery when self is success")
    func orElseAsyncDoesNotEvaluateOnSuccess() async {
        let success: Result<Int, TestError> = .success(1)
        let counter = AsyncCounter()

        let _: Result<Int, OtherError> = await success.orElseAsync { _ in
            await counter.increment()
            return .failure(.wrapped)
        }

        let count = await counter.count
        #expect(count == 0)
    }

    // MARK: - getOrElse (closure)

    @Test("getOrElse returns success value when self is success")
    func getOrElseSuccessReturnsValue() {
        let success: Result<Int, TestError> = .success(42)

        let value = success.getOrElse { _ in 0 }

        #expect(value == 42)
    }

    @Test("getOrElse computes fallback from failure")
    func getOrElseFailureComputesFromError() {
        let failure: Result<Int, TestError> = .failure(.primary)

        let value = failure.getOrElse { error in
            error == .primary ? -1 : -2
        }

        #expect(value == -1)
    }

    @Test("getOrElse closure is not evaluated on success")
    func getOrElseClosureNotEvaluatedOnSuccess() {
        let success: Result<Int, TestError> = .success(42)
        nonisolated(unsafe) var evaluated = false

        _ = success.getOrElse { _ in
            evaluated = true
            return 0
        }

        #expect(evaluated == false)
    }

    // MARK: - getOrElse (autoclosure)

    @Test("getOrElse autoclosure returns success value when self is success")
    func getOrElseAutoclosureSuccessReturnsValue() {
        let success: Result<Int, TestError> = .success(42)

        let value = success.getOrElse(0)

        #expect(value == 42)
    }

    @Test("getOrElse autoclosure returns default when self is failure")
    func getOrElseAutoclosureFailureReturnsDefault() {
        let failure: Result<Int, TestError> = .failure(.primary)

        let value = failure.getOrElse(99)

        #expect(value == 99)
    }

    @Test("getOrElse autoclosure is not evaluated on success")
    func getOrElseAutoclosureNotEvaluatedOnSuccess() {
        let success: Result<Int, TestError> = .success(42)
        nonisolated(unsafe) var evaluated = false

        _ = success.getOrElse(
            {
                evaluated = true
                return 0
            }())

        #expect(evaluated == false)
    }

    // MARK: - getOrElseAsync

    @Test("getOrElseAsync returns success value when self is success")
    func getOrElseAsyncSuccessReturnsValue() async {
        let success: Result<Int, TestError> = .success(42)

        let value = await success.getOrElseAsync { _ in
            await Task.yield()
            return 0
        }

        #expect(value == 42)
    }

    @Test("getOrElseAsync computes fallback from failure")
    func getOrElseAsyncFailureComputesFromError() async {
        let failure: Result<Int, TestError> = .failure(.primary)

        let value = await failure.getOrElseAsync { error in
            await Task.yield()
            return error == .primary ? -1 : -2
        }

        #expect(value == -1)
    }

    @Test("getOrElseAsync closure is not evaluated on success")
    func getOrElseAsyncClosureNotEvaluatedOnSuccess() async {
        let success: Result<Int, TestError> = .success(42)
        let counter = AsyncCounter()

        _ = await success.getOrElseAsync { _ in
            await counter.increment()
            return 0
        }

        let count = await counter.count
        #expect(count == 0)
    }

    // MARK: - getOrElseAsync (autoclosure)

    @Test("getOrElseAsync autoclosure returns success value when self is success")
    func getOrElseAsyncAutoclosureSuccessReturnsValue() async {
        let success: Result<Int, TestError> = .success(42)

        let value = await success.getOrElseAsync(0)

        #expect(value == 42)
    }

    @Test("getOrElseAsync autoclosure awaits default on failure")
    func getOrElseAsyncAutoclosureFailureAwaitsDefault() async {
        let failure: Result<Int, TestError> = .failure(.primary)

        @Sendable func fallback() async -> Int {
            await Task.yield()
            return 99
        }

        let value = await failure.getOrElseAsync(await fallback())

        #expect(value == 99)
    }

    @Test("getOrElseAsync autoclosure is not evaluated on success")
    func getOrElseAsyncAutoclosureNotEvaluatedOnSuccess() async {
        let success: Result<Int, TestError> = .success(42)
        let counter = AsyncCounter()

        @Sendable func fallback(_ counter: AsyncCounter) async -> Int {
            await counter.increment()
            return 0
        }

        _ = await success.getOrElseAsync(await fallback(counter))

        let count = await counter.count
        #expect(count == 0)
    }

    // MARK: - getOrExit
    //
    // Failure paths call `Foundation.exit`, so they are covered by exit
    // tests (`processExitsWith:`) that run the body in a child process.

    @Test("getOrExit returns the success value")
    func getOrExitReturnsSuccess() {
        let success: Result<Int, TestError> = .success(42)

        let value = success.getOrExit()

        #expect(value == 42)
    }

    @Test("getOrExit with custom prefix and exit code returns success unchanged")
    func getOrExitCustomArgsReturnsSuccess() {
        let success: Result<String, TestError> = .success("ok")

        let value = success.getOrExit(prefix: "fatal: ", exitCode: 2)

        #expect(value == "ok")
    }

    @Test("getOrExit message closure is not evaluated on success")
    func getOrExitMessageClosureNotEvaluatedOnSuccess() {
        let success: Result<Int, TestError> = .success(7)
        nonisolated(unsafe) var evaluated = false

        let value = success.getOrExit { error in
            evaluated = true
            return "should not run: \(error)\n"
        }

        #expect(value == 7)
        #expect(evaluated == false)
    }

    // Exit tests need process spawning — unavailable on iOS/tvOS.
    #if os(macOS) || os(Linux)
    @Test("getOrExit on failure writes prefix and error to stderr and exits with the given code")
    func getOrExitExitsOnFailure() async {
        let result = await #expect(
            processExitsWith: .exitCode(2),
            observing: [\.standardErrorContent]
        ) {
            let failure: Result<Int, TestError> = .failure(.primary)
            _ = failure.getOrExit(prefix: "fatal: ", exitCode: 2)
        }

        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("fatal: primary"))
    }

    @Test("getOrExit on failure defaults to exit code 1 and the Error prefix")
    func getOrExitDefaultsOnFailure() async {
        let result = await #expect(
            processExitsWith: .exitCode(1),
            observing: [\.standardErrorContent]
        ) {
            let failure: Result<Int, TestError> = .failure(.primary)
            _ = failure.getOrExit()
        }

        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("Error: primary"))
    }

    @Test("getOrExit on failure writes the custom message")
    func getOrExitCustomMessageOnFailure() async {
        let result = await #expect(
            processExitsWith: .exitCode(3),
            observing: [\.standardErrorContent]
        ) {
            let failure: Result<Int, TestError> = .failure(.primary)
            _ = failure.getOrExit(exitCode: 3) { error in
                "could not load: \(error)\n"
            }
        }

        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("could not load: primary"))
    }
    #endif

    // MARK: - orExit
    //
    // Failure paths call `Foundation.exit`, so they are covered by exit
    // tests (`processExitsWith:`) that run the body in a child process.

    @Test("orExit does nothing on success")
    func orExitDoesNothingOnSuccess() {
        let success: Result<Int, TestError> = .success(42)

        success.orExit()
    }

    @Test("orExit with custom prefix and exit code does nothing on success")
    func orExitCustomArgsDoesNothingOnSuccess() {
        let success: Result<String, TestError> = .success("ok")

        success.orExit(prefix: "fatal: ", exitCode: 2)
    }

    @Test("orExit message closure is not evaluated on success")
    func orExitMessageClosureNotEvaluatedOnSuccess() {
        let success: Result<Int, TestError> = .success(7)
        nonisolated(unsafe) var evaluated = false

        success.orExit { error in
            evaluated = true
            return "should not run: \(error)\n"
        }

        #expect(evaluated == false)
    }

    // Exit tests need process spawning — unavailable on iOS/tvOS.
    #if os(macOS) || os(Linux)
    @Test("orExit on failure writes prefix and error to stderr and exits with the given code")
    func orExitExitsOnFailure() async {
        let result = await #expect(
            processExitsWith: .exitCode(2),
            observing: [\.standardErrorContent]
        ) {
            let failure: Result<Int, TestError> = .failure(.primary)
            failure.orExit(prefix: "fatal: ", exitCode: 2)
        }

        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("fatal: primary"))
    }

    @Test("orExit on failure writes the custom message")
    func orExitCustomMessageOnFailure() async {
        let result = await #expect(
            processExitsWith: .exitCode(4),
            observing: [\.standardErrorContent]
        ) {
            let failure: Result<Int, TestError> = .failure(.primary)
            failure.orExit(exitCode: 4) { error in
                "command failed: \(error)\n"
            }
        }

        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("command failed: primary"))
    }
    #endif
}
