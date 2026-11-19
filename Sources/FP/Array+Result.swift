import Synchronization

// Everything here is `@inlinable` so callers specialize it. Generic code is slower per element,
// and async generic code allocates its temporaries on the heap.

public extension Array {
    /// Transforms each element and returns the new array as a success.
    @inlinable
    func traverse<Success>(
        _ transform: (Element) -> Success
    ) -> Result<[Success], Never> {
        guard count >= DirectFill.minimumCount else {
            var results: [Success] = []
            results.reserveCapacity(count)

            for element in self {
                results.append(transform(element))
            }

            return .success(results)
        }

        return .success(
            [Success](capacity: count) { (output: inout OutputSpan<Success>) in
                for element in self {
                    output.append(transform(element))
                }
            }
        )
    }

    /// Transforms each element with a transform that can fail.
    ///
    /// Returns all values in order, or the first failure. Elements after a failure are not
    /// transformed.
    @inlinable
    func traverse<Success, Failure: Error>(
        _ transform: (Element) -> Result<Success, Failure>
    ) -> Result<[Success], Failure> {
        guard count >= DirectFill.minimumCount else {
            var results: [Success] = []
            results.reserveCapacity(count)

            for element in self {
                switch transform(element) {
                    case .success(let value):
                        results.append(value)
                    case .failure(let error):
                        return .failure(error)
                }
            }

            return .success(results)
        }

        // A failure throws out of the initializer, which releases the values written so far.
        do throws(Failure) {
            return .success(
                try [Success](capacity: count) {
                    (output: inout OutputSpan<Success>) throws(Failure) in
                    for element in self {
                        output.append(try transform(element).get())
                    }
                }
            )
        } catch {
            return .failure(error)
        }
    }

    /// Transforms each element with an async transform, one at a time.
    ///
    /// Pass `concurrency:` to run transforms at the same time.
    @inlinable
    func traverseAsync<Success>(
        _ transform: (Element) async -> Success
    ) async -> Result<[Success], Never> {
        var results: [Success] = []
        results.reserveCapacity(count)

        for element in self {
            results.append(await transform(element))
        }

        return .success(results)
    }

    /// Transforms each element with an async transform that can fail, one at a time.
    ///
    /// Returns all values in order, or the first failure. Elements after a failure do not run.
    /// Pass `concurrency:` to run transforms at the same time.
    @inlinable
    func traverseAsync<Success, Failure: Error>(
        _ transform: (Element) async -> Result<Success, Failure>
    ) async -> Result<[Success], Failure> {
        var results: [Success] = []
        results.reserveCapacity(count)

        for element in self {
            switch await transform(element) {
                case .success(let value):
                    results.append(value)
                case .failure(let error):
                    return .failure(error)
            }
        }

        return .success(results)
    }

    /// Transforms each element with an async transform, with up to `concurrency` running at the
    /// same time.
    ///
    /// Results keep the source order. `concurrency` must be 1 or more.
    @inlinable
    func traverseAsync<Success: Sendable>(
        concurrency: Int,
        _ transform: @concurrent @Sendable @escaping (Element) async -> Success
    ) async -> Result<[Success], Never> where Element: Sendable {
        await traverseAsync(concurrency: concurrency) { element -> Result<Success, Never> in
            .success(await transform(element))
        }
    }

    /// Transforms each element with an async transform that can fail, with up to `concurrency`
    /// running at the same time.
    ///
    /// Returns all values in source order, or the failure with the lowest index. After the
    /// first failure, no new transform starts and running ones are cancelled.
    ///
    /// - Parameters:
    ///   - concurrency: How many transforms may run at the same time. Must be 1 or more.
    ///     With 1, it works like the version without `concurrency`.
    ///   - transform: The transform for one element.
    @inlinable
    func traverseAsync<Success: Sendable, Failure: Error>(
        concurrency: Int,
        _ transform: @concurrent @Sendable @escaping (Element) async -> Result<Success, Failure>
    ) async -> Result<[Success], Failure> where Element: Sendable {
        precondition(concurrency >= 1, "concurrency must be at least 1")
        // One transform at a time, or one element: loop here, with no child task.
        guard concurrency > 1, count > 1 else {
            return await traverseAsync(transform)
        }

        let traversal = ConcurrentTraversal<Success>(count: count, claimed: concurrency)
        let failure =
            if concurrency >= count {
                await traverseWithTaskPerElement(into: traversal, transform)
            } else {
                await traverseWithWorkers(concurrency, into: traversal, transform)
            }

        if let failure {
            return .failure(failure.failure)
        }
        return .success(traversal.values())
    }

    /// Splits an array of results into its success values and its failure values.
    @inlinable
    func separate<Success, Failure>() -> (successes: [Success], failures: [Failure])
    where Element == Result<Success, Failure> {
        // Two passes without a branch per element beat one pass with a branch that
        // mispredicts, but they need trivial values. Each pass allocates its own array.
        if count >= 2 * DirectFill.minimumCount, _isPOD(Success.self), _isPOD(Failure.self) {
            return (
                successes: trivialValues { result in
                    if case .success(let value) = result { value } else { nil }
                },
                failures: trivialValues { result in
                    if case .failure(let error) = result { error } else { nil }
                }
            )
        }

        var successes: [Success] = []
        var failures: [Failure] = []
        successes.reserveCapacity(count)
        failures.reserveCapacity(count)

        for result in self {
            switch result {
                case .success(let value):
                    successes.append(value)
                case .failure(let error):
                    failures.append(error)
            }
        }

        return (successes: successes, failures: failures)
    }

