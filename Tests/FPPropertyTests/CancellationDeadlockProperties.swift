// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import FP
    import HegelTesting
    import Synchronization
    import Testing

    /// Resumes a continuation at most once.
    final class Once<T: Sendable>: Sendable {
        let continuation: Mutex<CheckedContinuation<T?, Never>?>
        init(_ continuation: CheckedContinuation<T?, Never>) {
            self.continuation = Mutex(continuation)
        }
        func resume(_ value: T?) -> Bool {
            guard let continuation = continuation.withLock({ $0.take() }) else { return false }
            continuation.resume(returning: value)
            return true
        }
    }

    /// Waits for `task` for at most `limit`; `nil` means it was still running.
    func value<T: Sendable>(of task: Task<T, Never>, within limit: Duration) async -> T? {
        await withCheckedContinuation { continuation in
            let once = Once(continuation)
            Task { _ = once.resume(await task.value) }
            Task {
                try? await Task.sleep(for: limit)
                _ = once.resume(nil)
            }
        }
    }

    @Suite("Cancellation deadlock", .hegel)
    struct CancellationDeadlockProperties {
        /// Cancelling the task that reads a concurrent map, at any moment, ends
        /// the read: it never deadlocks with a worker that is finishing.
        @Test(.hegel(testCases: 2_000))
        func cancellingTheReaderEndsTheRead() async throws {
            try await property { tc in
                let jobs = try tc.draw(Draw.jobs(min: 1), named: "jobs")
                let concurrency = try tc.draw(Draw.parallel, named: "concurrency")
                let ordered = try tc.draw(.bool(), named: "ordered")
                let yields = try tc.draw(
                    .oneOf(.int(in: 0...20), .int(in: 0...1_000)),
                    named: "yieldsBeforeCancel"
                )
                let source = CountingSource(elements: jobs)
                let reader = Task {
                    var count = 0
                    if ordered {
                        for await _ in source.mapAsyncOrdered(
                            concurrency: concurrency,
                            { job in
                                await pause(job)
                                return job.value
                            }
                        ) { count += 1 }
                    } else {
                        for await _ in source.mapAsyncUnordered(
                            concurrency: concurrency,
                            { job in
                                await pause(job)
                                return job.value
                            }
                        ) { count += 1 }
                    }
                    return count
                }
                for _ in 0..<yields { await Task.yield() }
                reader.cancel()
                let read = await value(of: reader, within: .seconds(5))
                #expect(read != nil, "the reader was cancelled and never finished")
            }
        }
    }

#endif
