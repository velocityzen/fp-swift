// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import FP
    import HegelTesting
    import Testing

    /// The sinks that read an async sequence of `Result`s into one value,
    /// against a model over the same elements as an array.
    @Suite("Sink properties", .hegel)
    struct SinkProperties {
        /// Each sink gives its model's value, reads exactly as many elements
        /// as its stop rule says, and throws the sequence's error only when
        /// it reads to the end. The same from an actor.
        @Test(.hegel(testCases: 1_000))
        func sinksMatchTheirModel() async throws {
            try await property(
                reaching: ["stopped before the end", "threw the sequence's error"]
            ) { tc in
                let sink = try #draw(.element(of: Sink.allCases), from: tc)
                let mix = try #draw(.array(of: .bool(), count: 1...4), from: tc)
                let elements = try #draw(Self.results(mix), from: tc)
                let throwsAtEnd = try #draw(.bool(), from: tc)
                let yields = try #draw(.oneOf(.just(0), .int(in: 0...3)), from: tc)
                let onActor = try #draw(.bool(), from: tc)
                let source = ThrowingSource(
                    elements: elements,
                    throwsAtEnd: throwsAtEnd,
                    yields: yields
                )
                let model = sink.model(elements)

                let outcome: Result<SinkOutput, SequenceEnded>
                do throws(SequenceEnded) {
                    outcome = .success(
                        onActor
                            ? try await SinkReader().read(source, with: sink)
                            : try await sink.read(source)
                    )
                } catch {
                    outcome = .failure(error)
                }

                #expect(source.reads.value == model.reads)
                if model.readsToEnd, throwsAtEnd {
                    #expect(outcome == .failure(SequenceEnded()))
                } else {
                    #expect(outcome == .success(model.output))
                }

                if !model.readsToEnd {
                    try tc.event("stopped before the end")
                }
                if model.readsToEnd, throwsAtEnd {
                    try tc.event("threw the sequence's error")
                }
                if elements.isEmpty {
                    try tc.event("empty sequence")
                }
            }
        }

        /// After `mapAsyncOrdered`, a sink gives its model's value over the
        /// mapped results, and once it stops, the map has read at most
        /// `concurrency + bufferLimit` elements past the ones it took.
        @Test(.hegel(testCases: 300))
        func sinksStopAConcurrentMap() async throws {
            try await property(reaching: ["the map read ahead when the sink stopped"]) { tc in
                let sink = try #draw(.element(of: Sink.allCases), from: tc)
                let mix = try #draw(Draw.outcomes([.keep, .fail]), from: tc)
                let jobs = try #draw(Draw.jobs(mix), from: tc)
                let concurrency = try #draw(Draw.parallel, from: tc)
                let bufferLimit = try #draw(Draw.bufferLimit, from: tc)
                let source = CountingSource(elements: jobs)
                let output = try await tc.withStallDetection(after: stallLimit) { heartbeat in
                    await sink.read(
                        source.beating(heartbeat).mapAsyncOrdered(
                            concurrency: concurrency,
                            bufferLimit: bufferLimit
                        ) { job in
                            await pause(job, heartbeat)
                            return Self.result(of: job)
                        }
                    )
                }
                let model = sink.model(jobs.map(Self.result(of:)))
                #expect(output == model.output)

                // Give a reader that ignored the stop time to read on.
                try? await Task.sleep(for: .milliseconds(2))
                let reads = source.reads.value
                tc.note("reads after stopping: \(reads), taken: \(model.reads)")
                #expect(reads - model.reads <= orderedReadAheadBound(concurrency, bufferLimit))

                if !model.readsToEnd {
                    try tc.event("stopped before the end")
                }
                if reads > model.reads {
                    try tc.event("the map read ahead when the sink stopped")
                }
            }
        }

        /// With `failOnCancellation` before it, each sink gives its model's
        /// value over the elements read before the cancellation, followed by
        /// the failure. It never reads the source after the cancellation, and
        /// throws the sequence's error only without one. The cancellation
        /// comes between reads, or ends the sequence like `AsyncStream`.
        @Test(.hegel(testCases: 1_000))
        func failOnCancellationEndsWithTheFailure() async throws {
            try await property(
                reaching: [
                    "the sink read the failure",
                    "the sequence ended on the cancellation",
                    "threw the sequence's error",
                ]
            ) { tc in
                let sink = try #draw(.element(of: Sink.allCases), from: tc)
                let mix = try #draw(.array(of: .bool(), count: 1...4), from: tc)
                let elements = try #draw(Self.results(mix), from: tc)
                let cancelAt = try #draw(.optional(.int(in: 0...elements.count)), from: tc)
                let endsOnCancellation = try #draw(.bool(), from: tc)
                let throwsAtEnd = try #draw(.bool(), from: tc)
                let yields = try #draw(.oneOf(.just(0), .int(in: 0...3)), from: tc)
                let source = ThrowingSource(
                    elements: elements,
                    throwsAtEnd: throwsAtEnd,
                    yields: yields,
                    cancelAt: cancelAt,
                    endsOnCancellation: endsOnCancellation
                )

                // In its own task, so the cancellation stays out of the test's.
                let outcome = await Task { () -> Result<SinkOutput, SequenceEnded> in
                    if cancelAt == 0, !endsOnCancellation {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    do throws(SequenceEnded) {
                        return .success(
                            try await sink.read(source.failOnCancellation(with: Self.cancelled))
                        )
                    } catch {
                        return .failure(error)
                    }
                }.value

                let seen = cancelAt.map { Array(elements.prefix($0)) + [.failure(Self.cancelled)] }
                let model = sink.model(seen ?? elements)
                #expect(source.reads.value == min(model.reads, cancelAt ?? .max))
                if cancelAt == nil, throwsAtEnd, model.readsToEnd {
                    #expect(outcome == .failure(SequenceEnded()))
                } else {
                    #expect(outcome == .success(model.output))
                }

                if let cancelAt, model.reads > cancelAt {
                    try tc.event("the sink read the failure")
                    if endsOnCancellation {
                        try tc.event("the sequence ended on the cancellation")
                    }
                }
                if cancelAt == 0 {
                    try tc.event("cancelled before the first read")
                }
                if cancelAt == nil, throwsAtEnd, model.readsToEnd {
                    try tc.event("threw the sequence's error")
                }
            }
        }

        static let cancelled = JobFailure(value: .min)

        /// After `asResults()`, each sink gives its model's value over the
        /// source's elements as successes, followed by the error the source
        /// throws as a failure. Nothing throws, and the source is read only
        /// as far as the sink reads.
        @Test(.hegel(testCases: 1_000))
        func asResultsEndWithTheThrownError() async throws {
            try await property(
                reaching: ["the sink read the thrown error", "stopped before the end"]
            ) { tc in
                let sink = try #draw(.element(of: Sink.allCases), from: tc)
                let values = try #draw(
                    .oneOf(
                        .array(of: .oneOf(.int(in: 0...99), .int()), count: 0...Int.max),
                        .array(of: .oneOf(.int(in: 0...99), .int()), count: 50...Int.max)
                    ),
                    from: tc
                )
                let thrown = try #draw(.optional(.int()), from: tc).map(JobFailure.init(value:))
                let yields = try #draw(.oneOf(.just(0), .int(in: 0...3)), from: tc)
                let source = ValueSource(values: values, thrown: thrown, yields: yields)

                let output = await sink.read(source.asResults())

                let seen = values.map(Element.success) + (thrown.map { [.failure($0)] } ?? [])
                let model = sink.model(seen)
                #expect(output == model.output)
                #expect(source.reads.value == min(model.reads, values.count))

                if thrown != nil, model.reads > values.count {
                    try tc.event("the sink read the thrown error")
                }
                if !model.readsToEnd {
                    try tc.event("stopped before the end")
                }
            }
        }

        /// `get()` gives the success values up to the first failure, then
        /// throws that failure, and reads nothing after it. A reader that
        /// breaks early reads only as far as it went.
        @Test(.hegel(testCases: 1_000))
        func getThrowsTheFirstFailure() async throws {
            try await property(
                reaching: ["threw a failure", "read every value", "broke early"]
            ) { tc in
                let mix = try #draw(.array(of: .bool(), count: 1...4), from: tc)
                let elements = try #draw(Self.results(mix), from: tc)
                let limit = try #draw(.optional(.int(in: 0...60)), from: tc)
                let yields = try #draw(.oneOf(.just(0), .int(in: 0...3)), from: tc)
                let source = ResultSource(elements: elements, yields: yields)

                var values: [Int] = []
                var thrown: JobFailure?
                var iterator = source.get().makeAsyncIterator()
                do throws(JobFailure) {
                    while let value = try await iterator.next() {
                        if let limit, values.count == limit { break }
                        values.append(value)
                    }
                } catch {
                    thrown = error
                    // After the failure, it ends without reading again.
                    #expect((try? await iterator.next()) == .some(nil))
                }

                let firstFailure = elements.firstIndex { !$0.isSuccess }
                let readable = elements.prefix(firstFailure.map { $0 + 1 } ?? elements.count)
                let modelValues = readable.compactMap { try? $0.get() }
                if let limit, limit < modelValues.count {
                    #expect(values == Array(modelValues.prefix(limit)))
                    #expect(thrown == nil)
                    #expect(source.reads.value == limit + 1)
                    try tc.event("broke early")
                } else {
                    #expect(values == modelValues)
                    #expect(source.reads.value == readable.count)
                    if let firstFailure, case .failure(let error) = elements[firstFailure] {
                        #expect(thrown == error)
                        try tc.event("threw a failure")
                    } else {
                        #expect(thrown == nil)
                        try tc.event("read every value")
                    }
                }
            }
        }

        /// `asResults()` then `get()` gives back the source's values and the
        /// error it throws, and reads it once.
        @Test(.hegel(testCases: 500))
        func getUndoesAsResults() async throws {
            try await property(reaching: ["threw the source's error"]) { tc in
                let values = try #draw(.array(of: .int(), count: 0...200), from: tc)
                let thrown = try #draw(.optional(.int()), from: tc).map(JobFailure.init(value:))
                let source = ValueSource(values: values, thrown: thrown, yields: 0)

                var seen: [Int] = []
                var caught: JobFailure?
                do throws(JobFailure) {
                    for try await value in source.asResults().get() { seen.append(value) }
                } catch {
                    caught = error
                }

                #expect(seen == values)
                #expect(caught == thrown)
                #expect(source.reads.value == values.count)
                if thrown != nil { try tc.event("threw the source's error") }
            }
        }

        /// `untilFailure()` and `untilSuccess()` give the elements up to and
        /// including the first failure or success. Any sink after them gives
        /// its model's value over that prefix, the source is read no further
        /// than the sink reads, and the source's own error comes through only
        /// when no element stopped it.
        @Test(.hegel(testCases: 1_000))
        func untilMatchesItsModel() async throws {
            try await property(
                reaching: ["stopped at the element", "threw the sequence's error"]
            ) { tc in
                let sink = try #draw(.element(of: Sink.allCases), from: tc)
                let stopsOnSuccess = try #draw(.bool(), from: tc)
                let mix = try #draw(.array(of: .bool(), count: 1...4), from: tc)
                let elements = try #draw(Self.results(mix), from: tc)
                let throwsAtEnd = try #draw(.bool(), from: tc)
                let yields = try #draw(.oneOf(.just(0), .int(in: 0...3)), from: tc)
                let source = ThrowingSource(
                    elements: elements,
                    throwsAtEnd: throwsAtEnd,
                    yields: yields
                )

                let outcome: Result<SinkOutput, SequenceEnded>
                do throws(SequenceEnded) {
                    let until = stopsOnSuccess ? source.untilSuccess() : source.untilFailure()
                    outcome = .success(try await sink.read(until))
                } catch {
                    outcome = .failure(error)
                }

                let stop = elements.firstIndex { $0.isSuccess == stopsOnSuccess }
                let prefix = Array(elements.prefix(stop.map { $0 + 1 } ?? elements.count))
                let model = sink.model(prefix)
                #expect(source.reads.value == min(model.reads, prefix.count))
                if stop == nil, model.readsToEnd, throwsAtEnd {
                    #expect(outcome == .failure(SequenceEnded()))
                    try tc.event("threw the sequence's error")
                } else {
                    #expect(outcome == .success(model.output))
                }
                if stop != nil, model.readsToEnd {
                    try tc.event("stopped at the element")
                }
            }
        }

        /// Results from a per-test-case mix: `true` is a success. Usually a
        /// few, sometimes hundreds.
        static func results(_ mix: [Bool]) -> Gen<[Element]> {
            let element = Hegel.zip(.element(of: mix), .oneOf(.int(in: 0...99), .int()))
                .map { success, value -> Element in
                    success ? .success(value) : .failure(JobFailure(value: value))
                }
            return .oneOf(
                .array(of: element, count: 0...Int.max),
                .array(of: element, count: 50...Int.max)
            )
        }

        static func result(of job: Job) -> Element {
            job.outcome == .fail
                ? .failure(JobFailure(value: job.value)) : .success(transformed(job))
        }
    }

    typealias Element = Result<Int, JobFailure>

    /// How a test reads a sequence of results into one value.
    enum Sink: Sendable, Hashable, CaseIterable {
        case toResult, toArray, separate, first, firstSuccess, firstError, firstSuccessOrLastError
        case last, lastSuccess, lastError, reduce, reduceInto
    }

    /// What a sink returned.
    enum SinkOutput: Sendable, Hashable {
        case values(Result<[Int], JobFailure>)
        case elements([Element])
        case separated(successes: [Int], failures: [JobFailure])
        case first(Element?)
        case firstSuccess(Int?)
        case firstError(JobFailure?)
        case firstSuccessOrLastError(Element?)
        case last(Element?)
        case lastSuccess(Int?)
        case lastError(JobFailure?)
        case reduced(Result<Int, JobFailure>)
        case reducedInto(Result<[Int], JobFailure>)
    }

    /// Depends on the order of the values, so a sink that reorders them
    /// gives a different number.
    func combine(_ accumulated: Int, _ value: Int) -> Int {
        accumulated &* 31 &+ value
    }

    extension Sink {
        /// Reads `sequence` with this sink.
        nonisolated(nonsending) func read<S: AsyncSequence>(
            _ sequence: S
        ) async throws(S.Failure) -> SinkOutput where S.Element == Element {
            switch self {
                case .toResult: return .values(try await sequence.toResult())
                case .toArray: return .elements(try await sequence.toArray())
                case .separate:
                    let (successes, failures) = try await sequence.separate()
                    return .separated(successes: successes, failures: failures)
                case .first: return .first(try await sequence.first())
                case .firstSuccess: return .firstSuccess(try await sequence.firstSuccess())
                case .firstError: return .firstError(try await sequence.firstError())
                case .firstSuccessOrLastError:
                    return .firstSuccessOrLastError(try await sequence.firstSuccessOrLastError())
                case .last: return .last(try await sequence.last())
                case .lastSuccess: return .lastSuccess(try await sequence.lastSuccess())
                case .lastError: return .lastError(try await sequence.lastError())
                case .reduce: return .reduced(try await sequence.reduce(0, combine))
                case .reduceInto:
                    return .reducedInto(
                        try await sequence.reduce(into: [Int]()) { running, value in
                            running.append(combine(running.last ?? 0, value))
                        }
                    )
            }
        }

        /// What this sink gives for `elements`, how many it reads, and
        /// whether it reads to the end, where the sequence ends or throws.
        func model(_ elements: [Element]) -> (output: SinkOutput, reads: Int, readsToEnd: Bool) {
            let values = elements.compactMap { try? $0.get() }
            let failures = elements.compactMap { element -> JobFailure? in
                guard case .failure(let error) = element else { return nil }
                return error
            }
            let firstFailure = elements.firstIndex { (try? $0.get()) == nil }
            let firstSuccess = elements.firstIndex { (try? $0.get()) != nil }

            /// Reads up to and including `index`, or to the end without one.
            func stopping(
                at index: Int?,
                _ output: SinkOutput
            ) -> (output: SinkOutput, reads: Int, readsToEnd: Bool) {
                guard let index else { return (output, elements.count, true) }
                return (output, index + 1, false)
            }

            func failure(at index: Int) -> JobFailure {
                guard case .failure(let error) = elements[index] else {
                    preconditionFailure("element \(index) is not a failure")
                }
                return error
            }

            switch self {
                case .toResult:
                    return stopping(
                        at: firstFailure,
                        .values(firstFailure.map { .failure(failure(at: $0)) } ?? .success(values))
                    )
                case .toArray:
                    return stopping(at: nil, .elements(elements))
                case .separate:
                    return stopping(at: nil, .separated(successes: values, failures: failures))
                case .first:
                    return stopping(at: elements.isEmpty ? nil : 0, .first(elements.first))
                case .firstSuccess:
                    return stopping(
                        at: firstSuccess,
                        .firstSuccess(firstSuccess.flatMap { try? elements[$0].get() })
                    )
                case .firstError:
                    return stopping(at: firstFailure, .firstError(firstFailure.map(failure(at:))))
                case .firstSuccessOrLastError:
                    return stopping(
                        at: firstSuccess,
                        .firstSuccessOrLastError(
                            firstSuccess.map { elements[$0] } ?? failures.last.map { .failure($0) }
                        )
                    )
                case .last:
                    return stopping(at: nil, .last(elements.last))
                case .lastSuccess:
                    return stopping(at: nil, .lastSuccess(values.last))
                case .lastError:
                    return stopping(at: nil, .lastError(failures.last))
                case .reduce:
                    return stopping(
                        at: firstFailure,
                        .reduced(
                            firstFailure.map { .failure(failure(at: $0)) }
                                ?? .success(values.reduce(0, combine))
                        )
                    )
                case .reduceInto:
                    return stopping(
                        at: firstFailure,
                        .reducedInto(
                            firstFailure.map { .failure(failure(at: $0)) }
                                ?? .success(scan(values))
                        )
                    )
            }
        }
    }

    /// Each value combined with the running value before it, as
    /// `reduce(into:)` builds it in the sink property.
    func scan(_ values: [Int]) -> [Int] {
        var running: [Int] = []
        for value in values {
            running.append(combine(running.last ?? 0, value))
        }
        return running
    }

    /// Reads a sequence on an actor, so the sink runs with its isolation.
    actor SinkReader {
        func read(
            _ source: ThrowingSource,
            with sink: Sink
        ) async throws(SequenceEnded) -> SinkOutput {
            try await sink.read(source)
        }
    }

    struct SequenceEnded: Error, Hashable {}

    /// A sequence of `elements` that counts reads. When `throwsAtEnd`, it
    /// throws `SequenceEnded` where it would end.
    ///
    /// With `cancelAt`, it cancels the task that reads it at that index: right
    /// after the read before it, or, when `endsOnCancellation`, in the read at
    /// that index, which then ends the sequence the way `AsyncStream` does.
    struct ThrowingSource: AsyncSequence, Sendable {
        typealias Failure = SequenceEnded

        let elements: [Element]
        let throwsAtEnd: Bool
        /// How many times each read suspends first.
        let yields: Int
        var cancelAt: Int? = nil
        var endsOnCancellation = false
        let reads = Counter()

        struct AsyncIterator: AsyncIteratorProtocol {
            typealias Failure = SequenceEnded

            let source: ThrowingSource
            var index = 0

            mutating func next() async throws(SequenceEnded) -> Element? {
                for _ in 0..<source.yields {
                    await Task.yield()
                }
                if source.endsOnCancellation, index == source.cancelAt {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return nil
                }
                guard index < source.elements.count else {
                    if source.throwsAtEnd { throw SequenceEnded() }
                    return nil
                }
                source.reads.add()
                defer { index += 1 }
                if !source.endsOnCancellation, index + 1 == source.cancelAt {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
                return source.elements[index]
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(source: self)
        }
    }

    /// A sequence of `elements` that can't throw, and counts reads.
    struct ResultSource: AsyncSequence, Sendable {
        typealias Failure = Never

        let elements: [Element]
        /// How many times each read suspends first.
        let yields: Int
        let reads = Counter()

        struct AsyncIterator: AsyncIteratorProtocol {
            let source: ResultSource
            var index = 0

            mutating func next() async -> Element? {
                for _ in 0..<source.yields {
                    await Task.yield()
                }
                guard index < source.elements.count else { return nil }
                source.reads.add()
                defer { index += 1 }
                return source.elements[index]
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(source: self)
        }
    }

    /// A sequence of `values` that counts reads, and throws `thrown` where it
    /// would end.
    struct ValueSource: AsyncSequence, Sendable {
        typealias Element = Int
        typealias Failure = JobFailure

        let values: [Int]
        let thrown: JobFailure?
        /// How many times each read suspends first.
        let yields: Int
        let reads = Counter()

        struct AsyncIterator: AsyncIteratorProtocol {
            typealias Failure = JobFailure

            let source: ValueSource
            var index = 0

            mutating func next() async throws(JobFailure) -> Int? {
                for _ in 0..<source.yields {
                    await Task.yield()
                }
                guard index < source.values.count else {
                    if let thrown = source.thrown { throw thrown }
                    return nil
                }
                source.reads.add()
                defer { index += 1 }
                return source.values[index]
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(source: self)
        }
    }

#endif
