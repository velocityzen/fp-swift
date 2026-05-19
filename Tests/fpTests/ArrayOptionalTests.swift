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
}
