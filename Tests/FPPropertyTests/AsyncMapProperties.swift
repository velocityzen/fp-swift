// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import FP
    import HegelTesting
    import Testing

    /// The concurrent maps over async sequences, against `Array.map` as the
    /// model, for any concurrency, buffer limit and timing.
    @Suite("Async map properties", .hegel)
    struct AsyncMapProperties {
        /// `bufferLimit`: no limit half the time, a small one otherwise.
        static let bufferLimits = Draw.bufferLimit

        @Test(.hegel(testCases: 500))
        func orderedMapIsMap() async throws {
            try await property { tc in
                let jobs = try #draw(Draw.jobs(), from: tc)
                let concurrency = try #draw(Draw.concurrency, from: tc)
                let bufferLimit = try #draw(Self.bufferLimits, from: tc)
                let sourceYields = try #draw(Draw.sourceYields, from: tc)
                let consumer = try #draw(Draw.consumer, from: tc)
                let inFlight = InFlight()
                let results = await consumer.collect(
                    CountingSource(elements: jobs, yields: sourceYields).mapAsyncOrdered(
                        concurrency: concurrency,
                        bufferLimit: bufferLimit
                    ) { job in
                        await inFlight.run {
                            await pause(job)
                            return transformed(job)
                        }
                    }
                )
                #expect(results == jobs.map(transformed))
                #expect(inFlight.peak <= concurrency)
            }
        }

        @Test(.hegel(testCases: 500))
        func orderedCompactMapIsCompactMap() async throws {
            try await property { tc in
                let jobs = try #draw(Draw.jobs([.keep, .drop]), from: tc)
                let concurrency = try #draw(Draw.concurrency, from: tc)
                let bufferLimit = try #draw(Self.bufferLimits, from: tc)
                let sourceYields = try #draw(Draw.sourceYields, from: tc)
                let consumer = try #draw(Draw.consumer, from: tc)
                // Even values skip the transform.
                let results = await consumer.collect(
                    CountingSource(elements: jobs, yields: sourceYields).compactMapAsyncOrdered(
                        concurrency: concurrency,
                        bufferLimit: bufferLimit,
                        passthrough: { $0.value.isMultiple(of: 2) ? 0 &- $0.value : nil }
                    ) { job in
                        await pause(job)
                        return job.outcome == .drop ? nil : transformed(job)
                    }
                )
                let expected = jobs.compactMap { job -> Int? in
                    if job.value.isMultiple(of: 2) { return 0 &- job.value }
                    return job.outcome == .drop ? nil : transformed(job)
                }
                #expect(results == expected)
            }
        }

        @Test(.hegel(testCases: 500))
        func orderedFlatMapKeepsFailuresInPlace() async throws {
            try await property { tc in
                let jobs = try #draw(Draw.jobs([.keep, .fail]), from: tc)
                let concurrency = try #draw(Draw.concurrency, from: tc)
                let bufferLimit = try #draw(Self.bufferLimits, from: tc)
                let sourceYields = try #draw(Draw.sourceYields, from: tc)
                let consumer = try #draw(Draw.consumer, from: tc)
                // Values divisible by 5 arrive as failures; `.fail` jobs fail in
                // the transform.
                let source = jobs.map { job -> Result<Job, JobFailure> in
                    job.value.isMultiple(of: 5)
                        ? .failure(JobFailure(value: 0 &- job.value)) : .success(job)
                }
                let results = await consumer.collect(
                    CountingSource(elements: source, yields: sourceYields).flatMapAsyncOrdered(
                        concurrency: concurrency,
                        bufferLimit: bufferLimit
                    ) { job -> Result<Int, JobFailure> in
                        await pause(job)
                        return job.outcome == .fail
                            ? .failure(JobFailure(value: job.value)) : .success(transformed(job))
                    }
                )
                let expected = source.map { element in
                    element.flatMap { job -> Result<Int, JobFailure> in
                        job.outcome == .fail
                            ? .failure(JobFailure(value: job.value)) : .success(transformed(job))
                    }
                }
                #expect(results == expected)
            }
        }

        @Test(.hegel(testCases: 500))
        func unorderedMapIsMapInSomeOrder() async throws {
            try await property { tc in
                let jobs = try #draw(Draw.jobs([.keep, .drop]), from: tc)
                let concurrency = try #draw(Draw.concurrency, from: tc)
                let sourceYields = try #draw(Draw.sourceYields, from: tc)
                let inFlight = InFlight()
                let source = CountingSource(elements: jobs, yields: sourceYields)
                var results: [Int] = []
                var delivered = 0
                var mostReadAhead = 0
                for await value in source.compactMapAsyncUnordered(
                    concurrency: concurrency,
                    passthrough: { $0.value.isMultiple(of: 3) ? 0 &- $0.value : nil },
                    { job in
                        await inFlight.run {
                            await pause(job)
                            return job.outcome == .drop ? nil : transformed(job)
                        }
                    }
                ) {
                    results.append(value)
                    delivered += 1
                    mostReadAhead = max(mostReadAhead, source.reads.value - delivered)
                }
                let expected = jobs.compactMap { job -> Int? in
                    if job.value.isMultiple(of: 3) { return 0 &- job.value }
                    return job.outcome == .drop ? nil : transformed(job)
                }
                #expect(results.sorted() == expected.sorted())
                #expect(inFlight.peak <= concurrency)
                // Dropped elements are read and never delivered, so only
                // streams that drop nothing bound the read-ahead.
                if expected.count == jobs.count {
                    #expect(mostReadAhead <= concurrency)
                }
            }
        }

        @Test(.hegel(testCases: 500))
        func stoppingEarlyStopsReading() async throws {
            try await property { tc in
                let jobs = try #draw(Draw.jobs(min: 1), from: tc)
                let concurrency = try #draw(Draw.parallel, from: tc)
                let wanted = try #draw(.int(in: 0...(jobs.count - 1)), from: tc)
                let ordered = try #draw(.bool(), from: tc)
                let source = CountingSource(elements: jobs)
                var taken = 0
                if ordered {
                    for await _ in source.mapAsyncOrdered(
                        concurrency: concurrency,
                        bufferLimit: 0,
                        { job in
                            await pause(job)
                            return job.value
                        }
                    ) {
                        if taken == wanted { break }
                        taken += 1
                    }
                } else {
                    for await _ in source.mapAsyncUnordered(
                        concurrency: concurrency,
                        { job in
                            await pause(job)
                            return job.value
                        }
                    ) {
                        if taken == wanted { break }
                        taken += 1
                    }
                }
                // Give a reader that ignored the stop time to read on.
                try? await Task.sleep(for: .milliseconds(2))
                let reads = source.reads.value
                tc.note("reads after stopping: \(reads)")
                // A bound that cannot overflow when `concurrency` is `Int.max`.
                #expect(reads - wanted - 1 <= concurrency)
            }
        }

        /// Jobs with `.drop` hang until cancelled. Once the consumer has what it
        /// came for and stops, every running transform is cancelled.
        @Test(.hegel(testCases: 500))
        func stoppingCancelsRunningTransforms() async throws {
            try await property { tc in
                let jobs = try #draw(Draw.jobs([.keep, .keep, .drop], min: 1), from: tc)
                let concurrency = try #draw(Draw.parallel, from: tc)
                let ordered = try #draw(.bool(), from: tc)
                let hangs = Hangs()
                let transform: @concurrent @Sendable (Job) async -> Int = { job in
                    if job.outcome == .drop {
                        await hangs.hang()
                    } else {
                        await pause(job)
                    }
                    return job.value
                }
                // Take one result, from a job that doesn't hang, then stop. The
                // first `concurrency` jobs are the ones that start, so one of
                // them must not hang.
                try tc.assume(jobs.prefix(concurrency).contains { $0.outcome != .drop })
                if ordered {
                    try tc.assume(jobs[0].outcome != .drop)
                    for await _ in CountingSource(elements: jobs).mapAsyncOrdered(
                        concurrency: concurrency,
                        transform
                    ) {
                        break
                    }
                } else {
                    for await _ in CountingSource(elements: jobs).mapAsyncUnordered(
                        concurrency: concurrency,
                        transform
                    ) {
                        break
                    }
                }
                // Releasing the iterator cancels the running transforms. The
                // wait covers one that was given an element just before and
                // is only now starting its hang. It waits for cancellations,
                // not for the cancelled tasks to finish, which on a busy
                // machine can take many seconds.
                let cancelled = await eventually { hangs.uncancelled == 0 }
                #expect(
                    cancelled,
                    "\(hangs.uncancelled) hanging transforms not cancelled after the consumer stopped"
                )
            }
        }
    }

#endif
