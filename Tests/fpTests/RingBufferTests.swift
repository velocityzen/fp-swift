import Testing

@testable import FP

/// An object to watch with a weak reference.
private final class Box {}

@Suite("RingBuffer and FIFOQueue Tests")
struct RingBufferTests {
    @Test("RingBuffer rounds its room up to a power of two")
    func roundsUpToPowerOfTwo() {
        #expect(RingBuffer<Int>.roundedUp(0) == 0)
        #expect(RingBuffer<Int>.roundedUp(1) == 1)
        #expect(RingBuffer<Int>.roundedUp(2) == 2)
        #expect(RingBuffer<Int>.roundedUp(3) == 4)
        #expect(RingBuffer<Int>.roundedUp(1024) == 1024)
        #expect(RingBuffer<Int>.roundedUp(1025) == 2048)
    }

    @Test("RingBuffer finds and takes elements by index, and grows past its room")
    func storesByIndex() {
        var ring = RingBuffer<String>(capacity: 4)
        ring.store("a", at: 10, from: 10)
        ring.store("c", at: 12, from: 10)

        #expect(ring.contains(10, from: 10))
        #expect(!ring.contains(11, from: 10))
        #expect(ring.contains(12, from: 10))
        // 14 shares a slot with 10, but is out of the range 10..<14
        #expect(!ring.contains(14, from: 10))

        // 16 is out of the range, so the ring grows to 10..<18
        ring.store("g", at: 16, from: 10)
        #expect(ring.slots.count == 8)
        #expect(ring.take(10) == "a")
        #expect(ring.take(11) == nil)
        #expect(ring.take(12) == "c")
        #expect(ring.take(16) == "g")
    }

    @Test(
        "FIFOQueue keeps the order when it wraps around and when it grows",
        arguments: [0, 1, 2, 4]
    )
    func keepsOrder(capacity: Int) {
        var queue = FIFOQueue<Int>(capacity: capacity)
        var appended = 0
        var popped: [Int] = []
        // Uneven appends and pops wrap the head around, and fill the queue
        // past its room while it is wrapped.
        for round in 0..<50 {
            for _ in 0..<(round % 7) {
                queue.append(appended)
                appended += 1
            }
            for _ in 0..<(round % 5) {
                if let element = queue.popFirst() {
                    popped.append(element)
                }
            }
        }
        while let element = queue.popFirst() {
            popped.append(element)
        }

        #expect(popped == Array(0..<appended))
        #expect(queue.popFirst() == nil)
    }

    @Test("FIFOQueue keeps no element it gave out")
    func releasesPoppedElements() {
        var queue = FIFOQueue<Box>(capacity: 4)
        weak var first: Box?
        weak var second: Box?
        do {
            let a = Box()
            let b = Box()
            first = a
            second = b
            queue.append(a)
            queue.append(b)
        }

        _ = queue.popFirst()

        // The queue still holds `second`, but no longer `first`.
        #expect(first == nil)
        #expect(second != nil)
    }

    @Test("FIFOQueue with room for its elements never grows")
    func reusesItsRoom() {
        var queue = FIFOQueue<Int>(capacity: 4)
        for element in 0..<1_000 {
            queue.append(element)
            if element >= 3 {
                _ = queue.popFirst()
            }
        }

        #expect(queue.ring.slots.count == 4)
    }
}
