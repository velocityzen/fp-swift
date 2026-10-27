// MARK: - Combine a tuple of Results into a Result of a tuple (sync)

// MARK: Arity 2

/// Combines multiple Results into a single Result containing a tuple of all success values.
///
/// Returns the first failure if any Result fails. Supports 2 to 10 arguments.
public func flatten<A, B, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>
) -> Result<(A, B), E> {
    switch (a, b) {
        case (.success(let a), .success(let b)):
            return .success((a, b))

        case (.failure(let e), _), (_, .failure(let e)):
            return .failure(e)
    }
}

public func flatten<A, B, C, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>
) -> Result<(A, B, C), E> {
    flatten(a, b).flatMap { (a, b) in c.map { c in (a, b, c) } }
}

public func flatten<A, B, C, D, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>
) -> Result<(A, B, C, D), E> {
    flatten(a, b, c).flatMap { (a, b, c) in d.map { d in (a, b, c, d) } }
}

public func flatten<A, B, C, D, F, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>
) -> Result<(A, B, C, D, F), E> {
    flatten(a, b, c, d).flatMap { (a, b, c, d) in f.map { f in (a, b, c, d, f) } }
}

public func flatten<A, B, C, D, F, G, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>,
    _ g: Result<G, E>
) -> Result<(A, B, C, D, F, G), E> {
    flatten(a, b, c, d, f).flatMap { (a, b, c, d, f) in g.map { g in (a, b, c, d, f, g) } }
}

public func flatten<A, B, C, D, F, G, H, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>,
    _ g: Result<G, E>,
    _ h: Result<H, E>
) -> Result<(A, B, C, D, F, G, H), E> {
    flatten(a, b, c, d, f, g).flatMap { (a, b, c, d, f, g) in h.map { h in (a, b, c, d, f, g, h) } }
}

public func flatten<A, B, C, D, F, G, H, I, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>,
    _ g: Result<G, E>,
    _ h: Result<H, E>,
    _ i: Result<I, E>
) -> Result<(A, B, C, D, F, G, H, I), E> {
    flatten(a, b, c, d, f, g, h).flatMap { (a, b, c, d, f, g, h) in
        i.map { i in (a, b, c, d, f, g, h, i) }
    }
}

public func flatten<A, B, C, D, F, G, H, I, J, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>,
    _ g: Result<G, E>,
    _ h: Result<H, E>,
    _ i: Result<I, E>,
    _ j: Result<J, E>
) -> Result<(A, B, C, D, F, G, H, I, J), E> {
    flatten(a, b, c, d, f, g, h, i).flatMap { (a, b, c, d, f, g, h, i) in
        j.map { j in (a, b, c, d, f, g, h, i, j) }
    }
}

public func flatten<A, B, C, D, F, G, H, I, J, K, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>,
    _ g: Result<G, E>,
    _ h: Result<H, E>,
    _ i: Result<I, E>,
    _ j: Result<J, E>,
    _ k: Result<K, E>
) -> Result<(A, B, C, D, F, G, H, I, J, K), E> {
    flatten(a, b, c, d, f, g, h, i, j).flatMap { (a, b, c, d, f, g, h, i, j) in
        k.map { k in (a, b, c, d, f, g, h, i, j, k) }
    }
}

// MARK: - Combine async Results in parallel

// MARK: Arity 2

/// Runs multiple async Result-producing operations in parallel and combines their success values into a tuple.
///
/// Returns the first failure to arrive and cancels the operations still
/// running; cancellation is cooperative, so this waits until they stop.
/// Supports 2 to 10 arguments.
public func withAll<A: Sendable, B: Sendable, E: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>
) async -> Result<(A, B), E> {
    await collectAll([
        { await a().map { $0 } },
        { await b().map { $0 } },
    ]).map { values in
        // `collectAll` keeps argument order, so each cast matches its type.
        (values[0] as! A, values[1] as! B)
    }
}

// MARK: Arity 3

public func withAll<A: Sendable, B: Sendable, C: Sendable, E: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<C, E>
) async -> Result<(A, B, C), E> {
    await collectAll([
        { await a().map { $0 } },
        { await b().map { $0 } },
        { await c().map { $0 } },
    ]).map { values in
        (values[0] as! A, values[1] as! B, values[2] as! C)
    }
}

// MARK: Arity 4

public func withAll<A: Sendable, B: Sendable, C: Sendable, D: Sendable, E: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<D, E>
) async -> Result<(A, B, C, D), E> {
    await collectAll([
        { await a().map { $0 } },
        { await b().map { $0 } },
        { await c().map { $0 } },
        { await d().map { $0 } },
    ]).map { values in
        (values[0] as! A, values[1] as! B, values[2] as! C, values[3] as! D)
    }
}

// MARK: Arity 5

public func withAll<A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, E: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<F, E>
) async -> Result<(A, B, C, D, F), E> {
    await collectAll([
        { await a().map { $0 } },
        { await b().map { $0 } },
        { await c().map { $0 } },
        { await d().map { $0 } },
        { await f().map { $0 } },
    ]).map { values in
        (values[0] as! A, values[1] as! B, values[2] as! C, values[3] as! D, values[4] as! F)
    }
}

// MARK: Arity 6

public func withAll<
    A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, G: Sendable, E: Error
