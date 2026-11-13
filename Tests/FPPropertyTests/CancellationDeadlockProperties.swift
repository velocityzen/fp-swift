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
        /// the read: it never deadlocks with a worker that is finishing. Once
        /// the read ends, cancelled or not, the source's iterator is released.
        ///
        /// The cancel lands on a drawn checkpoint: a transform starting or
        /// ending, or the reader getting a value. A worker that ends its
        /// transform cancels the reader while the other workers may be
        /// handing over their results.
        @Test(.hegel(testCases: cases(2_000)))
        func cancellingTheReaderEndsTheRead() async throws {
            var cases = 0
            var cancelled = 0
            try await property { tc in
                let mix = try #draw(Draw.outcomes([.keep, .drop]), from: tc)
                let jobs = try #draw(Draw.jobs(mix, min: 1), from: tc)
                let passEvery = try #draw(Draw.passEvery, from: tc)
                let concurrency = try #draw(Draw.concurrency, from: tc)
                let ordered = try #draw(.bool(), from: tc)
                let bufferLimit = try #draw(Draw.bufferLimit, from: tc)
                let source = CountingSource(elements: jobs)
                let passthrough = Draw.passthrough(passEvery)
                let run = try await tc.withRandomCancellation { cancellation in
                    let transform: @concurrent @Sendable (Job) async -> Int? = { job in
                        cancellation.checkpoint("transform \(job) starts")
                        await pause(job)
                        cancellation.checkpoint("transform \(job) ends")
                        return job.outcome == .drop ? nil : job.value
                    }
                    // The reader runs in a task of its own, so that a
                    // deadlock fails the property instead of hanging it.
                    let reader = Task {
                        var count = 0
                        if ordered {
                            for await _ in source.compactMapAsyncOrdered(
                                concurrency: concurrency,
                                bufferLimit: bufferLimit,
                                passthrough: passthrough,
                                transform
                            ) {
                                count += 1
                                cancellation.checkpoint("read \(count)")
                            }
                        } else {
                            for await _ in source.compactMapAsyncUnordered(
                                concurrency: concurrency,
                                passthrough: passthrough,
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
                // Running transforms ignore cancellation for up to 20 ms; the
                // reader lets go of the iterator once they are done.
                let released = await eventually(within: .seconds(5)) {
                    source.released.value == source.iterators.value
                }
                #expect(
                    released,
                    "\(source.iterators.value - source.released.value) source iterators never released"
                )

                cases += 1
                if run.cancelledAt != nil {
                    cancelled += 1
                    try tc.event("cancelled during the read")
                }
                if concurrency == 1 {
                    try tc.event("one at a time")
                }
            }
            expectReached(cancelled, in: cases, "no case cancelled the reader")
        }
    }

#endif
