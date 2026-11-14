// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import FP
    import HegelTesting
    import Testing

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
        @Test(.hegel(testCases: 2_000))
        func cancellingTheReaderEndsTheRead() async throws {
            try await property(reaching: ["cancelled during the read"]) { tc in
                let mix = try #draw(Draw.outcomes([.keep, .drop]), from: tc)
                let jobs = try #draw(Draw.jobs(mix, min: 1), from: tc)
                let passEvery = try #draw(Draw.passEvery, from: tc)
                let concurrency = try #draw(Draw.concurrency, from: tc)
                let ordered = try #draw(.bool(), from: tc)
                let bufferLimit = try #draw(Draw.bufferLimit, from: tc)
                let source = CountingSource(elements: jobs)
                let passthrough = Draw.passthrough(passEvery)
                // Once cancelled, the read has `stallLimit` to end: a
                // deadlock fails the property instead of hanging it.
                let run = try await tc.withRandomCancellation(endsWithin: stallLimit) {
                    cancellation in
                    let transform: @concurrent @Sendable (Job) async -> Int? = { job in
                        cancellation.checkpoint("transform \(job) starts")
                        await pause(job)
                        cancellation.checkpoint("transform \(job) ends")
                        return job.outcome == .drop ? nil : job.value
                    }
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
                // Running transforms ignore cancellation for up to 20 ms; the
                // reader lets go of the iterator once they are done.
                let released = await eventually(within: stallLimit) {
                    source.released.value == source.iterators.value
                }
                #expect(
                    released,
                    "\(source.iterators.value - source.released.value) source iterators never released"
                )

                if run.cancelledAt != nil {
                    try tc.event("cancelled during the read")
                }
                if concurrency == 1 {
                    try tc.event("one at a time")
                }
            }
        }
    }

#endif
