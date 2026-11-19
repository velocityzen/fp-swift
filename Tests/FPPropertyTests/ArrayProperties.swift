// Hegel runs on macOS and Linux only; see Package.swift.
#if os(macOS) || os(Linux)

    import FP
    import HegelTesting
    import Testing

    /// The synchronous array helpers against models built from the standard library.
    ///
    /// From 64 elements (128 for `separate`) the helpers write into the new array's buffer, and
    /// the splitting helpers skip elements without a branch when their values are trivial.
    /// Lengths are drawn around those sizes, and values come in trivial, zero-sized and
    /// reference-counted types, so both paths of each helper are checked.
    @Suite("Array properties", .hegel)
    struct ArrayProperties {
        /// `successes()`, `failures()` and `separate()` keep every value of their side, in
        /// order, for trivial, zero-sized and reference-counted values and for `any Error`.
        @Test(.hegel(testCases: 500))
        func splittingResultsKeepsEveryValueInOrder() throws {
            try property(
                reaching: [
                    "appended", "wrote into the buffer", "separate wrote into the buffers",
                    "kept nothing", "kept everything",
                ]
            ) { tc in
                let count = try #draw(Self.length, from: tc)
                let mix = try #draw(.array(of: .bool(), count: 1...4), from: tc)
                let elements = try #draw(Self.elements(count, mix), from: tc)

                let codes = elements.map { isSuccess, value -> Result<Int, Code> in
                    isSuccess ? .success(value) : .failure(Code(value))
                }
                let messages = elements.map { isSuccess, value -> Result<String, Message> in
                    isSuccess ? .success("value \(value)") : .failure(Message(value))
                }
                let empties = elements.map { isSuccess, _ -> Result<Empty, Empty> in
                    isSuccess ? .success(Empty()) : .failure(Empty())
                }
                let anyErrors = elements.map { isSuccess, value -> Result<Int, any Error> in
                    isSuccess ? .success(value) : .failure(Code(value))
                }

                #expect(codes.successes() == Self.successes(codes))
                #expect(codes.failures() == Self.failures(codes))
                #expect(codes.separate() == (Self.successes(codes), Self.failures(codes)))

                #expect(messages.successes() == Self.successes(messages))
                #expect(messages.failures() == Self.failures(messages))
                #expect(messages.separate() == (Self.successes(messages), Self.failures(messages)))

                #expect(empties.successes() == Self.successes(empties))
                #expect(empties.failures() == Self.failures(empties))
                #expect(empties.separate() == (Self.successes(empties), Self.failures(empties)))

                let anyFailures = Self.failures(anyErrors).map { $0 as? Code }
                #expect(anyErrors.successes() == Self.successes(anyErrors))
                #expect(anyErrors.failures().map { $0 as? Code } == anyFailures)
                let separated = anyErrors.separate()
                #expect(separated.successes == Self.successes(anyErrors))
                #expect(separated.failures.map { $0 as? Code } == anyFailures)

                try Self.reportPath(count, tc)
                if count >= 128 {
                    try tc.event("separate wrote into the buffers")
                }
                if count > 0, !mix.contains(true) {
                    try tc.event("kept nothing")
                }
                if count > 0, !mix.contains(false) {
                    try tc.event("kept everything")
                }
            }
        }

        /// `compact()` keeps every non-`nil` value in order, and `sequence()` unwraps every
        /// value or gives `nil` when any element is `nil`, also for a single `nil` anywhere in
        /// a long array. `Bool?` stores `nil` in its payload's spare bits, where the other
        /// payloads need an extra tag byte.
        @Test(.hegel(testCases: 500))
        func unwrappingOptionalsMatchesTheStandardLibrary() throws {
            try property(
                reaching: ["appended", "wrote into the buffer", "one nil past 64 elements"]
            ) { tc in
                let count = try #draw(Self.length, from: tc)
                let mix = try #draw(.array(of: .bool(), count: 1...4), from: tc)
                let elements = try #draw(Self.elements(count, mix), from: tc)
                let nilAt = try #draw(.optional(.int(in: 0...max(0, count - 1))), from: tc)

                let ints = elements.map { isPresent, value in isPresent ? value : nil }
                let strings = ints.map { $0.map { "value \($0)" } }
                let bools = ints.map { $0.map { $0.isMultiple(of: 2) } }
                let empties = ints.map { $0.map { _ in Empty() } }

                #expect(ints.compact() == ints.compactMap { $0 })
                #expect(strings.compact() == strings.compactMap { $0 })
                #expect(bools.compact() == bools.compactMap { $0 })
                #expect(empties.compact() == empties.compactMap { $0 })

                #expect(ints.sequence() == Self.sequence(ints))
                #expect(strings.sequence() == Self.sequence(strings))
                #expect(bools.sequence() == Self.sequence(bools))
                #expect(empties.sequence() == Self.sequence(empties))

                // At most one nil, so `sequence()` reads up to it before it gives up.
                var present: [Int?] = elements.map { $0.value }
                var presentStrings = present.map { $0.map { "value \($0)" } }
                if let nilAt, count > 0 {
                    present[nilAt] = nil
                    presentStrings[nilAt] = nil
                }
                #expect(present.sequence() == Self.sequence(present))
                #expect(presentStrings.sequence() == Self.sequence(presentStrings))

                try Self.reportPath(count, tc)
                if let nilAt, count > 0, nilAt >= 64 {
                    try tc.event("one nil past 64 elements")
                }
            }
        }

        /// `traverse` gives every transformed value in order, or the first failure. It doesn't
        /// call the transform after a failure, and releases the values it made before it.
        @Test(.hegel(testCases: 500))
        func traverseStopsAtTheFirstFailure() throws {
            try property(
                reaching: [
                    "appended", "wrote into the buffer", "failed past 64 elements",
                    "succeeded",
                ]
            ) { tc in
                let count = try #draw(Self.length, from: tc)
                let values = try #draw(.array(of: .int(), count: count...count), from: tc)
                let failAt = try #draw(.optional(.int(in: 0...max(0, count - 1))), from: tc)
                let failure = count > 0 ? failAt : nil

                #expect(values.traverse { $0 &* 3 } == .success(values.map { $0 &* 3 }))

                let indices = Array(values.indices)
                let trivial = indices.traverse { index -> Result<Int, Code> in
                    index == failure ? .failure(Code(values[index])) : .success(values[index] &* 3)
                }
                let model: Result<[Int], Code> =
                    failure.map { .failure(Code(values[$0])) } ?? .success(values.map { $0 &* 3 })
                #expect(trivial == model)

                let life = Life()
                var calls = 0
                do {
                    let tracked = indices.traverse { index -> Result<Tracked, Code> in
                        calls += 1
                        return index == failure
                            ? .failure(Code(values[index])) : .success(Tracked(values[index], life))
                    }
                    #expect(tracked.map { $0.map(\.value) } == model.map { _ in values })
                    #expect(calls == failure.map { $0 + 1 } ?? count)
                }
                #expect(life.live == 0)

                try Self.reportPath(count, tc)
                if let failure, failure >= 64 {
                    try tc.event("failed past 64 elements")
                }
                if failure == nil {
                    try tc.event("succeeded")
                }
            }
        }

        // MARK: Inputs

        /// Lengths at the sizes where the helpers change paths, and any length up to 300.
        static let length: Gen<Int> = .oneOf(
            .element(of: [0, 1, 2, 63, 64, 65, 127, 128, 129]),
            .int(in: 0...300)
        )

        /// `count` elements, each kept or not by a flag drawn from `mix`, with a value. A mix of
        /// one flag keeps everything or nothing; the others keep a fraction at random places.
        static func elements(_ count: Int, _ mix: [Bool]) -> Gen<[(isKept: Bool, value: Int)]> {
            .array(
                of: Hegel.zip(.element(of: mix), .oneOf(.int(in: 0...99), .int()))
                    .map { (isKept: $0, value: $1) },
                count: count...count
            )
        }

        static func reportPath(_ count: Int, _ tc: TestCase) throws {
            try tc.event(count >= 64 ? "wrote into the buffer" : "appended")
        }

        // MARK: Models

        static func successes<Success, Failure>(
            _ results: [Result<Success, Failure>]
        ) -> [Success] {
            results.compactMap { result in
                if case .success(let value) = result { value } else { nil }
            }
        }

        static func failures<Success, Failure>(
            _ results: [Result<Success, Failure>]
        ) -> [Failure] {
            results.compactMap { result in
                if case .failure(let error) = result { error } else { nil }
            }
        }

        static func sequence<T>(_ values: [T?]) -> [T]? {
            values.contains { $0 == nil } ? nil : values.map { $0! }
        }
    }

    // MARK: Values

    /// A trivial error, one byte wide.
    private enum Code: Error, Equatable {
        case a, b, c

        init(_ value: Int) {
            self = [.a, .b, .c][Int(value.magnitude % 3)]
        }
    }

    /// An error that holds a reference.
    private struct Message: Error, Equatable {
        let text: String

        init(_ value: Int) {
            text = "failure \(value)"
        }
    }

    /// A value and an error with no bytes at all.
    private struct Empty: Error, Equatable {}

    /// How many `Tracked` values are alive. Each test case makes its own.
    private final class Life {
        var live = 0
    }

    /// A value that counts itself alive in its `Life`.
    private final class Tracked {
        let value: Int
        let life: Life

        init(_ value: Int, _ life: Life) {
            self.value = value
            self.life = life
            life.live += 1
        }

        deinit {
            life.live -= 1
        }
    }

#endif
