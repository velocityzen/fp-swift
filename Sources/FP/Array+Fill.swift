// How the array helpers build their results without `append`.
//
// `append` keeps the new array's count in its buffer's header. In a loop that skips elements or
// can stop early, each append stores the count and the next one loads it back, so every element
// waits on that round trip through memory (about 1.7 ns on an M4). Writing into the buffer that
// `Array(capacity:initializingWith:)` or `Array(unsafeUninitializedCapacity:initializingWith:)`
// hands out keeps the count in a register, and a loop with a trivial transform vectorizes.

/// The array sizes from which the helpers write their results into the new array's buffer.
@usableFromInline
enum DirectFill {
    /// The fewest elements for which a helper writes into the buffer instead of appending.
    ///
    /// The initializers that hand out an uninitialized buffer allocate it through a generic
    /// path of the standard library that costs about 16 ns more per call than
    /// `reserveCapacity`. Below this size, that costs more than the writes save. A helper that
    /// fills two arrays pays it twice, and starts at twice the size.
    @inlinable
    static var minimumCount: Int { 64 }
}

extension Array {
    /// The values `extract` finds in the array, in order, collected without a branch per
    /// element. Only for a trivial `Value` (`_isPOD`).
    ///
    /// Every element writes a value into the next free slot, and only a kept one moves past it:
    /// a skipped element writes the last kept value again, into a slot that the next kept value
    /// overwrites or that stays past the array's count. Leaving copies behind like that is safe
    /// only for a value with nothing to release. A branch per element would mispredict when
    /// kept and skipped elements mix at random, which costs more than the extra writes.
    ///
    /// The new array has room for every element from the first kept one on. When nothing is
    /// kept it is empty and allocates nothing.
    @inlinable
    func trivialValues<Value>(_ extract: (Element) -> Value?) -> [Value] {
        assert(_isPOD(Value.self), "skipped slots may keep a copy, so the value must be trivial")
        return withUnsafeBufferPointer { source in
            // The first kept value is the first value a skipped element writes.
            var index = 0
            var last: Value
            while true {
                guard index < source.count else { return [] }
                if let value = extract(source[index]) {
                    last = value
                    break
                }
                index &+= 1
            }

            return [Value](unsafeUninitializedCapacity: source.count &- index) {
                buffer,
                initializedCount in
                let output = buffer.baseAddress.unsafelyUnwrapped
                // Never more kept values than elements read since the first kept one, so every
                // write lands inside the buffer.
                var written = 0
                while index < source.count {
                    let isKept: Bool
                    if let value = extract(source[index]) {
                        last = value
                        isKept = true
                    } else {
                        isKept = false
                    }
                    (output + written).initialize(to: last)
                    written &+= isKept ? 1 : 0
                    index &+= 1
                }
                initializedCount = written
            }
        }
    }
}
