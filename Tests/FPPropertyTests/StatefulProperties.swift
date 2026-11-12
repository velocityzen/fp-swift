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
            for x in 0..<count {
                s.queue.append(x)
                s.model.append(x)
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
            s.ring.store(x, at: s.start + offset, from: s.start)
            s.model[s.start + offset] = x
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

    /// `SourceOrder` driven the way `ConcurrentMapCoordinator` drives it: admit
    /// while a slot is free and the order allows it, finish admitted elements in
    /// any order, with a value or dropped, and a consumer that takes results or
    /// waits. The model is the results by index.
    struct OrderModel {
        var order: SourceOrder<Int>
        let concurrency: Int
        let bufferLimit: Int
        /// The ring's size when made. With a limit, it never grows.
        let initialSlots: Int
        var admitted = 0
        var pending = 0
        var running: [Int] = []
        /// Every finished element's result, by index.
        var results: [Int: Int?] = [:]
        /// The results the coordinator kept for later, not yet taken.
        var kept: Set<Int> = []
        var consumerWaiting = false
        var delivered: [Int] = []

        init(concurrency: Int, bufferLimit: Int) {
            order = SourceOrder(concurrency: concurrency, bufferLimit: bufferLimit)
            self.concurrency = concurrency
            self.bufferLimit = bufferLimit
            initialSlots = order.ready.slots.count
        }

        var mayAdmit: Bool {
            pending - order.early < concurrency && order.mayAdmit(admitted)
        }

        /// `ConcurrentMapCoordinator.State.takeNext`, without the end.
        mutating func takeNext() -> Int? {
            while let result = order.takeNext() {
                kept.remove(order.due - 1)
                pending -= 1
                if let value = result { return value }
            }
            return nil
        }
    }

    let orderMachine = StateMachine<OrderModel>(steps: 200)
        .rule("admit", weight: 2) { s, tc in
            try tc.assume(s.mayAdmit)
            s.running.append(s.admitted)
            s.admitted += 1
            s.pending += 1
        }
        .rule("finish", weight: 2) { s, tc in
            try tc.assume(!s.running.isEmpty)
            let which = try #draw(.int(in: 0...(s.running.count - 1)), from: tc)
            let dropped = try #draw(.bool(), from: tc)
            let index = s.running.remove(at: which)
            let result: Int? = dropped ? nil : index &* 7
            s.results[index] = .some(result)
            // `ConcurrentMapCoordinator.State.complete`.
            if let value = result {
                if s.consumerWaiting, s.order.deliverNow(index) {
                    s.delivered.append(value)
                    s.consumerWaiting = false
                    s.pending -= 1
                } else {
                    s.order.keep(value, at: index)
                    s.kept.insert(index)
                }
            } else if s.order.deliverNow(index) {
                s.pending -= 1
                if s.consumerWaiting, let value = s.takeNext() {
                    s.delivered.append(value)
                    s.consumerWaiting = false
                }
            } else {
                s.order.keep(nil, at: index)
                s.kept.insert(index)
            }
        }
        .rule("consume") { s, tc in
            try tc.assume(!s.consumerWaiting)
            if let value = s.takeNext() {
                s.delivered.append(value)
            } else {
                s.consumerWaiting = true
            }
        }
        .invariant("delivers in source order", everyStep: true) { s, _ in
            let due = s.order.due
            #expect(
                (0..<due).allSatisfy { s.results[$0] != nil },
                "delivered past a running element"
            )
            #expect(s.delivered == (0..<due).compactMap { s.results[$0] ?? nil })
            #expect(s.kept.allSatisfy { $0 >= due })
        }
        .invariant("tracks the first running element", everyStep: true) { s, _ in
            let frontier = (s.order.due...).first { s.results[$0] == nil }!
            #expect(s.order.frontier == frontier)
            #expect(s.order.early == s.kept.filter { $0 > frontier }.count)
        }
        .invariant("keeps to its limits", everyStep: true) { s, _ in
            // `concurrency`: how many transforms run at once. `bufferLimit`: how
            // many results wait for an earlier element. A result that stops
            // being early when that element finishes then waits for the
            // consumer, so `pending` alone can pass `concurrency`.
            #expect(s.running.count <= s.concurrency)
            #expect(s.order.early <= s.bufferLimit)
            #expect(s.running.count + s.kept.count <= s.pending)
            // `SourceOrder.init`: `ready` never spans more than
            // `concurrency + bufferLimit` indices.
            let (bound, overflow) = s.concurrency.addingReportingOverflow(s.bufferLimit)
            #expect(overflow || s.admitted - s.order.due <= bound)
            // With a limit that fits the preallocation, the ring never grows.
            if s.bufferLimit != .max, s.concurrency <= 1_024, s.bufferLimit <= 1_024,
                s.concurrency + s.bufferLimit <= 1_024
            {
                #expect(s.order.ready.slots.count == s.initialSlots, "the ring grew")
            }
        }

    /// What the workers did to a gate.
    final class GateRig: Sendable {
        let gate: Gate<Int>
        let parties: Int
        /// Every value passed to `open` or `arrive`, and the arrivals.
        let calls = Mutex<(values: Set<Int>, opens: Int, arrivals: Int, firstSeen: Int?)>(
            ([], 0, 0, nil)
        )

        init(parties: Int) {
            self.parties = parties
            gate = Gate(parties: parties)
        }

        var value: Int? { gate.state.withLock { $0.value } }
    }

    let gateMachine = ConcurrentStateMachine<GateRig>(steps: 80, concurrency: 2...4)
        .rule("open") { rig, tc in
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
        .invariant("opens once, when it should", everyStep: true) { rig, _ in
            let value = rig.value
            let calls = rig.calls.withLock { calls in
                if calls.firstSeen == nil { calls.firstSeen = value }
                return calls
            }
            let shouldBeOpen = calls.opens > 0 || (rig.parties > 0 && calls.arrivals >= rig.parties)
            #expect((value != nil) == shouldBeOpen)
            if let value {
                #expect(calls.values.contains(value))
                #expect(calls.firstSeen == value, "the gate's value changed")
                // An open waiter returns at once, with that value.
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

        @Test(.hegel(testCases: 300))
        func fifoQueue() throws {
            try property { tc in
                let capacity = try #draw(Self.capacity, from: tc)
                try queueMachine.run(tc, from: QueueModel(queue: FIFOQueue(capacity: capacity)))
            }
        }

        @Test(.hegel(testCases: 300))
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

        @Test(.hegel(testCases: 300))
        func sourceOrder() throws {
            try property { tc in
                let concurrency = try #draw(
                    .oneOf(.int(in: 1...4), .int(in: 1...Int.max), .just(.max)),
                    from: tc
                )
                let bufferLimit = try #draw(
                    .oneOf(.int(in: 0...4), .int(in: 0...Int.max), .just(.max)),
                    from: tc
                )
                try orderMachine.run(
                    tc,
                    from: OrderModel(concurrency: concurrency, bufferLimit: bufferLimit)
                )
            }
        }

        @Test(.hegel(Settings(testCases: 200, nondeterminism: .warn)))
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
                try await gateMachine.run(tc, from: GateRig(parties: parties))
            }
        }
    }

#endif
