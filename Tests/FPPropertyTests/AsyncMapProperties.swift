// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import FP
    import HegelTesting
    import Testing

    /// The concurrent maps over async sequences, against `Array.map` as the
    /// model, for any concurrency, buffer limit and timing.
    ///
    /// Every stream is read under `withStallDetection`: a lost wakeup fails the
    /// property with a shrunk example instead of hanging the test run.
    /// The most elements an ordered map reads ahead of its consumer:
    /// `concurrency` in flight or waiting for the consumer, and
    /// `bufferLimit` early results.
    ///
    /// The reader stays one short of it once there are early results. It
    /// gets there only between reading an element and handing it over, so a
    /// reader that is one too far ahead is rarely seen.
    func orderedReadAheadBound(_ concurrency: Int, _ bufferLimit: Int) -> Int {
        let (bound, overflow) = concurrency.addingReportingOverflow(bufferLimit)
        return overflow ? .max : bound
    }

    @Suite("Async map properties", .hegel)
    struct AsyncMapProperties {
        /// `bufferLimit`: no limit half the time, a small one otherwise.
        static let bufferLimits = Draw.bufferLimit

        /// `mapAsyncOrdered` gives `Array.map`'s results, runs at most
        /// `concurrency` transforms at once, and reads at most
        /// `concurrency + bufferLimit` elements ahead of the consumer, none
        /// with `concurrency` 1.
        @Test(.hegel(testCases: cases(500)))
        func orderedMapIsMap() async throws {
            try await property(reaching: ["transforms overlapped"]) { tc in
                let jobs = try #draw(Draw.jobs(), from: tc)
                let concurrency = try #draw(Draw.concurrency, from: tc)
                let bufferLimit = try #draw(Self.bufferLimits, from: tc)
                let sourceYields = try #draw(Draw.sourceYields, from: tc)
                let consumer = try #draw(Draw.consumer, from: tc)
                let inFlight = InFlight()
                let source = CountingSource(elements: jobs, yields: sourceYields)
                let readAhead = ReadAhead(of: source.reads)
                let results = try await tc.withStallDetection(after: stallLimit) { heartbeat in
                    await consumer.collect(
                        source.beating(heartbeat).mapAsyncOrdered(
                            concurrency: concurrency,
                            bufferLimit: bufferLimit
                        ) { job in
                            await inFlight.run {
                                await pause(job, heartbeat)
                                return transformed(job)
                            }
                        },
                        heartbeat,
                        readAhead
                    )
                }
                #expect(results == jobs.map(transformed))
                #expect(inFlight.peak <= concurrency)
                let bound = orderedReadAheadBound(concurrency, bufferLimit)
                #expect(readAhead.most <= bound)
                if concurrency == 1 {
                    #expect(readAhead.most == 0)
                }

                if concurrency > 1 {
                    try tc.event("concurrent pipeline")
                }
                if bufferLimit < concurrency - 1 {
                    try tc.event("bufferLimit below concurrency - 1")
                }
                if inFlight.peak > 1 {
                    try tc.event("transforms overlapped")
                }
                if concurrency > 1, bound < jobs.count {
                    try tc.event("read-ahead bound below the element count")
                }
            }
        }

        /// A slow consumer pauses the source: `mapAsyncOrdered` reads at most
        /// `concurrency + bufferLimit` elements ahead of it.
        ///
        /// `orderedMapIsMap` checks this for any limits, and rarely draws
        /// limits below the element count. Here they always are.
        @Test(.hegel(testCases: cases(200)))
        func orderedMapPausesTheSource() async throws {
            try await property(reaching: ["read ahead to within one of the bound"]) { tc in
                let concurrency = try #draw(.int(in: 2...8), from: tc)
                let bufferLimit = try #draw(.int(in: 0...6), from: tc)
                let jobs = try #draw(Draw.jobs(min: concurrency + bufferLimit + 1), from: tc)
                let consumer = try #draw(Draw.consumer, from: tc)
                let source = CountingSource(elements: jobs)
                let readAhead = ReadAhead(of: source.reads)
                let results = try await tc.withStallDetection(after: stallLimit) { heartbeat in
                    await consumer.collect(
                        source.beating(heartbeat).mapAsyncOrdered(
                            concurrency: concurrency,
                            bufferLimit: bufferLimit
                        ) { job in
                            await pause(job, heartbeat)
                            return transformed(job)
                        },
                        heartbeat,
                        readAhead
                    )
                }
                #expect(results == jobs.map(transformed))
                #expect(readAhead.most <= concurrency + bufferLimit)
                tc.note("most read ahead: \(readAhead.most)")

                if readAhead.most >= concurrency + bufferLimit - 1 {
                    try tc.event("read ahead to within one of the bound")
                }
            }
        }

        /// `compactMapAsyncOrdered` gives `Array.compactMap`'s results, with
        /// `passthrough` values in place, and its read-ahead bound counts
        /// dropped elements as delivered.
        @Test(.hegel(testCases: cases(500)))
        func orderedCompactMapIsCompactMap() async throws {
            try await property { tc in
                let mix = try #draw(Draw.outcomes([.keep, .drop]), from: tc)
                let jobs = try #draw(Draw.jobs(mix), from: tc)
                let passEvery = try #draw(Draw.passEvery, from: tc)
                let concurrency = try #draw(Draw.concurrency, from: tc)
                let bufferLimit = try #draw(Self.bufferLimits, from: tc)
                let sourceYields = try #draw(Draw.sourceYields, from: tc)
                let consumer = try #draw(Draw.consumer, from: tc)
                let source = CountingSource(elements: jobs, yields: sourceYields)
                let readAhead = ReadAhead(of: source.reads)
                let passthrough = Draw.passthrough(passEvery)
                let results = try await tc.withStallDetection(after: stallLimit) { heartbeat in
                    await consumer.collect(
                        source.beating(heartbeat).compactMapAsyncOrdered(
                            concurrency: concurrency,
                            bufferLimit: bufferLimit,
                            passthrough: passthrough
                        ) { job in
                            await pause(job, heartbeat)
                            if job.outcome == .drop {
                                readAhead.dropped.add()
                                return nil
                            }
                            return transformed(job)
                        },
                        heartbeat,
                        readAhead
                    )
                }
                let expected = jobs.compactMap { job -> Int? in
                    if let value = passthrough?(job) { return value }
                    return job.outcome == .drop ? nil : transformed(job)
                }
                #expect(results == expected)
                #expect(readAhead.most <= orderedReadAheadBound(concurrency, bufferLimit))
                if concurrency == 1 {
                    #expect(readAhead.most == 0)
                }

                if jobs.contains(where: { passthrough?($0) != nil }) {
                    try tc.event("passed an element through")
                }
                if expected.count < jobs.count {
                    try tc.event("dropped an element")
                }
                if !jobs.isEmpty, expected.isEmpty {
                    try tc.event("dropped every element")
                }
            }
        }

        /// `flatMapAsyncOrdered` gives each source failure and each transform
        /// failure in its element's place.
        @Test(.hegel(testCases: cases(500)))
        func orderedFlatMapKeepsFailuresInPlace() async throws {
            try await property { tc in
                let mix = try #draw(Draw.outcomes([.keep, .fail]), from: tc)
                let jobs = try #draw(Draw.jobs(mix), from: tc)
                let sourceFailEvery = try #draw(Draw.passEvery, from: tc)
                let concurrency = try #draw(Draw.concurrency, from: tc)
                let bufferLimit = try #draw(Self.bufferLimits, from: tc)
                let sourceYields = try #draw(Draw.sourceYields, from: tc)
                let consumer = try #draw(Draw.consumer, from: tc)
                // Values that are a multiple of `sourceFailEvery` arrive as
                // failures; `.fail` jobs fail in the transform.
                let source = jobs.map { job -> Result<Job, JobFailure> in
                    if let every = sourceFailEvery, job.value.isMultiple(of: every) {
                        return .failure(JobFailure(value: 0 &- job.value))
                    }
                    return .success(job)
                }
                let counting = CountingSource(elements: source, yields: sourceYields)
                let readAhead = ReadAhead(of: counting.reads)
                let results = try await tc.withStallDetection(after: stallLimit) { heartbeat in
                    await consumer.collect(
                        counting.beating(heartbeat).flatMapAsyncOrdered(
                            concurrency: concurrency,
                            bufferLimit: bufferLimit
                        ) { job -> Result<Int, JobFailure> in
                            await pause(job, heartbeat)
                            return job.outcome == .fail
                                ? .failure(JobFailure(value: job.value))
                                : .success(transformed(job))
                        },
                        heartbeat,
                        readAhead
                    )
                }
                let expected = source.map { element in
                    element.flatMap { job -> Result<Int, JobFailure> in
                        job.outcome == .fail
                            ? .failure(JobFailure(value: job.value)) : .success(transformed(job))
                    }
                }
                #expect(results == expected)
                #expect(readAhead.most <= orderedReadAheadBound(concurrency, bufferLimit))

                if source.contains(where: { (try? $0.get()) == nil }) {
                    try tc.event("a source failure")
                }
                if source.contains(where: { (try? $0.get())?.outcome == .fail }) {
                    try tc.event("a transform failure")
                }
            }
        }

        /// `compactMapAsyncUnordered` gives `Array.compactMap`'s results in
        /// some order, runs at most `concurrency` transforms at once, and
        /// reads at most `concurrency` elements ahead of the consumer, none
        /// with `concurrency` 1. A dropped element frees its slot.
        @Test(.hegel(testCases: cases(500)))
        func unorderedMapIsMapInSomeOrder() async throws {
            try await property(
                reaching: ["read-ahead bound below the element count", "read ahead to the bound"]
            ) { tc in
                let mix = try #draw(Draw.outcomes([.keep, .drop]), from: tc)
                let jobs = try #draw(Draw.jobs(mix), from: tc)
                let passEvery = try #draw(Draw.passEvery, from: tc)
                let concurrency = try #draw(Draw.concurrency, from: tc)
                let sourceYields = try #draw(Draw.sourceYields, from: tc)
                let consumer = try #draw(Draw.consumer, from: tc)
                let inFlight = InFlight()
                let source = CountingSource(elements: jobs, yields: sourceYields)
                let readAhead = ReadAhead(of: source.reads)
                let passthrough = Draw.passthrough(passEvery)
                let results = try await tc.withStallDetection(after: stallLimit) { heartbeat in
                    await consumer.collect(
                        source.beating(heartbeat).compactMapAsyncUnordered(
                            concurrency: concurrency,
                            passthrough: passthrough
                        ) { job in
                            await inFlight.run {
                                await pause(job, heartbeat)
                                if job.outcome == .drop {
                                    readAhead.dropped.add()
                                    return nil
                                }
                                return transformed(job)
                            }
                        },
                        heartbeat,
                        readAhead
                    )
                }
                let expected = jobs.compactMap { job -> Int? in
                    if let value = passthrough?(job) { return value }
                    return job.outcome == .drop ? nil : transformed(job)
                }
                #expect(results.sorted() == expected.sorted())
                #expect(inFlight.peak <= concurrency)
                #expect(readAhead.most <= concurrency)
                if concurrency == 1 {
                    #expect(readAhead.most == 0)
                }

                if inFlight.peak > 1 {
                    try tc.event("transforms overlapped")
                }
                // The bound can only fail with more elements than workers.
                if concurrency > 1, jobs.count > concurrency {
                    try tc.event("read-ahead bound below the element count")
                }
                if concurrency > 1, readAhead.most == concurrency {
                    try tc.event("read ahead to the bound")
                }
                if expected.count < jobs.count, jobs.count > concurrency {
                    try tc.event("dropped an element with more elements than workers")
                }
            }
        }

        /// When the consumer stops, reading stops: with no buffer, the reader is at
        /// most `concurrency` elements past the last one taken.
        @Test(.hegel(testCases: cases(500)))
        func stoppingEarlyStopsReading() async throws {
            try await property { tc in
                let jobs = try #draw(Draw.jobs(min: 1), from: tc)
                let concurrency = try #draw(Draw.parallel, from: tc)
                let wanted = try #draw(.int(in: 0...(jobs.count - 1)), from: tc)
                let ordered = try #draw(.bool(), from: tc)
                let source = CountingSource(elements: jobs)
                try await tc.withStallDetection(after: stallLimit) { heartbeat in
                    let source = source.beating(heartbeat)
                    var taken = 0
                    if ordered {
                        for await _ in source.mapAsyncOrdered(
                            concurrency: concurrency,
                            bufferLimit: 0,
                            { job in
                                await pause(job, heartbeat)
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
                                await pause(job, heartbeat)
                                return job.value
                            }
                        ) {
                            if taken == wanted { break }
                            taken += 1
                        }
                    }
                }
                // Give a reader that ignored the stop time to read on.
                try? await Task.sleep(for: .milliseconds(2))
                let reads = source.reads.value
                tc.note("reads after stopping: \(reads)")
                // A bound that cannot overflow when `concurrency` is `Int.max`.
                #expect(reads - wanted - 1 <= concurrency)

                if wanted + 1 < jobs.count {
                    try tc.event("stopped before the end")
                }
                if reads > wanted + 1 {
                    try tc.event("the reader was ahead when the consumer stopped")
                }
            }
        }

        /// Jobs with `.drop` hang until cancelled. Once the consumer has what it
        /// came for and stops, every running transform is cancelled.
        @Test(.hegel(testCases: cases(500)))
        func stoppingCancelsRunningTransforms() async throws {
            try await property(reaching: ["a transform hung when the consumer stopped"]) { tc in
                let concurrency = try #draw(Draw.parallel, from: tc)
                let ordered = try #draw(.bool(), from: tc)
                // The consumer takes one result, from a job that doesn't hang,
                // then stops. The first `concurrency` jobs are the ones that
                // start, so one of them keeps: in source order, the first.
                let jobs = try #draw(
                    Draw.jobs([.keep, .keep, .drop], min: 1).flatMap { jobs in
                        Gen.int(in: 0...(ordered ? 0 : min(concurrency, jobs.count) - 1)).map {
                            var jobs = jobs
                            jobs[$0].outcome = .keep
                            return jobs
                        }
                    },
                    from: tc
                )
                let hangs = CancellationProbe()
                try await tc.withStallDetection(after: stallLimit) { heartbeat in
                    let transform: @concurrent @Sendable (Job) async -> Int = { job in
                        if job.outcome == .drop {
                            await hangs.hang()
                        } else {
                            await pause(job, heartbeat)
                        }
                        return job.value
                    }
                    if ordered {
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

                if hangs.started > 0 {
                    try tc.event("a transform hung when the consumer stopped")
                }
            }
        }
    }

#endif
