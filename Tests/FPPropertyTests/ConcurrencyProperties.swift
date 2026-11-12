// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import FP
    import HegelTesting
    import Testing

    @Suite("Concurrency helper properties", .hegel)
    struct ConcurrencyProperties {
        static func run(_ job: Job) async -> Result<Int, JobFailure> {
            await pause(job)
            return job.outcome == .fail
                ? .failure(JobFailure(value: job.value)) : .success(transformed(job))
        }

        /// With transforms that ignore cancellation, the concurrent traversal
        /// gives what the sequential one gives: every value in order, or the
        /// failure with the lowest index.
        ///
        /// Concurrency mostly stays below the element count, where a fixed set of
        /// workers claims elements; at or above it, each element gets a task.
        @Test(.hegel(testCases: 500))
        func concurrentTraverseIsSequentialTraverse() async throws {
            try await property { tc in
                let jobs = try #draw(Draw.jobs([.keep, .fail]), from: tc)
                let concurrency = try #draw(
                    .oneOf(.int(in: 1...4), .int(in: 1...16), Draw.concurrency),
                    from: tc
                )
                let inFlight = InFlight()
                let concurrent = await jobs.traverseAsync(concurrency: concurrency) { job in
                    await inFlight.run { await Self.run(job) }
                }
                let sequential = await jobs.traverseAsync { await Self.run($0) }
                #expect(concurrent == sequential)
                #expect(inFlight.peak <= concurrency)
            }
        }

        /// The race gives a success if any operation succeeds, and otherwise one
        /// of the failures, for any number of operations and any timing.
        @Test(.hegel(testCases: 500))
        func withAnyFindsASuccessIfThereIsOne() async throws {
            try await property { tc in
                let jobs = try #draw(Draw.jobs([.keep, .fail], min: 1), from: tc)
                let viaArray = try #draw(.bool(), from: tc)
                let result = viaArray ? await raceArray(jobs) : await raceArity(jobs)
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
            }
        }

        func raceArray(_ jobs: [Job]) async -> Result<Int, JobFailure> {
            await withAny(jobs.map { job in { await Self.run(job) } })
        }

        /// The `withAny` overload for `jobs.count` operations; the array one for
        /// a single job.
        func raceArity(_ jobs: [Job]) async -> Result<Int, JobFailure> {
            let j = jobs
            switch j.count {
                case 2: return await withAny(await Self.run(j[0]), await Self.run(j[1]))
                case 3:
                    return await withAny(
                        await Self.run(j[0]),
                        await Self.run(j[1]),
                        await Self.run(j[2])
                    )
                case 4:
                    return await withAny(
                        await Self.run(j[0]),
                        await Self.run(j[1]),
                        await Self.run(j[2]),
                        await Self.run(j[3])
                    )
                case 5:
                    return await withAny(
                        await Self.run(j[0]),
                        await Self.run(j[1]),
                        await Self.run(j[2]),
                        await Self.run(j[3]),
                        await Self.run(j[4])
                    )
                case 6:
                    return await withAny(
                        await Self.run(j[0]),
                        await Self.run(j[1]),
                        await Self.run(j[2]),
                        await Self.run(j[3]),
                        await Self.run(j[4]),
                        await Self.run(j[5])
                    )
                case 7:
                    return await withAny(
                        await Self.run(j[0]),
                        await Self.run(j[1]),
                        await Self.run(j[2]),
                        await Self.run(j[3]),
                        await Self.run(j[4]),
                        await Self.run(j[5]),
                        await Self.run(j[6])
                    )
                case 8:
                    return await withAny(
                        await Self.run(j[0]),
                        await Self.run(j[1]),
                        await Self.run(j[2]),
                        await Self.run(j[3]),
                        await Self.run(j[4]),
                        await Self.run(j[5]),
                        await Self.run(j[6]),
                        await Self.run(j[7])
                    )
                case 9:
                    return await withAny(
                        await Self.run(j[0]),
                        await Self.run(j[1]),
                        await Self.run(j[2]),
                        await Self.run(j[3]),
                        await Self.run(j[4]),
                        await Self.run(j[5]),
                        await Self.run(j[6]),
                        await Self.run(j[7]),
                        await Self.run(j[8])
                    )
                case 10:
                    return await withAny(
                        await Self.run(j[0]),
                        await Self.run(j[1]),
                        await Self.run(j[2]),
                        await Self.run(j[3]),
                        await Self.run(j[4]),
                        await Self.run(j[5]),
                        await Self.run(j[6]),
                        await Self.run(j[7]),
                        await Self.run(j[8]),
                        await Self.run(j[9])
                    )
                default: return await raceArray(jobs)
            }
        }

        /// A quick operation beats a long timeout, failure or not; one that
        /// never finishes on its own loses to a short timeout.
        @Test(.hegel(testCases: 500))
        func withTimeoutPicksTheFirstToFinish() async throws {
            try await property { tc in
                let job = try #draw(.job(outcomes: [.keep, .fail]), from: tc)
                // Ends when the job does, so a long limit costs nothing, and a
                // busy machine can stretch a job's pause to seconds.
                let quick = await withTimeout(.seconds(60), failingWith: JobFailure(value: -1)) {
                    await Self.run(job)
                }
                #expect(quick == (await Self.run(job)))
                let stuck = await withTimeout(
                    .microseconds(job.delay * 50),
                    failingWith: JobFailure(value: -1)
                ) {
                    try? await Task.sleep(for: .seconds(60))
                    return await Self.run(job)
                }
                #expect(stuck == .failure(JobFailure(value: -1)))
            }
        }

        /// After a failure, the transforms still running are cancelled: jobs
        /// with `.drop` hang until they are, so the traversal never waits one
        /// out.
        @Test(.hegel(testCases: 500))
        func traverseCancelsAfterAFailure() async throws {
            try await property { tc in
                let jobs = try #draw(
                    Draw.jobs([.keep, .drop, .fail], min: 2),
                    from: tc
                )
                let concurrency = try #draw(Draw.parallel, from: tc)
                // A failure every hanging job runs alongside: the first job.
                try tc.assume(jobs[0].outcome == .fail)
                let hangs = Hangs()
                let result = await jobs.traverseAsync(concurrency: concurrency) {
                    job -> Result<Int, JobFailure> in
                    switch job.outcome {
                        case .keep: return .success(job.value)
                        case .drop:
                            await hangs.hang()
                            return .success(job.value)
                        case .fail:
                            await pause(job)
                            return .failure(JobFailure(value: job.value))
                    }
                }
                #expect(result == .failure(JobFailure(value: jobs[0].value)))
                // Every transform has ended, so every hang was cancelled or
                // ran out its minute. Counted, not timed: on a busy machine
                // the other transforms' pauses can take many seconds.
                #expect(
                    hangs.uncancelled == 0,
                    "\(hangs.uncancelled) hanging transforms were never cancelled"
                )
            }
        }
    }

#endif
