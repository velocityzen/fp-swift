import Testing

@testable import FP

@Suite("Result+Timeout Tests")
struct ResultTimeoutTests {
    enum TestError: Error, Equatable {
        case failed
        case timeout
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
    @Test("returns the success when the operation finishes within the timeout")
    func successWithinTimeout() async {
        let result: Result<Int, TestError> = await withTimeout(.seconds(5), failingWith: .timeout) {
            .success(42)
        }

        #expect(result == .success(42))
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
    @Test("returns the operation's own failure when it fails before the timeout")
    func failureWithinTimeoutIsNotSwallowed() async {
        let result: Result<Int, TestError> = await withTimeout(.seconds(5), failingWith: .timeout) {
            .failure(.failed)
        }

        // The fast failure wins. It must not be replaced by .timeout.
        #expect(result == .failure(.failed))
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
    @Test("returns the timeout error when the operation outlasts the timeout", .hangGuard)
    func timesOutWhenOperationIsTooSlow() async {
        let result: Result<Int, TestError> = await withTimeout(
            .milliseconds(50),
            failingWith: .timeout
        ) {
            await waitForCancellation()
            return .success(1)
        }

        #expect(result == .failure(.timeout))
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
    @Test("cancels the operation when the timeout fires", .hangGuard)
    func cancelsOperationOnTimeout() async {
        let cancelled = AsyncCounter()

        let result: Result<Int, TestError> = await withTimeout(
            .milliseconds(50),
            failingWith: .timeout
        ) {
            await waitForCancellation()
            await cancelled.increment()
            return .success(1)
        }

        let cancelledCount = await cancelled.count
        #expect(result == .failure(.timeout))
        #expect(cancelledCount == 1)
    }
}
