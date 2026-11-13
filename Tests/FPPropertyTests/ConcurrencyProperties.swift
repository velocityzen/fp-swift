// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import FP
    import HegelTesting
    import Testing

    /// Every call runs under `unlessStalled`: a lost wakeup fails the property
    /// with a shrunk example instead of hanging the test run.
    @Suite("Concurrency helper properties", .hegel)
    struct ConcurrencyProperties {
        static func run(_ job: Job, _ heartbeat: Heartbeat? = nil) async -> Result<Int, JobFailure>
        {
            await pause(job, heartbeat)
            return job.outcome == .fail
                ? .failure(JobFailure(value: job.value)) : .success(transformed(job))
        }

        /// Like `run`, but a job with `.drop` hangs until it is cancelled.
        static func runOrHang(
            _ job: Job,
            _ hangs: Hangs,
            _ heartbeat: Heartbeat
        ) async -> Result<Int, JobFailure> {
            if job.outcome == .drop {
                await hangs.hang()
                return .success(transformed(job))
            }
            return await run(job, heartbeat)
        }

        /// With transforms that ignore cancellation, the concurrent traversal
        /// gives what the sequential one gives: every value in order, or the
        /// failure with the lowest index. After a failure, no new transform
        /// starts.
        ///
        /// Concurrency mostly stays below the element count, where a fixed set of
        /// workers claims elements; at or above it, each element gets a task.
        @Test(.hegel(testCases: 500))
        func concurrentTraverseIsSequentialTraverse() async throws {
            var cases = 0
            var workerPool = 0
            var taskPerElement = 0
            try await property { tc in
                let jobs = try #draw(Draw.jobs([.keep, .fail]), from: tc)
                let concurrency = try #draw(
                    .oneOf(.int(in: 1...4), .int(in: 1...16), Draw.concurrency),
                    from: tc
                )
                let heartbeat = Heartbeat()
                let inFlight = InFlight()
                let lateStarts = Counter()
                let traversed = await unlessStalled(heartbeat) {
                    await jobs.traverseAsync(concurrency: concurrency) {
                        job -> Result<Int, JobFailure> in
                        if Task.isCancelled {
                            lateStarts.add()
                        }
                        return await inFlight.run { await Self.run(job, heartbeat) }
                    }
                }
                let concurrent = try #require(traversed, "the traversal stalled")
                let sequential = await jobs.traverseAsync { await Self.run($0) }
                #expect(concurrent == sequential)
                #expect(inFlight.peak <= concurrency)
                // The traversal is cancelled after the first failure, which has
                // stopped the workers from claiming more. Each other worker may
                // still start one element it claimed just before.
                #expect(
                    lateStarts.value < concurrency,
                    "\(lateStarts.value) transforms started after the traversal was cancelled"
                )

                cases += 1
                if concurrency > 1, jobs.count > 1 {
                    if concurrency >= jobs.count {
                        taskPerElement += 1
                        try tc.event("task per element")
                    } else {
                        workerPool += 1
                        try tc.event("worker pool")
                    }
                }
                if let index = jobs.firstIndex(where: { $0.outcome == .fail }),
                    concurrency < jobs.count - index - 1
                {
                    try tc.event("failed with elements left to claim")
                }
            }
            expectReached(workerPool, in: cases, "no case ran the worker pool")
            expectReached(taskPerElement, in: cases, "no case ran a task per element")
        }

        /// The race gives a success if any operation succeeds, and otherwise one
        /// of the failures, for any number of operations and any timing.
        @Test(.hegel(testCases: 500))
        func withAnyFindsASuccessIfThereIsOne() async throws {
            try await property { tc in
                let jobs = try #draw(Draw.jobs([.keep, .fail], min: 1), from: tc)
                let viaArray = try #draw(.bool(), from: tc)
                let heartbeat = Heartbeat()
                let raced = await unlessStalled(heartbeat) {
                    viaArray
                        ? await Self.raceArray(jobs, heartbeat)
                        : await Self.raceArity(jobs, heartbeat)
                }
                let result = try #require(raced, "the race stalled")
                let successes = Set(jobs.filter { $0.outcome == .keep }.map(transformed))
                let failures = Set(
                    jobs.filter { $0.outcome == .fail }.map { JobFailure(value: $0.value) }
                )
                switch result {
                    case .success(let value):
                        #expect(successes.contains(value))
                    case .failure(let failure):
                        #expect(successes.isEmpty, "a failure won although an operation succeeded")
                        #expect(failures.contains(failure))
                }

                try tc.event(
                    successes.isEmpty ? "every operation failed" : "an operation succeeded"
                )
                if !viaArray, (2...10).contains(jobs.count) {
                    try tc.event("a fixed-arity withAny")
                }
            }
        }

        static func raceArray(
            _ jobs: [Job],
            _ heartbeat: Heartbeat
        ) async -> Result<Int, JobFailure> {
            await withAny(jobs.map { job in { await Self.run(job, heartbeat) } })
        }

        /// The `withAny` overload for `jobs.count` operations; the array one for
        /// a single job or more than ten.
        static func raceArity(
            _ jobs: [Job],
            _ heartbeat: Heartbeat
        ) async -> Result<Int, JobFailure> {
            let j = jobs
            let h = heartbeat
            switch j.count {
                case 2: return await withAny(await Self.run(j[0], h), await Self.run(j[1], h))
                case 3:
                    return await withAny(
                        await Self.run(j[0], h),
                        await Self.run(j[1], h),
                        await Self.run(j[2], h)
                    )
                case 4:
                    return await withAny(
                        await Self.run(j[0], h),
                        await Self.run(j[1], h),
                        await Self.run(j[2], h),
                        await Self.run(j[3], h)
                    )
                case 5:
                    return await withAny(
                        await Self.run(j[0], h),
                        await Self.run(j[1], h),
                        await Self.run(j[2], h),
                        await Self.run(j[3], h),
                        await Self.run(j[4], h)
                    )
                case 6:
                    return await withAny(
                        await Self.run(j[0], h),
                        await Self.run(j[1], h),
                        await Self.run(j[2], h),
                        await Self.run(j[3], h),
                        await Self.run(j[4], h),
                        await Self.run(j[5], h)
                    )
                case 7:
                    return await withAny(
                        await Self.run(j[0], h),
                        await Self.run(j[1], h),
                        await Self.run(j[2], h),
                        await Self.run(j[3], h),
                        await Self.run(j[4], h),
                        await Self.run(j[5], h),
                        await Self.run(j[6], h)
                    )
                case 8:
                    return await withAny(
                        await Self.run(j[0], h),
                        await Self.run(j[1], h),
                        await Self.run(j[2], h),
                        await Self.run(j[3], h),
                        await Self.run(j[4], h),
                        await Self.run(j[5], h),
                        await Self.run(j[6], h),
                        await Self.run(j[7], h)
                    )
                case 9:
                    return await withAny(
                        await Self.run(j[0], h),
                        await Self.run(j[1], h),
                        await Self.run(j[2], h),
                        await Self.run(j[3], h),
                        await Self.run(j[4], h),
                        await Self.run(j[5], h),
                        await Self.run(j[6], h),
                        await Self.run(j[7], h),
                        await Self.run(j[8], h)
                    )
                case 10:
                    return await withAny(
                        await Self.run(j[0], h),
                        await Self.run(j[1], h),
                        await Self.run(j[2], h),
                        await Self.run(j[3], h),
                        await Self.run(j[4], h),
                        await Self.run(j[5], h),
                        await Self.run(j[6], h),
                        await Self.run(j[7], h),
                        await Self.run(j[8], h),
                        await Self.run(j[9], h)
                    )
                default: return await raceArray(jobs, heartbeat)
            }
        }

        /// `withAll` gives every value, in argument order, when every operation
        /// succeeds, and otherwise one of the failures. It returns only after
        /// the operations still running were cancelled and stopped.
        ///
        /// Jobs with `.drop` hang until cancelled. A hang never ends on its
        /// own, so hangs run only alongside a failure.
        @Test(.hegel(testCases: 500))
        func withAllGivesEveryValueOrAFailure() async throws {
            var cases = 0
            var cancelledHangs = 0
            try await property { tc in
                let drawn = try #draw(
                    .array(of: .job(outcomes: [.keep, .fail, .drop]), count: 2...10),
                    from: tc
                )
                let failing = drawn.contains { $0.outcome == .fail }
                let jobs = drawn.map { job in
                    var job = job
                    if !failing, job.outcome == .drop {
                        job.outcome = .keep
                    }
                    return job
                }
                let heartbeat = Heartbeat()
                let hangs = Hangs()
                let combined = await unlessStalled(heartbeat) {
                    await Self.all(jobs, hangs, heartbeat)
                }
                let result = try #require(combined, "withAll stalled")
                let failures = Set(
                    jobs.filter { $0.outcome == .fail }.map { JobFailure(value: $0.value) }
                )
                switch result {
                    case .success(let values):
                        #expect(failures.isEmpty, "withAll succeeded although an operation failed")
                        #expect(values == jobs.map(transformed))
                    case .failure(let failure):
                        #expect(failures.contains(failure))
                }
                // Every operation has stopped, so every hang was cancelled.
                #expect(
                    hangs.uncancelled == 0,
                    "\(hangs.uncancelled) hanging operations were never cancelled"
                )

                cases += 1
                try tc.event(failing ? "an operation failed" : "every operation succeeded")
                if hangs.started > 0 {
                    cancelledHangs += 1
                    try tc.event("a hanging operation was cancelled")
                }
            }
            expectReached(cancelledHangs, in: cases, "no hanging operation ran beside a failure")
        }

        /// The `withAll` overload for `jobs.count` operations, its tuple as an
        /// array.
        static func all(
            _ jobs: [Job],
            _ hangs: Hangs,
            _ heartbeat: Heartbeat
        ) async -> Result<[Int], JobFailure> {
            let j = jobs
            let (s, h) = (hangs, heartbeat)
            switch j.count {
                case 2:
                    return await withAll(
                        await Self.runOrHang(j[0], s, h),
                        await Self.runOrHang(j[1], s, h)
                    ).map { [$0.0, $0.1] }
                case 3:
                    return await withAll(
                        await Self.runOrHang(j[0], s, h),
                        await Self.runOrHang(j[1], s, h),
                        await Self.runOrHang(j[2], s, h)
                    ).map { [$0.0, $0.1, $0.2] }
                case 4:
                    return await withAll(
                        await Self.runOrHang(j[0], s, h),
                        await Self.runOrHang(j[1], s, h),
                        await Self.runOrHang(j[2], s, h),
                        await Self.runOrHang(j[3], s, h)
                    ).map { [$0.0, $0.1, $0.2, $0.3] }
                case 5:
                    return await withAll(
                        await Self.runOrHang(j[0], s, h),
                        await Self.runOrHang(j[1], s, h),
                        await Self.runOrHang(j[2], s, h),
                        await Self.runOrHang(j[3], s, h),
                        await Self.runOrHang(j[4], s, h)
                    ).map { [$0.0, $0.1, $0.2, $0.3, $0.4] }
                case 6:
                    return await withAll(
                        await Self.runOrHang(j[0], s, h),
                        await Self.runOrHang(j[1], s, h),
                        await Self.runOrHang(j[2], s, h),
                        await Self.runOrHang(j[3], s, h),
                        await Self.runOrHang(j[4], s, h),
                        await Self.runOrHang(j[5], s, h)
                    ).map { [$0.0, $0.1, $0.2, $0.3, $0.4, $0.5] }
                case 7:
                    return await withAll(
                        await Self.runOrHang(j[0], s, h),
                        await Self.runOrHang(j[1], s, h),
                        await Self.runOrHang(j[2], s, h),
                        await Self.runOrHang(j[3], s, h),
                        await Self.runOrHang(j[4], s, h),
                        await Self.runOrHang(j[5], s, h),
                        await Self.runOrHang(j[6], s, h)
                    ).map { [$0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $0.6] }
                case 8:
                    return await withAll(
                        await Self.runOrHang(j[0], s, h),
                        await Self.runOrHang(j[1], s, h),
                        await Self.runOrHang(j[2], s, h),
                        await Self.runOrHang(j[3], s, h),
                        await Self.runOrHang(j[4], s, h),
                        await Self.runOrHang(j[5], s, h),
                        await Self.runOrHang(j[6], s, h),
                        await Self.runOrHang(j[7], s, h)
                    ).map { [$0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $0.6, $0.7] }
                case 9:
                    return await withAll(
                        await Self.runOrHang(j[0], s, h),
                        await Self.runOrHang(j[1], s, h),
                        await Self.runOrHang(j[2], s, h),
                        await Self.runOrHang(j[3], s, h),
                        await Self.runOrHang(j[4], s, h),
                        await Self.runOrHang(j[5], s, h),
                        await Self.runOrHang(j[6], s, h),
                        await Self.runOrHang(j[7], s, h),
                        await Self.runOrHang(j[8], s, h)
                    ).map { [$0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $0.6, $0.7, $0.8] }
                default:
                    return await withAll(
                        await Self.runOrHang(j[0], s, h),
                        await Self.runOrHang(j[1], s, h),
                        await Self.runOrHang(j[2], s, h),
                        await Self.runOrHang(j[3], s, h),
                        await Self.runOrHang(j[4], s, h),
                        await Self.runOrHang(j[5], s, h),
                        await Self.runOrHang(j[6], s, h),
                        await Self.runOrHang(j[7], s, h),
                        await Self.runOrHang(j[8], s, h),
                        await Self.runOrHang(j[9], s, h)
                    ).map { [$0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $0.6, $0.7, $0.8, $0.9] }
            }
        }

        /// A quick operation beats a long timeout, failure or not; one that
        /// never finishes on its own loses to a short timeout.
        @Test(.hegel(testCases: 500))
        func withTimeoutPicksTheFirstToFinish() async throws {
            try await property { tc in
                let job = try #draw(.job(outcomes: [.keep, .fail]), from: tc)
                let heartbeat = Heartbeat()
                let raced = await unlessStalled(heartbeat) {
                    // Ends when the job does, so a long limit costs nothing, and a
                    // busy machine can stretch a job's pause to seconds.
                    let quick = await withTimeout(.seconds(60), failingWith: JobFailure(value: -1))
                    {
                        await Self.run(job, heartbeat)
                    }
                    let stuck = await withTimeout(
                        .microseconds(job.delay * 50),
                        failingWith: JobFailure(value: -1)
                    ) {
                        try? await Task.sleep(for: .seconds(60))
                        return await Self.run(job)
                    }
                    return (quick: quick, stuck: stuck)
                }
                let (quick, stuck) = try #require(raced, "withTimeout stalled")
                #expect(quick == (await Self.run(job)))
                #expect(stuck == .failure(JobFailure(value: -1)))
            }
        }

        /// After a failure, the transforms still running are cancelled: jobs
        /// with `.drop` hang until they are, so the traversal never waits one
        /// out. No new transform starts.
        @Test(.hegel(testCases: 500))
        func traverseCancelsAfterAFailure() async throws {
            var cases = 0
            var hangsRan = 0
            var elementsLeft = 0
            try await property { tc in
                let jobs = try #draw(
                    Draw.jobs([.keep, .drop, .fail], min: 2),
                    from: tc
                )
                let concurrency = try #draw(Draw.parallel, from: tc)
                // A failure every hanging job runs alongside: the first job.
                try tc.assume(jobs[0].outcome == .fail)
                let heartbeat = Heartbeat()
                let hangs = Hangs()
                let lateStarts = Counter()
                let traversed = await unlessStalled(heartbeat) {
                    await jobs.traverseAsync(concurrency: concurrency) {
                        job -> Result<Int, JobFailure> in
                        if Task.isCancelled {
                            lateStarts.add()
                        }
                        switch job.outcome {
                            case .keep: return .success(job.value)
                            case .drop:
                                await hangs.hang()
                                return .success(job.value)
                            case .fail:
                                await pause(job, heartbeat)
                                return .failure(JobFailure(value: job.value))
                        }
                    }
                }
                let result = try #require(traversed, "the traversal stalled")
                #expect(result == .failure(JobFailure(value: jobs[0].value)))
                // Every transform has ended, so every hang was cancelled or
                // ran out its minute. Counted, not timed: on a busy machine
                // the other transforms' pauses can take many seconds.
                #expect(
                    hangs.uncancelled == 0,
                    "\(hangs.uncancelled) hanging transforms were never cancelled"
                )
                // Each other worker may start one element it claimed just
                // before the failure stopped the claims.
                #expect(
                    lateStarts.value < concurrency,
                    "\(lateStarts.value) transforms started after the traversal was cancelled"
                )

                cases += 1
                if hangs.started > 0 {
                    hangsRan += 1
                    try tc.event("a transform hung beside the failure")
                }
                if concurrency < jobs.count - 1 {
                    elementsLeft += 1
                    try tc.event("elements left to claim after the failure")
                }
            }
            expectReached(hangsRan, in: cases, "no transform hung beside the failure")
            expectReached(elementsLeft, in: cases, "no failure left elements to claim")
        }
    }

#endif
