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

        // The fast failure wins — it must NOT be replaced by .timeout.
        #expect(result == .failure(.failed))
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
    @Test("returns the timeout error when the operation outlasts the timeout")
    func timesOutWhenOperationIsTooSlow() async {
        let result: Result<Int, TestError> = await withTimeout(
            .milliseconds(50), failingWith: .timeout
        ) {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            return .success(1)
        }

        #expect(result == .failure(.timeout))
    }

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
    @Test("cancels the operation when the timeout fires")
    func cancelsOperationOnTimeout() async {
        let cancelled = AsyncCounter()

        let result: Result<Int, TestError> = await withTimeout(
            .milliseconds(50), failingWith: .timeout
        ) {
            // sleeps far longer than the timeout; throws immediately on cancellation
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if Task.isCancelled {
                await cancelled.increment()
            }
            return .success(1)
        }

        let cancelledCount = await cancelled.count
        #expect(result == .failure(.timeout))
        #expect(cancelledCount == 1)
    }
}
