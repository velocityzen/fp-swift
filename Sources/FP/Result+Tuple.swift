// MARK: - Combine a tuple of Results into a Result of a tuple (sync)

// MARK: Arity 2

/// Combines multiple Results into a single Result containing a tuple of all success values.
///
/// Returns the first failure if any Result fails. Supports 2 to 10 arguments.
@inlinable
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

@inlinable
public func flatten<A, B, C, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>
) -> Result<(A, B, C), E> {
    flatten(a, b).flatMap { (a, b) in c.map { c in (a, b, c) } }
}

@inlinable
public func flatten<A, B, C, D, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>
) -> Result<(A, B, C, D), E> {
    flatten(a, b, c).flatMap { (a, b, c) in d.map { d in (a, b, c, d) } }
}

@inlinable
public func flatten<A, B, C, D, F, E: Error>(
    _ a: Result<A, E>,
    _ b: Result<B, E>,
    _ c: Result<C, E>,
    _ d: Result<D, E>,
    _ f: Result<F, E>
) -> Result<(A, B, C, D, F), E> {
    flatten(a, b, c, d).flatMap { (a, b, c, d) in f.map { f in (a, b, c, d, f) } }
}

@inlinable
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

@inlinable
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

@inlinable
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

@inlinable
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

@inlinable
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
@inlinable
public func withAll<A: Sendable, B: Sendable, E: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>
) async -> Result<(A, B), E> {
    let gate = Gate<E?>(parties: 2)
    async let ra = gate.success(of: await a())
    async let rb = gate.success(of: await b())
    if let failure = await gate.wait() {
        // Leaving the scope cancels the operations still running
        // and waits for them to stop.
        return .failure(failure)
    }
    // The gate opened without a failure, so every operation succeeded.
    return .success((await ra!, await rb!))
}

// MARK: Arity 3

@inlinable
public func withAll<A: Sendable, B: Sendable, C: Sendable, E: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<C, E>
) async -> Result<(A, B, C), E> {
    let gate = Gate<E?>(parties: 3)
    async let ra = gate.success(of: await a())
    async let rb = gate.success(of: await b())
    async let rc = gate.success(of: await c())
    if let failure = await gate.wait() {
        // Leaving the scope cancels the operations still running
        // and waits for them to stop.
        return .failure(failure)
    }
    // The gate opened without a failure, so every operation succeeded.
    return .success((await ra!, await rb!, await rc!))
}

// MARK: Arity 4

@inlinable
public func withAll<A: Sendable, B: Sendable, C: Sendable, D: Sendable, E: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<D, E>
) async -> Result<(A, B, C, D), E> {
    let gate = Gate<E?>(parties: 4)
    async let ra = gate.success(of: await a())
    async let rb = gate.success(of: await b())
    async let rc = gate.success(of: await c())
    async let rd = gate.success(of: await d())
    if let failure = await gate.wait() {
        // Leaving the scope cancels the operations still running
        // and waits for them to stop.
        return .failure(failure)
    }
    // The gate opened without a failure, so every operation succeeded.
    return .success((await ra!, await rb!, await rc!, await rd!))
}

// MARK: Arity 5

@inlinable
public func withAll<A: Sendable, B: Sendable, C: Sendable, D: Sendable, F: Sendable, E: Error>(
    _ a: @concurrent @Sendable @autoclosure @escaping () async -> Result<A, E>,
    _ b: @concurrent @Sendable @autoclosure @escaping () async -> Result<B, E>,
    _ c: @concurrent @Sendable @autoclosure @escaping () async -> Result<C, E>,
    _ d: @concurrent @Sendable @autoclosure @escaping () async -> Result<D, E>,
    _ f: @concurrent @Sendable @autoclosure @escaping () async -> Result<F, E>
) async -> Result<(A, B, C, D, F), E> {
    let gate = Gate<E?>(parties: 5)
    async let ra = gate.success(of: await a())
    async let rb = gate.success(of: await b())
    async let rc = gate.success(of: await c())
    async let rd = gate.success(of: await d())
    async let rf = gate.success(of: await f())
    if let failure = await gate.wait() {
        // Leaving the scope cancels the operations still running
        // and waits for them to stop.
        return .failure(failure)
    }
    // The gate opened without a failure, so every operation succeeded.
    return .success((await ra!, await rb!, await rc!, await rd!, await rf!))
}

