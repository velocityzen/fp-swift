import Synchronization

// Everything here is `@inlinable` so callers specialize it for their element
// and result types: unspecialized, every element goes through generic value
// witnesses, and async ones heap-allocate their generic temporaries.

public extension Array {
    /// Traverses the array, applying a transform function to each element.
    /// Returns a Result containing an array of transformed values.
    ///
    /// - Parameter transform: A closure that transforms each element
    /// - Returns: A Result containing an array of transformed values (never fails)
    @inlinable
    func traverse<Success>(
        _ transform: (Element) -> Success
    ) -> Result<[Success], Never> {
        var results: [Success] = []
        results.reserveCapacity(count)

        for element in self {
            results.append(transform(element))
        }

        return .success(results)
    }

    /// Traverses the array, applying a transform function that returns a Result.
    /// If all transformations succeed, returns a Result containing an array of successes.
    /// If any transformation fails, returns the first failure encountered.
    ///
    /// - Parameter transform: A closure that transforms each element into a Result
    /// - Returns: A Result containing either an array of all successes or the first failure
    @inlinable
    func traverse<Success, Failure: Error>(
        _ transform: (Element) -> Result<Success, Failure>
    ) -> Result<[Success], Failure> {
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

    /// Asynchronously traverses the array, applying a transform function to each element.
    /// Returns a Result containing an array of transformed values.
    ///
    /// Transforms run sequentially — each element awaits the previous one.
    /// Pass `concurrency:` to run them in parallel.
    ///
    /// - Parameter transform: An async closure that transforms each element
    /// - Returns: A Result containing an array of transformed values (never fails)
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

    /// Asynchronously traverses the array, applying a transform function that returns a Result.
    /// If all transformations succeed, returns a Result containing an array of successes.
    /// If any transformation fails, returns the first failure encountered.
    ///
    /// Transforms run sequentially — each element awaits the previous one, and
    /// elements after a failure never run. Pass `concurrency:` to run them in
    /// parallel.
    ///
    /// - Parameter transform: An async closure that transforms each element into a Result
    /// - Returns: A Result containing either an array of all successes or the first failure
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

    /// Asynchronously traverses the array with up to `concurrency` transforms
    /// in flight at once. Results keep source order.
    ///
    /// - Parameters:
    ///   - concurrency: Maximum number of transforms in flight at once; must
    ///     be at least 1. `concurrency: 1` is equivalent to the sequential
    ///     variant.
    ///   - transform: An async closure that transforms each element
    /// - Returns: A Result containing an array of transformed values in
    ///   source order (never fails)
    @inlinable
    func traverseAsync<Success: Sendable>(
        concurrency: Int,
        _ transform: @concurrent @Sendable @escaping (Element) async -> Success
    ) async -> Result<[Success], Never> where Element: Sendable {
        await traverseAsync(concurrency: concurrency) { element -> Result<Success, Never> in
            .success(await transform(element))
        }
    }

    /// Asynchronously traverses the array with up to `concurrency` transforms
    /// in flight at once. Results keep source order.
    ///
    /// Fails with the failure of the lowest-index failing element. Once a
    /// failure is observed, no further transforms start and in-flight ones
    /// are cancelled cooperatively — elements after a failure may have
    /// started (and been cancelled) or never run at all.
    ///
    /// For streaming results, endless sources, or failures kept in position,
    /// use `mapAsyncKeepOrder` on an async sequence instead.
    ///
    /// - Parameters:
    ///   - concurrency: Maximum number of transforms in flight at once; must
    ///     be at least 1. `concurrency: 1` is equivalent to the sequential
    ///     variant.
    ///   - transform: An async closure that transforms each element into a Result
    /// - Returns: A Result containing either an array of all successes in
    ///   source order, or the lowest-index failure
    @inlinable
    func traverseAsync<Success: Sendable, Failure: Error>(
        concurrency: Int,
        _ transform: @concurrent @Sendable @escaping (Element) async -> Result<Success, Failure>
    ) async -> Result<[Success], Failure> where Element: Sendable {
        precondition(concurrency >= 1, "concurrency must be at least 1")
        // With one transform in flight at a time there is nothing to run in
        // parallel, so loop in place rather than start a child task.
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

    /// Separates an array of Results into success and failure arrays.
    ///
    /// - Returns: A tuple containing all success values and all failure values
    @inlinable
    func separate<Success, Failure>() -> (successes: [Success], failures: [Failure])
    where Element == Result<Success, Failure> {
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

    /// Returns just the success values from an array of `Result`.
    ///
    /// ```swift
    /// let results: [Result<Int, MyError>] = [.success(1), .failure(.bad), .success(2)]
    /// results.successes()  // [1, 2]
    /// ```
    @inlinable
    func successes<Success, Failure>() -> [Success]
    where Element == Result<Success, Failure> {
        var values: [Success] = []
        values.reserveCapacity(count)
        for result in self {
            if case .success(let value) = result {
                values.append(value)
            }
        }
        return values
    }

    /// Returns just the failure errors from an array of `Result`.
    ///
    /// ```swift
    /// let results: [Result<Int, MyError>] = [.success(1), .failure(.bad), .success(2)]
    /// results.failures()  // [.bad]
    /// ```
    @inlinable
    func failures<Success, Failure>() -> [Failure]
    where Element == Result<Success, Failure> {
        var errors: [Failure] = []
        for result in self {
            if case .failure(let error) = result {
                errors.append(error)
            }
        }
        return errors
    }
}

extension Array where Element: Sendable {
    /// Runs a child task per element, each handing its result back to the
    /// group: with every element in flight at once there is nothing to
    /// schedule, so children share no state and capture only their element.
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

    /// Runs a fixed pool of workers rather than a child task per element,
    /// since a child task costs far more than most transforms: each worker
    /// starts on its own element, then claims the next unclaimed one until
    /// none are left. Starting every worker up front keeps the first
    /// `workers` elements running even if one fails at once.
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

/// The state of a concurrent `traverseAsync`: the next index for a worker
/// to claim, and a slot per element for its result.
///
/// `@unchecked Sendable`: each slot is written once, by the one task that
/// ran its element or received its result, and read only after every
/// child task has finished.
@usableFromInline
final class ConcurrentTraversal<Success>: @unchecked Sendable {
    @usableFromInline let count: Int
    @usableFromInline let next: Atomic<Int>
    @usableFromInline let slots: UnsafeMutablePointer<Success?>

    /// - Parameter claimed: How many leading indices the workers start on,
    ///   so `claim()` begins after them.
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

    /// Claims the next unclaimed index, or returns nil when every index is
    /// claimed or the traversal stopped.
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

    /// Moves every result out, in index order. Call only after every worker
    /// has finished and stored its results without stopping.
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
