import Testing

@testable import FP

@Suite("Array+Optional Tests")
struct ArrayOptionalTests {
    // MARK: - compact

    @Test("compact drops nils and unwraps remaining values")
    func compactDropsNils() {
        let xs: [Int?] = [1, nil, 2, nil, 3]

        #expect(xs.compact() == [1, 2, 3])
    }

    @Test("compact returns empty array when all elements are nil")
    func compactAllNils() {
        let xs: [Int?] = [nil, nil, nil]

        #expect(xs.compact().isEmpty)
    }

    @Test("compact returns all values when none are nil")
    func compactNoNils() {
        let xs: [Int?] = [1, 2, 3]

        #expect(xs.compact() == [1, 2, 3])
    }

    @Test("compact handles empty arrays")
    func compactEmpty() {
        let xs: [Int?] = []

        #expect(xs.compact().isEmpty)
    }

    @Test("compact preserves order")
    func compactPreservesOrder() {
        let xs: [String?] = [nil, "a", nil, "b", "c", nil]

        #expect(xs.compact() == ["a", "b", "c"])
    }

    // MARK: - sequence

    @Test("sequence returns unwrapped array when no element is nil")
    func sequenceAllPresent() {
        let xs: [Int?] = [1, 2, 3]

        #expect(xs.sequence() == [1, 2, 3])
    }

    @Test("sequence returns nil when any element is nil")
    func sequenceAnyNil() {
        let xs: [Int?] = [1, nil, 3]

        #expect(xs.sequence() == nil)
    }

    @Test("sequence returns nil when only the last element is nil")
    func sequenceLastNil() {
        let xs: [Int?] = [1, 2, nil]

        #expect(xs.sequence() == nil)
    }

    @Test("sequence returns nil when only the first element is nil")
    func sequenceFirstNil() {
        let xs: [Int?] = [nil, 2, 3]

        #expect(xs.sequence() == nil)
    }

    @Test("sequence returns empty array for empty input")
    func sequenceEmpty() {
        let xs: [Int?] = []

        #expect(xs.sequence() == [])
    }

    // MARK: - Long arrays

    // From 64 elements both write into the new array's buffer, and `compact()` skips `nil`s
    // without a branch when its values are trivial.

    @Test("compact keeps every value in order at every size", arguments: [63, 64, 65, 1_000])
    func compactLongArrays(count: Int) {
        let ints = (0..<count).map { $0.isMultiple(of: 3) ? nil : $0 }
        let bools = ints.map { $0.map { $0.isMultiple(of: 2) } }
        let strings = ints.map { $0.map { "\($0)" } }

        #expect(ints.compact() == ints.compactMap { $0 })
        #expect(bools.compact() == bools.compactMap { $0 })
        #expect(strings.compact() == strings.compactMap { $0 })
        let nils = [Int?](repeating: nil, count: count)
        #expect(nils.compact().isEmpty)
    }

    @Test("sequence finds a nil anywhere in a long array", arguments: [0, 63, 64, 999])
    func sequenceLongArrayWithANil(at index: Int) {
        var xs: [Int?] = Array(0..<1_000)
        let all: [Int]? = Array(0..<1_000)
        #expect(xs.sequence() == all)

        xs[index] = nil
        #expect(xs.sequence() == nil)
    }
}
