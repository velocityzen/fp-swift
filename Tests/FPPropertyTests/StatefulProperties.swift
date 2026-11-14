// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import HegelTesting
    import Synchronization
    import Testing

    @testable import FP

    /// `FIFOQueue` against an array.
    struct QueueModel {
        var queue: FIFOQueue<Int>
        var model: [Int] = []
    }

    let queueMachine = StateMachine<QueueModel>()
        .rule("append", weight: 2) { s, tc in
            let x = try #draw(.int(), from: tc)
            s.queue.append(x)
            s.model.append(x)
        }
        .rule("appendMany") { s, tc in
            // Enough at once to grow the ring past its capacity, often more than once.
            // Memory bounds the long branch.
            let count = try #draw(.oneOf(.int(in: 0...10), .int(in: 0...5_000)), from: tc)
            let room = s.queue.ring.slots.count
            for x in 0..<count {
                s.queue.append(x)
                s.model.append(x)
            }
            if s.queue.ring.slots.count > room {
                try tc.event("the ring grew")
            }
        }
        .rule("popMany") { s, tc in
            let count = try #draw(.oneOf(.int(in: 0...10), .int(in: 0...5_000)), from: tc)
            for _ in 0..<count {
                #expect(s.queue.popFirst() == (s.model.isEmpty ? nil : s.model.removeFirst()))
            }
        }
        .rule("popFirst") { s, _ in
            #expect(s.queue.popFirst() == (s.model.isEmpty ? nil : s.model.removeFirst()))
        }
        .invariant("keeps no element it gave out", everyStep: true) { s, _ in
            let given = s.queue.head
            let kept = s.queue.ring.slots.compactMap { $0 }.count
            #expect(kept == s.model.count, "head \(given), tail \(s.queue.tail)")
        }

    /// `RingBuffer` against a dictionary, driven the way the pipeline drives it:
    /// stores anywhere at or after `start`, takes within the ring, and moves
    /// `start` on only past an empty slot.
    struct RingModel {
        var ring: RingBuffer<Int>
        var start = 0
        var model: [Int: Int] = [:]
    }

    let ringMachine = StateMachine<RingModel>()
        .rule("store") { s, tc in
            // The ring grows to fit the offset, so memory bounds it.
            let offset = try #draw(
                .oneOf(.int(in: 0...20), .int(in: 0...(1 << 20))),
                from: tc
            )
            let x = try #draw(.int(), from: tc)
            let room = s.ring.slots.count
            s.ring.store(x, at: s.start + offset, from: s.start)
            s.model[s.start + offset] = x
            if s.ring.slots.count > room {
                try tc.event(room == 0 ? "the empty ring grew" : "the ring grew")
            }
        }
        .rule("take") { s, tc in
            try tc.assume(!s.ring.slots.isEmpty)
            let offset = try #draw(.int(in: 0...(s.ring.slots.count - 1)), from: tc)
            #expect(s.ring.take(s.start + offset) == s.model.removeValue(forKey: s.start + offset))
        }
        .rule("advance") { s, _ in
            // The pipeline takes the element at `start` before moving on.
            if !s.ring.slots.isEmpty {
                #expect(s.ring.take(s.start) == s.model.removeValue(forKey: s.start))
            }
            s.start += 1
        }
        .invariant("agrees with the model", everyStep: true) { s, _ in
            let window = s.start..<(s.start + 24)
            // Around the end of the ring; `contains` takes no index before `start`.
            let end = s.start + s.ring.slots.count
            let edge = max(s.start, end - 1)...(end + 1)
            for index in Set(window).union(edge).union(s.model.keys) {
                #expect(
                    s.ring.contains(index, from: s.start) == (s.model[index] != nil),
                    "index \(index)"
                )
            }
            #expect(s.model.keys.allSatisfy { $0 >= s.start })
        }

    /// What a task that called into the coordinator got back.
    enum Letter: Sendable {
        case reader(Bool)
        /// A worker's next element, or nil when it exits.
        case worker(id: Int, next: Int?)
        case consumer(Int?)
    }

    /// Where the tasks the coordinator machine starts leave what they got
    /// back.
    final class Mailbox: Sendable {
        private let letters = Mutex<[Letter]>([])
        private let posted = Atomic<Int>(0)

        /// Letters ever posted. Counted after the letter is in the box.
        var count: Int { posted.load(ordering: .sequentiallyConsistent) }

        func post(_ letter: Letter) {
            letters.withLock { $0.append(letter) }
            posted.add(1, ordering: .sequentiallyConsistent)
        }

        func takeAll() -> [Letter] {
            letters.withLock { letters in
                defer { letters = [] }
                return letters
            }
        }
    }

    /// The real `ConcurrentMapCoordinator`, and the tasks that call into it
    /// the way `ConcurrentMapPipeline` does: a reader, the workers, and a
    /// consumer. The machine moves them one call at a time, and after each
    /// one waits until every task has returned or is parked in the
    /// coordinator.
    ///
    /// Element `i` is the `i`th element read, and its value is `i`.
    struct CoordinatorModel<Order: DeliveryOrder>: Sendable where Order.Value == Int {
        enum Reader: Equatable, Sendable {
            /// May ask for a slot.
            case idle
            /// Asked for a slot; running or parked.
            case waiting
            /// Got a slot; may read an element or find the source's end.
            case cleared
            case stopped
        }

        enum Worker: Equatable, Sendable {
            case transforming(Int)
            /// Handed over a result; running or parked.
            case waiting
            case exited
        }

        let coordinator: ConcurrentMapCoordinator<Int, Order>
        let mailbox = Mailbox()
        let concurrency: Int
        let bufferLimit: Int
        /// How many elements the source has.
        let sourceLength: Int
        /// How often an element skips the transform, and how often the
        /// transform drops one.
        let passProbability: Double
        let dropProbability: Double
        /// How often the consumer stops early, which cancels the stream.
        let cancelProbability: Double
        /// How often the consumer is ready for a value when its turn comes:
        /// a slow one lets results pile up and the reader wait.
        let consumerReadiness: Double
        var reader = Reader.idle
        var workers: [Worker] = []
        var consumerWaiting = false
        var consumerEnded = false
        /// Elements admitted.
        var read = 0
        /// Every finished element's result, by index; nil if dropped.
        var results: [Int: Int?] = [:]
        var delivered: [Int] = []
        var cancelled = false
        var started = 0
        /// The states the machine exists to reach, seen after some step.
        var readerWaited = false
        var consumerWaited = false
        var workerWaited = false
        var bufferFilled = false

        init(
            concurrency: Int,
            bufferLimit: Int,
            sourceLength: Int,
            passProbability: Double,
            dropProbability: Double,
            cancelProbability: Double,
            consumerReadiness: Double
        ) {
            coordinator = ConcurrentMapCoordinator(
                concurrency: concurrency,
                bufferLimit: bufferLimit
            )
            self.concurrency = concurrency
            self.bufferLimit = bufferLimit
            self.sourceLength = sourceLength
            self.passProbability = passProbability
            self.dropProbability = dropProbability
            self.cancelProbability = cancelProbability
            self.consumerReadiness = consumerReadiness
        }

        /// Starts a task that calls into the coordinator and posts what it
        /// got back.
        mutating func start(_ call: @escaping @Sendable () async -> Letter) {
            started += 1
            let mailbox = mailbox
            Task { mailbox.post(await call()) }
        }

        /// The tasks the coordinator holds a continuation for.
        var parked: Int {
            coordinator.state.withLock {
                ($0.consumer == nil ? 0 : 1) + ($0.reader == nil ? 0 : 1) + $0.idle.count
            }
        }

        /// Waits until every task has posted its letter or is parked, then
        /// reads the letters. False if that takes `stallLimit`.
        ///
        /// The posted count is read first. A task counts as running until
        /// it posts, and a parked one is counted only while the coordinator
        /// holds it, so the two counts meet only when no task is running.
        mutating func settle() async -> Bool {
            let deadline = ContinuousClock.now + stallLimit
            while started - mailbox.count != parked {
                if ContinuousClock.now >= deadline {
                    return false
                }
                await Task.yield()
            }
            for letter in mailbox.takeAll() {
                switch letter {
                    case .reader(let slot):
                        reader = slot ? .cleared : .stopped
                    case .worker(let id, let next):
                        workers[id] = next.map { .transforming($0) } ?? .exited
                    case .consumer(let value):
                        consumerWaiting = false
                        if let value {
                            #expect(!consumerEnded, "the consumer got \(value) after the end")
                            delivered.append(value)
                        } else {
                            consumerEnded = true
                        }
                }
            }
            return true
        }

        mutating func settled() async throws {
            let settled = await settle()
            try #require(settled, "a task neither returned nor parked")
            readerWaited = readerWaited || reader == .waiting
            consumerWaited = consumerWaited || consumerWaiting
            workerWaited = workerWaited || workers.contains(.waiting)
            let early = coordinator.state.withLock { $0.results.early }
            bufferFilled = bufferFilled || (bufferLimit > 0 && early == bufferLimit)
        }

        /// The reader stops, as when its source ends or the pipeline is
        /// cancelled.
        mutating func stopReader() {
            coordinator.finish()
            reader = .stopped
        }

        /// Runs the stream to its end: the reader finds the source's end, every
        /// transform finishes with its value, and the consumer reads on. True
        /// if every task returned.
        mutating func drain() async -> Bool {
            while true {
                var acted = false
                switch reader {
                    case .cleared:
                        stopReader()
                        acted = true
                    case .idle:
                        askForSlot()
                        acted = true
                    case .waiting, .stopped: break
                }
                for id in workers.indices {
                    if case .transforming(let index) = workers[id] {
                        finish(worker: id, index: index, with: index)
                        acted = true
                    }
                }
                if !consumerWaiting, !consumerEnded {
                    askForNext()
                    acted = true
                }
                guard await settle() else { return false }
                if !acted {
                    return started == mailbox.count
                }
            }
        }

        mutating func askForSlot() {
            reader = .waiting
            let coordinator = coordinator
            start {
                let slot = await coordinator.waitForSlot()
                if !slot {
                    coordinator.finish()
                }
                return .reader(slot)
            }
        }

        mutating func finish(worker id: Int, index: Int, with result: Int?) {
            results[index] = .some(result)
            workers[id] = .waiting
            let coordinator = coordinator
            start { .worker(id: id, next: await coordinator.complete(result, at: index)?.index) }
        }

        mutating func askForNext() {
            consumerWaiting = true
            let coordinator = coordinator
            start { .consumer(await coordinator.next()) }
        }
    }

    func coordinatorMachine<Order: DeliveryOrder>(
        _: Order.Type
    ) -> StateMachine<CoordinatorModel<Order>> where Order.Value == Int {
        StateMachine<CoordinatorModel<Order>>(steps: 200)
            .rule("the reader asks for a slot", weight: 2) { s, tc in
                try tc.assume(s.reader == .idle)
                s.askForSlot()
                try await s.settled()
            }
            .rule("the reader admits an element", weight: 3) { s, tc in
                try tc.assume(s.reader == .cleared && s.read < s.sourceLength)
                let index = s.read
                s.reader = .idle
                let passes = try #draw(.bool(probability: s.passProbability), from: tc)
                if passes {
                    if s.coordinator.admit(result: index) {
                        s.read += 1
                        s.results[index] = .some(index)
                    } else {
                        s.stopReader()
                    }
                } else {
                    switch s.coordinator.admit(index) {
                        case .taken:
                            s.read += 1
                        case .start(let work):
                            s.read += 1
                            #expect(work.index == index && work.element == index)
                            s.workers.append(.transforming(work.index))
                        case .cancelled:
                            s.stopReader()
                    }
                }
                try await s.settled()
            }
            .rule("the reader finds the source's end") { s, tc in
                try tc.assume(s.reader == .cleared && s.read == s.sourceLength)
                s.stopReader()
                try await s.settled()
            }
            .rule("a transform finishes", weight: 3) { s, tc in
                let running = s.workers.indices.filter {
                    if case .transforming = s.workers[$0] { true } else { false }
                }
                try tc.assume(!running.isEmpty)
                let id = try #draw(.element(of: running), from: tc)
                guard case .transforming(let index) = s.workers[id] else { return }
                let drops = try #draw(.bool(probability: s.dropProbability), from: tc)
                s.finish(worker: id, index: index, with: drops ? nil : index)
                try await s.settled()
            }
            .rule("the consumer asks for the next value", weight: 2) { s, tc in
                try tc.assume(!s.consumerWaiting)
                let ready = try #draw(.bool(probability: s.consumerReadiness), from: tc)
                try tc.assume(ready)
                s.askForNext()
                try await s.settled()
            }
            .rule("the consumer stops") { s, tc in
                try tc.assume(!s.cancelled)
                let stops = try #draw(.bool(probability: s.cancelProbability), from: tc)
                try tc.assume(stops)
                s.cancelled = true
                s.coordinator.cancel()
                try await s.settled()
            }
            .invariant("no task waits for what is there", everyStep: true) { s, _ in
                s.checkWaits(s.snapshot)
            }
            .invariant("keeps to its limits", everyStep: true) { s, _ in
                s.checkLimits(s.snapshot)
            }
            .invariant("delivers each finished value once", everyStep: true) { s, _ in
                s.checkDelivery(s.snapshot)
            }
    }

    // The checks read a copy of the state, taken under the lock while every
    // task is parked or done. Closures nested in a `withLock` closure in
    // this generic code were miscompiled (Swift 6.4): one ran with another's
    // captures.
    extension CoordinatorModel {
        typealias State = ConcurrentMapCoordinator<Int, Order>.State

        var snapshot: State { coordinator.state.withLock { $0 } }

        /// No task is parked while what it waits for is there: the lost
        /// wakeups.
        func checkWaits(_ state: State) {
            if state.consumer != nil {
                #expect(!state.cancelled, "the consumer waits after the cancel")
                // A copy of the results only: `State.takeNext` frees slots,
                // which resumes the real reader.
                var results = state.results
                #expect(results.takeNext() == nil, "the consumer waits for a ready result")
                #expect(
                    !(state.finished && state.pending == 0),
                    "the consumer waits after the end"
                )
            }
            if state.reader != nil {
                #expect(!state.cancelled, "the reader waits after the cancel")
                #expect(!state.mayAdmit, "the reader waits for a free slot")
            }
            if !state.idle.isEmpty {
                #expect(
                    state.queue.head == state.queue.tail,
                    "a worker waits beside a queued element"
                )
                #expect(!state.finished && !state.cancelled, "a worker waits after the end")
            }
        }

        func checkLimits(_ state: State) {
            #expect(state.admitted == read)
            #expect(state.workers == workers.count)
            #expect(state.workers <= concurrency)
            #expect(state.results.early <= bufferLimit)
            // In completion order no result is early, so every admitted
            // element holds a slot until the consumer takes it or it drops.
            if state.results is CompletionOrder<Int> {
                #expect(state.pending <= concurrency, "more elements hold a slot than concurrency")
            }
        }

        func checkDelivery(_ state: State) {
            let finished = Set(results.keys)
            if let order = state.results as? SourceOrder<Int> {
                let due = order.due
                #expect(
                    (0..<due).allSatisfy(finished.contains),
                    "delivered past a running element"
                )
                var values: [Int] = []
                for index in 0..<due {
                    if case .some(.some(let value)) = results[index] {
                        values.append(value)
                    }
                }
                #expect(delivered == values)
                // `SourceOrder.init`: `ready` never spans more than
                // `concurrency + bufferLimit` indices.
                let (bound, overflow) = concurrency.addingReportingOverflow(bufferLimit)
                #expect(overflow || state.admitted - due <= bound)
                // Once cancelled, results are no longer kept.
                if !state.cancelled {
                    // Element `read` is not admitted yet, so never finished.
                    var frontier = due
                    while finished.contains(frontier) {
                        frontier += 1
                    }
                    #expect(order.frontier == frontier)
                    #expect(order.early == finished.filter { $0 > frontier }.count)
                }
            }
            if let order = state.results as? CompletionOrder<Int> {
                let waiting = order.ready.ring.slots.compactMap { $0 }
                var values: [Int] = []
                for case .some(let value) in results.values {
                    values.append(value)
                }
                #expect(Set(delivered).count == delivered.count, "a value delivered twice")
                #expect(delivered.allSatisfy(finished.contains))
                if !state.cancelled {
                    #expect((delivered + waiting).sorted() == values.sorted())
                }
            }
        }
    }

    /// What the workers did to a gate.
    final class GateRig: Sendable {
        let gate: Gate<Int>
        let parties: Int
        /// Whether the workers call `open` at all. One almost always does in
        /// a long run, before the last arrival.
        let opens: Bool
        /// Every value passed to `open` or `arrive`, and the arrivals.
        let calls = Mutex<(values: Set<Int>, opens: Int, arrivals: Int, firstSeen: Int?)>(
            ([], 0, 0, nil)
        )

        /// The one task that waits on the gate, once a worker starts it.
        let waiter = Mutex<Task<Int, Never>?>(nil)
        /// What `wait()` returned to it.
        let waited = Mutex<Int?>(nil)
        /// Whether the gate was closed when the waiter started.
        let waiterSawItClosed = Mutex(false)

        init(parties: Int, opens: Bool) {
            self.parties = parties
            self.opens = opens
            gate = Gate(parties: parties)
        }

        var value: Int? { gate.state.withLock { $0.value } }

        /// Starts the waiter, unless a worker already did: a gate has one
        /// waiter.
        func startWaiter() {
            waiter.withLock { waiter in
                guard waiter == nil else { return }
                waiterSawItClosed.withLock { $0 = value == nil }
                waiter = Task {
                    let value = await gate.wait()
                    waited.withLock { $0 = value }
                    return value
                }
            }
        }
    }

    let gateMachine = ConcurrentStateMachine<GateRig>(steps: 80, concurrency: 2...4)
        .rule("open") { rig, tc in
            guard rig.opens else { return }
            let x = try #draw(.int(), from: tc)
            rig.calls.withLock {
                $0.values.insert(x)
                $0.opens += 1
            }
            rig.gate.open(with: x)
        }
        .rule("arrive", weight: 3) { rig, tc in
            let x = try #draw(.int(), from: tc)
            rig.calls.withLock {
                $0.values.insert(x)
                $0.arrivals += 1
            }
            rig.gate.arrive(orOpenWith: x)
        }
        .rule("wait") { rig, _ in
            rig.startWaiter()
        }
        .invariant("opens once, when it should", everyStep: true) { rig, tc in
            // Read before the gate's value: a waiter that returned saw the gate
            // open, and it never closes.
            let waited = rig.waited.withLock { $0 }
            let value = rig.value
            let calls = rig.calls.withLock { calls in
                if calls.firstSeen == nil { calls.firstSeen = value }
                return calls
            }
            let opened = calls.opens > 0
            let arrived = rig.parties > 0 && calls.arrivals >= rig.parties
            #expect((value != nil) == (opened || arrived))
            if arrived, !opened {
                try tc.event("opened by the last arrival")
            }
            if let waited {
                #expect(waited == value, "the waiter got \(waited), not the gate's value")
            }
            if let value {
                #expect(calls.values.contains(value))
                #expect(calls.firstSeen == value, "the gate's value changed")
                // An open gate returns its value at once, without parking:
                // the waiter's slot is not touched.
                #expect(await rig.gate.wait() == value)
            }
        }

    @Suite("Stateful properties", .hegel)
    struct StatefulProperties {
        /// None, a few, or more than the pipeline preallocates.
        static let capacity: Gen<Int> = .oneOf(
            .int(in: 0...8),
            .int(in: 1_000...1_100),
            // Memory bounds the rest.
            .int(in: 0...(1 << 20))
        )

        /// `FIFOQueue` gives back its elements in the order they went in, from any
        /// starting capacity, and keeps none it gave out.
        @Test(.hegel(testCases: cases(300)))
        func fifoQueue() throws {
            try property { tc in
                let capacity = try #draw(Self.capacity, from: tc)
                try queueMachine.run(tc, from: QueueModel(queue: FIFOQueue(capacity: capacity)))
            }
        }

        /// `RingBuffer` holds what a dictionary by index would, from any starting
        /// capacity and index.
        @Test(.hegel(testCases: cases(300)))
        func ringBuffer() throws {
            try property { tc in
                let capacity = try #draw(Self.capacity, from: tc)
                // Indices count elements, so they can get large in a long
                // stream; the ring must mask them the same way.
                // Any start that leaves room for the offsets after it.
                let start = try #draw(
                    .oneOf(.just(0), .int(in: 0...(Int.max - (1 << 22)))),
                    from: tc
                )
                try ringMachine.run(
                    tc,
                    from: RingModel(ring: RingBuffer(capacity: capacity), start: start)
                )
            }
        }

        /// The coordinator in source order: values in index order, no task
        /// left waiting for what is there, and every task returns once the
        /// stream ends.
        @Test(.hegel(testCases: cases(200)))
        func coordinatorInSourceOrder() async throws {
            try await Self.runCoordinator(SourceOrder<Int>.self)
        }

        /// The coordinator in completion order: each value once, no task
        /// left waiting for what is there, and every task returns once the
        /// stream ends.
        @Test(.hegel(testCases: cases(200)))
        func coordinatorInCompletionOrder() async throws {
            try await Self.runCoordinator(CompletionOrder<Int>.self)
        }

        static func runCoordinator<Order: DeliveryOrder>(
            _ order: Order.Type
        ) async throws where Order.Value == Int {
            let machine = coordinatorMachine(order)
            let ordered = order == SourceOrder<Int>.self
            var claims = [
                "the reader waited for a slot",
                "the consumer waited",
                "a worker waited for an element",
            ]
            if ordered {
                claims.append("early results filled the buffer")
            }
            try await property(reaching: claims) { tc in
                // Small limits half the time: with large ones the reader never
                // waits for a slot.
                let concurrency = try #draw(
                    .oneOf(.int(in: 1...4), .int(in: 1...8), .int(in: 1...Int.max), .just(.max)),
                    from: tc
                )
                let bufferLimit = try #draw(
                    .oneOf(
                        .int(in: 0...4),
                        .int(in: 1...3),
                        .int(in: 0...8),
                        .int(in: 0...Int.max),
                        .just(.max)
                    ),
                    from: tc
                )
                // The machine's steps bound how many are read.
                let sourceLength = try #draw(.oneOf(.int(in: 0...5), .int(in: 0...60)), from: tc)
                let passProbability = try #draw(.element(of: [0, 0.1, 0.5]), from: tc)
                let dropProbability = try #draw(.element(of: [0, 0.2, 0.6]), from: tc)
                let cancelProbability = try #draw(.element(of: [0, 0, 0, 0.005, 0.1]), from: tc)
                let consumerReadiness = try #draw(.element(of: [0.1, 0.4, 1]), from: tc)
                var model = try await machine.run(
                    tc,
                    from: CoordinatorModel<Order>(
                        concurrency: concurrency,
                        bufferLimit: bufferLimit,
                        sourceLength: sourceLength,
                        passProbability: passProbability,
                        dropProbability: dropProbability,
                        cancelProbability: cancelProbability,
                        consumerReadiness: consumerReadiness
                    )
                )
                let drained = await model.drain()
                #expect(drained, "a task was left waiting after the stream ended")
                #expect(model.consumerEnded)
                if !model.cancelled {
                    #expect(model.results.count == model.read, "an admitted element never finished")
                    var values: [Int] = []
                    for index in 0..<model.read {
                        if case .some(.some(let value)) = model.results[index] {
                            values.append(value)
                        }
                    }
                    if ordered {
                        #expect(model.delivered == values)
                    } else {
                        #expect(model.delivered.sorted() == values)
                    }
                }

                if model.cancelled {
                    try tc.event("cancelled")
                }
                try tc.event("elements read", value: Double(model.read))
                if model.readerWaited {
                    try tc.event("the reader waited for a slot")
                }
                if model.consumerWaited {
                    try tc.event("the consumer waited")
                }
                if model.workerWaited {
                    try tc.event("a worker waited for an element")
                }
                if model.bufferFilled {
                    try tc.event("early results filled the buffer")
                }
            }
        }

        /// A gate opens once, with the first value given or at the last arrival,
        /// and its waiter gets that value, whatever the workers do at once.
        @Test(.hegel(Settings(testCases: cases(200), nondeterminism: .warn)))
        func gateUnderConcurrentUse() async throws {
            try await property { tc in
                // No parties, or fewer than can arrive, or more; a gate with no
                // parties, or a negative count, opens only with `open`.
                let parties = try #draw(
                    .oneOf(
                        .int(in: 0...6),
                        .int(in: 7...60),
                        .int(in: 0...Int.max),
                        // Below 0 it never opens by arrival; far enough above
                        // `Int.min` that the arrivals cannot overflow.
                        .int(in: (Int.min + 1_000)...(-1))
                    ),
                    from: tc
                )
                let opens = try #draw(.bool(), from: tc)
                let rig = GateRig(parties: parties, opens: opens)
                try await gateMachine.run(tc, from: rig)
                // A waiter left waiting gets the value that opens the gate, so
                // open it if no worker did.
                guard let waiter = rig.waiter.withLock({ $0 }) else { return }
                rig.gate.open(with: 0)
                // Nothing beats, so this is a time limit of `stallLimit`.
                let value = try await tc.withStallDetection(after: stallLimit) { _ in
                    await waiter.value
                }
                #expect(value == rig.value)
                if rig.waiterSawItClosed.withLock({ $0 }) {
                    try tc.event("the waiter waited on a closed gate")
                }
            }
        }

        /// `open(after:with:)` opens the gate when its time is up, or at once
        /// when its task is cancelled, unless a rival opened it first. The
        /// waiter gets whichever value came first.
        @Test(.hegel(testCases: cases(300)))
        func timedOpen() async throws {
            try await property(reaching: ["the cancelled timer opened it"]) { tc in
                let delay = try #draw(.oneOf(.int(in: 0...50), .int(in: 0...5_000)), from: tc)
                let cancelled = try #draw(.bool(), from: tc)
                let rival = try #draw(.optional(.job()), from: tc)
                let gate = Gate<Int>()
                // A cancelled timer would wait far past the stall limit, so it
                // must open the gate when cancelled, not when its time is up.
                let duration: Duration = cancelled ? stallLimit * 12 : .microseconds(delay)
                let timer = Task { await gate.open(after: duration, with: Int.min) }
                if cancelled {
                    timer.cancel()
                }
                if let rival {
                    Task {
                        await pause(rival)
                        gate.open(with: rival.value)
                    }
                }
                // Nothing beats, so this is a time limit of `stallLimit`.
                let value = try await tc.withStallDetection(after: stallLimit) { _ in
                    await gate.wait()
                }
                if let rival {
                    #expect(value == Int.min || value == rival.value)
                } else {
                    #expect(value == Int.min)
                }
                timer.cancel()

                if value == Int.min {
                    try tc.event(
                        cancelled ? "the cancelled timer opened it" : "the timer opened it"
                    )
                } else {
                    try tc.event("the rival opened it")
                }
            }
        }
    }

#endif
