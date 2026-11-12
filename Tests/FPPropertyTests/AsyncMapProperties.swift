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
            let jobs = try tc.draw(Draw.jobs(), named: "jobs")
            let concurrency = try tc.draw(Draw.concurrency, named: "concurrency")
            let bufferLimit = try tc.draw(Self.bufferLimits, named: "bufferLimit")
            let yields = try tc.draw(Draw.sourceYields, named: "sourceYields")
            let consumer = try tc.draw(Draw.consumer, named: "consumer")
            let inFlight = InFlight()
            let results = await consumer.collect(
                CountingSource(elements: jobs, yields: yields).mapAsyncOrdered(
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
            let jobs = try tc.draw(Draw.jobs([.keep, .drop]), named: "jobs")
            let concurrency = try tc.draw(Draw.concurrency, named: "concurrency")
            let bufferLimit = try tc.draw(Self.bufferLimits, named: "bufferLimit")
            let yields = try tc.draw(Draw.sourceYields, named: "sourceYields")
            let consumer = try tc.draw(Draw.consumer, named: "consumer")
            // Even values skip the transform.
            let results = await consumer.collect(
                CountingSource(elements: jobs, yields: yields).compactMapAsyncOrdered(
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
            let jobs = try tc.draw(Draw.jobs([.keep, .fail]), named: "jobs")
            let concurrency = try tc.draw(Draw.concurrency, named: "concurrency")
            let bufferLimit = try tc.draw(Self.bufferLimits, named: "bufferLimit")
            let yields = try tc.draw(Draw.sourceYields, named: "sourceYields")
            let consumer = try tc.draw(Draw.consumer, named: "consumer")
            // Values divisible by 5 arrive as failures; `.fail` jobs fail in
            // the transform.
            let source = jobs.map { job -> Result<Job, JobFailure> in
                job.value.isMultiple(of: 5)
                    ? .failure(JobFailure(value: 0 &- job.value)) : .success(job)
            }
            let results = await consumer.collect(
                CountingSource(elements: source, yields: yields).flatMapAsyncOrdered(
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
            let jobs = try tc.draw(Draw.jobs([.keep, .drop]), named: "jobs")
            let concurrency = try tc.draw(Draw.concurrency, named: "concurrency")
            let yields = try tc.draw(Draw.sourceYields, named: "sourceYields")
            let inFlight = InFlight()
            let source = CountingSource(elements: jobs, yields: yields)
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
            let jobs = try tc.draw(Draw.jobs(min: 1), named: "jobs")
            let concurrency = try tc.draw(Draw.parallel, named: "concurrency")
            let wanted = try tc.draw(.int(in: 0...(jobs.count - 1)), named: "wanted")
            let ordered = try tc.draw(.bool(), named: "ordered")
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
            let jobs = try tc.draw(Draw.jobs([.keep, .keep, .drop], min: 1), named: "jobs")
            let concurrency = try tc.draw(Draw.parallel, named: "concurrency")
            let ordered = try tc.draw(.bool(), named: "ordered")
            let running = Running()
            let transform: @concurrent @Sendable (Job) async -> Int = { job in
                await running.run {
                    if job.outcome == .drop {
                        await hangUntilCancelled()
                    } else {
                        await pause(job)
                    }
                    return job.value
                }
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
            let stopped = await eventually { running.value == 0 }
            #expect(stopped, "\(running.value) transforms still running after the consumer stopped")
        }
    }
}