>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<F, E>,
    _ g: @concurrent @Sendable @autoclosure @escaping () async -> Result<G, E>
) async -> Result<(A, B, C, D, F, G), E> {
    await collectAll([
        { await a().map { $0 } },
        { await b().map { $0 } },
        { await c().map { $0 } },
        { await d().map { $0 } },
        { await f().map { $0 } },
        { await g().map { $0 } },
    ]).map { values in
        (
            values[0] as! A, values[1] as! B, values[2] as! C, values[3] as! D, values[4] as! F,
            values[5] as! G
        )
    }
}

// MARK: Arity 7

public func withAll<
    A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, G: Sendable, H: Sendable,
    E: Error
>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<F, E>,
    _ g: @concurrent @Sendable @autoclosure @escaping () async -> Result<G, E>,
    _ h: @concurrent @Sendable @autoclosure @escaping () async -> Result<H, E>
) async -> Result<(A, B, C, D, F, G, H), E> {
    await collectAll([
        { await a().map { $0 } },
        { await b().map { $0 } },
        { await c().map { $0 } },
        { await d().map { $0 } },
        { await f().map { $0 } },
        { await g().map { $0 } },
        { await h().map { $0 } },
    ]).map { values in
        (
            values[0] as! A, values[1] as! B, values[2] as! C, values[3] as! D, values[4] as! F,
            values[5] as! G, values[6] as! H
        )
    }
}

// MARK: Arity 8

public func withAll<
    A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, G: Sendable, H: Sendable,
    I: Sendable, E: Error
>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<F, E>,
    _ g: @concurrent @Sendable @autoclosure @escaping () async -> Result<G, E>,
    _ h: @concurrent @Sendable @autoclosure @escaping () async -> Result<H, E>,
    _ i: @concurrent @Sendable @autoclosure @escaping () async -> Result<I, E>
) async -> Result<(A, B, C, D, F, G, H, I), E> {
    await collectAll([
        { await a().map { $0 } },
        { await b().map { $0 } },
        { await c().map { $0 } },
        { await d().map { $0 } },
        { await f().map { $0 } },
        { await g().map { $0 } },
        { await h().map { $0 } },
        { await i().map { $0 } },
    ]).map { values in
        (
            values[0] as! A, values[1] as! B, values[2] as! C, values[3] as! D, values[4] as! F,
            values[5] as! G, values[6] as! H, values[7] as! I
        )
    }
}

// MARK: Arity 9

public func withAll<
    A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, G: Sendable, H: Sendable,
    I: Sendable, J: Sendable, E: Error
>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<F, E>,
    _ g: @concurrent @Sendable @autoclosure @escaping () async -> Result<G, E>,
    _ h: @concurrent @Sendable @autoclosure @escaping () async -> Result<H, E>,
    _ i: @concurrent @Sendable @autoclosure @escaping () async -> Result<I, E>,
    _ j: @concurrent @Sendable @autoclosure @escaping () async -> Result<J, E>
) async -> Result<(A, B, C, D, F, G, H, I, J), E> {
    await collectAll([
        { await a().map { $0 } },
        { await b().map { $0 } },
        { await c().map { $0 } },
        { await d().map { $0 } },
        { await f().map { $0 } },
        { await g().map { $0 } },
        { await h().map { $0 } },
        { await i().map { $0 } },
        { await j().map { $0 } },
    ]).map { values in
        (
            values[0] as! A, values[1] as! B, values[2] as! C, values[3] as! D, values[4] as! F,
            values[5] as! G, values[6] as! H, values[7] as! I, values[8] as! J
        )
    }
}

// MARK: Arity 10

public func withAll<
    A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, G: Sendable, H: Sendable,
    I: Sendable, J: Sendable, K: Sendable, E: Error
>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<F, E>,
    _ g: @concurrent @Sendable @autoclosure @escaping () async -> Result<G, E>,
    _ h: @concurrent @Sendable @autoclosure @escaping () async -> Result<H, E>,
    _ i: @concurrent @Sendable @autoclosure @escaping () async -> Result<I, E>,
    _ j: @concurrent @Sendable @autoclosure @escaping () async -> Result<J, E>,
    _ k: @concurrent @Sendable @autoclosure @escaping () async -> Result<K, E>
) async -> Result<(A, B, C, D, F, G, H, I, J, K), E> {
    await collectAll([
        { await a().map { $0 } },
        { await b().map { $0 } },
        { await c().map { $0 } },
        { await d().map { $0 } },
        { await f().map { $0 } },
        { await g().map { $0 } },
        { await h().map { $0 } },
        { await i().map { $0 } },
        { await j().map { $0 } },
        { await k().map { $0 } },
    ]).map { values in
        (
            values[0] as! A, values[1] as! B, values[2] as! C, values[3] as! D, values[4] as! F,
            values[5] as! G, values[6] as! H, values[7] as! I, values[8] as! J, values[9] as! K
        )
    }
}

/// Runs `operations` in parallel and collects their successes in argument
/// order. The first failure to arrive cancels the operations still running
/// and is returned once they have stopped.
private func collectAll<E: Error>(
    _ operations: [@concurrent @Sendable () async -> Result<any Sendable, E>]
) async -> Result<[any Sendable], E> {
    await withTaskGroup(of: (index: Int, result: Result<any Sendable, E>).self) { group in
        for (index, operation) in operations.enumerated() {
            group.addTask { (index, await operation()) }
        }

        var values = [(any Sendable)?](repeating: nil, count: operations.count)
        for await completed in group {
            switch completed.result {
                case .success(let value):
                    values[completed.index] = value
                case .failure(let error):
                    group.cancelAll()
                    return .failure(error)
            }
        }
        return .success(values.compactMap { $0 })
    }
}
