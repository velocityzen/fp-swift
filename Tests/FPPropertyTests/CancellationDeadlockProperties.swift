// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import FP
    import HegelTesting
    import Testing

    /// Waits for `task`, and cancels it if the waiting task is cancelled. From
    /// that cancel, `task` has `limit` to finish: `nil` means it was still
    /// running.
    func value<T: Sendable>(of task: Task<T, Never>, cancelledWithin limit: Duration) async -> T? {
        let (results, delivery) = AsyncStream.makeStream(of: T?.self)
        Task { delivery.yield(await task.value) }
        return await withTaskCancellationHandler {
            // In a task of its own: in a cancelled task, the stream ends at
            // once.
            await Task {
                for await result in results {
                    return result
                }
                return nil
            }.value
        } onCancel: {
            task.cancel()
            Task {
                try? await Task.sleep(for: limit)
                delivery.yield(nil)
            }
        }
    }

    @Suite("Cancellation deadlock", .hegel)
    struct CancellationDeadlockProperties {
        /// Cancelling the task that reads a concurrent map, at any point, ends
        /// the read: it never deadlocks with a worker that is finishing.
        ///
        /// The cancel lands on a drawn checkpoint: a transform starting or
        /// ending, or the reader getting a value. A worker that ends its
        /// transform cancels the reader while the other workers may be
        /// handing over their results.
        @Test(.hegel(testCases: 2_000))
        func cancellingTheReaderEndsTheRead() async throws {
            var cases = 0
            var cancelled = 0
            try await property { tc in
                let jobs = try #draw(Draw.jobs(min: 1), from: tc)
                let concurrency = try #draw(Draw.parallel, from: tc)
                let ordered = try #draw(.bool(), from: tc)
                let source = CountingSource(elements: jobs)
                let run = try await tc.withRandomCancellation { cancellation in
                    let transform: @concurrent @Sendable (Job) async -> Int = { job in
                        cancellation.checkpoint("transform \(job) starts")
                        await pause(job)
                        cancellation.checkpoint("transform \(job) ends")
                        return job.value
                    }
                    // The reader runs in a task of its own, so that a
                    // deadlock fails the property instead of hanging it.
                    let reader = Task {
                        var count = 0
                        if ordered {
                            for await _ in source.mapAsyncOrdered(
                                concurrency: concurrency,
                                transform
                            ) {
                                count += 1
                                cancellation.checkpoint("read \(count)")
                            }
                        } else {
                            for await _ in source.mapAsyncUnordered(
                                concurrency: concurrency,
                                transform
                            ) {
                                count += 1
                                cancellation.checkpoint("read \(count)")
                            }
                        }
                        return count
                    }
                    return await value(of: reader, cancelledWithin: .seconds(5))
                }
                #expect(run.value != nil, "the reader was cancelled and never finished")

                cases += 1
                if run.cancelledAt != nil {
                    cancelled += 1
                    try tc.event("cancelled during the read")
                }
            }
            expectReached(cancelled, in: cases, "no case cancelled the reader")
        }
    }

#endif