    /// Returns the success values from an array of results.
    @inlinable
    func successes<Success, Failure>() -> [Success]
    where Element == Result<Success, Failure> {
        if count >= DirectFill.minimumCount, _isPOD(Success.self) {
            return trivialValues { result in
                if case .success(let value) = result { value } else { nil }
            }
        }

        var values: [Success] = []
        values.reserveCapacity(count)
        for result in self {
            if case .success(let value) = result {
                values.append(value)
            }
        }
        return values
    }

    /// Returns the failure values from an array of results.
    @inlinable
    func failures<Success, Failure>() -> [Failure]
    where Element == Result<Success, Failure> {
        if count >= DirectFill.minimumCount, _isPOD(Failure.self) {
            return trivialValues { result in
                if case .failure(let error) = result { error } else { nil }
            }
        }

        // Room for every element from the first failure on, as `successes()` reserves for
        // all of them, so the array never grows. Without a failure it allocates nothing.
        guard
            let first = firstIndex(where: { result in
                if case .failure = result { true } else { false }
            })
        else { return [] }

        var errors: [Failure] = []
        errors.reserveCapacity(count - first)
        for result in self[first...] {
            if case .failure(let error) = result {
                errors.append(error)
            }
        }
        return errors
    }
}

extension Array where Element: Sendable {
    /// Runs one child task per element. All elements run at the same time, so there is nothing
    /// to schedule: children share no state and capture only their element.
    @inlinable
    func traverseWithTaskPerElement<Success: Sendable, Failure: Error>(
        into traversal: ConcurrentTraversal<Success>,
        _ transform: @concurrent @Sendable @escaping (Element) async -> Result<Success, Failure>
    ) async -> (index: Int, failure: Failure)? {
        await withTaskGroup(of: (index: Int, result: Result<Success, Failure>).self) { group in
            for index in indices {
                let element = self[index]
                group.addTask { (index: index, result: await transform(element)) }
            }

            var lowest: (index: Int, failure: Failure)? = nil
            for await (index, result) in group {
                switch result {
                    case .success(let value):
                        traversal.store(value, at: index)
                    case .failure(let error):
                        group.cancelAll()
                        if lowest.map({ index < $0.index }) ?? true {
                            lowest = (index, error)
                        }
                }
            }
            return lowest
        }
    }

    /// Runs a fixed number of workers, because a child task per element costs more than most
    /// transforms. Each worker starts on its own element, then claims the next free one until
    /// none are left. All workers start first, so the first `workers` elements run even if one
    /// fails at once.
    @inlinable
    func traverseWithWorkers<Success: Sendable, Failure: Error>(
        _ workers: Int,
        into traversal: ConcurrentTraversal<Success>,
        _ transform: @concurrent @Sendable @escaping (Element) async -> Result<Success, Failure>
    ) async -> (index: Int, failure: Failure)? {
        await withTaskGroup(of: (index: Int, failure: Failure)?.self) { group in
            for first in 0..<workers {
                group.addTask {
                    var index = first
                    while true {
                        switch await transform(self[index]) {
                            case .success(let value):
                                traversal.store(value, at: index)
                            case .failure(let error):
                                traversal.stop()
                                return (index, error)
                        }
                        guard let next = traversal.claim() else { return nil }
                        index = next
                    }
                }
            }

            var lowest: (index: Int, failure: Failure)? = nil
            for await case let failure? in group {
                group.cancelAll()
                if lowest.map({ failure.index < $0.index }) ?? true {
                    lowest = failure
                }
            }
            return lowest
        }
    }
}

/// The state of a concurrent `traverseAsync`: the next index to claim, and one result slot per
/// element.
///
/// `@unchecked Sendable`: each slot is written once, by one task, and read only after every
/// child task has finished.
@usableFromInline
final class ConcurrentTraversal<Success>: @unchecked Sendable {
    @usableFromInline let count: Int
    @usableFromInline let next: Atomic<Int>
    @usableFromInline let slots: UnsafeMutablePointer<Success?>

    /// - Parameter claimed: How many first indices the workers start on. `claim()` starts
    ///   after them.
    @inlinable
    init(count: Int, claimed: Int) {
        self.count = count
        next = Atomic(claimed)
        slots = .allocate(capacity: count)
        slots.initialize(repeating: nil, count: count)
    }

    deinit {
        slots.deinitialize(count: count)
        slots.deallocate()
    }

    /// Claims the next free index. Returns nil when all are claimed or the traversal stopped.
    @inlinable
    func claim() -> Int? {
        let index = next.wrappingAdd(1, ordering: .relaxed).oldValue
        return index < count ? index : nil
    }

    /// Makes every later `claim()` return nil.
    @inlinable
    func stop() {
        next.store(count, ordering: .relaxed)
    }

    @inlinable
    func store(_ value: Success, at index: Int) {
        slots[index] = value
    }

    /// Moves all results out, in index order. Call it only after every worker finished and
    /// none of them stopped the traversal.
    @inlinable
    func values() -> [Success] {
        Array(unsafeUninitializedCapacity: count) { buffer, initializedCount in
            for index in 0..<count {
                // A traversal that never stopped stored every slot.
                buffer.initializeElement(at: index, to: (slots + index).move()!)
                (slots + index).initialize(to: nil)
            }
            initializedCount = count
        }
    }
}