// MARK: Arity 6

@inlinable
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
    let gate = Gate<E?>(parties: 6)
    async let ra = gate.success(of: await a())
    async let rb = gate.success(of: await b())
    async let rc = gate.success(of: await c())
    async let rd = gate.success(of: await d())
    async let rf = gate.success(of: await f())
    async let rg = gate.success(of: await g())
    if let failure = await gate.wait() {
        // Leaving the scope cancels the operations still running
        // and waits for them to stop.
        return .failure(failure)
    }
    // The gate opened without a failure, so every operation succeeded.
    return .success((await ra!, await rb!, await rc!, await rd!, await rf!, await rg!))
}

// MARK: Arity 7

@inlinable
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
    let gate = Gate<E?>(parties: 7)
    async let ra = gate.success(of: await a())
    async let rb = gate.success(of: await b())
    async let rc = gate.success(of: await c())
    async let rd = gate.success(of: await d())
    async let rf = gate.success(of: await f())
    async let rg = gate.success(of: await g())
    async let rh = gate.success(of: await h())
    if let failure = await gate.wait() {
        // Leaving the scope cancels the operations still running
        // and waits for them to stop.
        return .failure(failure)
    }
    // The gate opened without a failure, so every operation succeeded.
    return .success((await ra!, await rb!, await rc!, await rd!, await rf!, await rg!, await rh!))
}

// MARK: Arity 8

@inlinable
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
    let gate = Gate<E?>(parties: 8)
    async let ra = gate.success(of: await a())
    async let rb = gate.success(of: await b())
    async let rc = gate.success(of: await c())
    async let rd = gate.success(of: await d())
    async let rf = gate.success(of: await f())
    async let rg = gate.success(of: await g())
    async let rh = gate.success(of: await h())
    async let ri = gate.success(of: await i())
    if let failure = await gate.wait() {
        // Leaving the scope cancels the operations still running
        // and waits for them to stop.
        return .failure(failure)
    }
    // The gate opened without a failure, so every operation succeeded.
    return .success(
        (
            await ra!, await rb!, await rc!, await rd!, await rf!, await rg!, await rh!, await ri!
        )
    )
}

// MARK: Arity 9

@inlinable
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
    let gate = Gate<E?>(parties: 9)
    async let ra = gate.success(of: await a())
    async let rb = gate.success(of: await b())
    async let rc = gate.success(of: await c())
    async let rd = gate.success(of: await d())
    async let rf = gate.success(of: await f())
    async let rg = gate.success(of: await g())
    async let rh = gate.success(of: await h())
    async let ri = gate.success(of: await i())
    async let rj = gate.success(of: await j())
    if let failure = await gate.wait() {
        // Leaving the scope cancels the operations still running
        // and waits for them to stop.
        return .failure(failure)
    }
    // The gate opened without a failure, so every operation succeeded.
    return .success(
        (
            await ra!, await rb!, await rc!, await rd!, await rf!, await rg!, await rh!, await ri!,
            await rj!
        )
    )
}

// MARK: Arity 10

@inlinable
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
    let gate = Gate<E?>(parties: 10)
    async let ra = gate.success(of: await a())
    async let rb = gate.success(of: await b())
    async let rc = gate.success(of: await c())
    async let rd = gate.success(of: await d())
    async let rf = gate.success(of: await f())
    async let rg = gate.success(of: await g())
    async let rh = gate.success(of: await h())
    async let ri = gate.success(of: await i())
    async let rj = gate.success(of: await j())
    async let rk = gate.success(of: await k())
    if let failure = await gate.wait() {
        // Leaving the scope cancels the operations still running
        // and waits for them to stop.
        return .failure(failure)
    }
    // The gate opened without a failure, so every operation succeeded.
    return .success(
        (
            await ra!, await rb!, await rc!, await rd!, await rf!, await rg!, await rh!, await ri!,
            await rj!, await rk!
        )
    )
}
