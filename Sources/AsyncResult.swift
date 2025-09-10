public struct AsyncResult<Success, Failure: Error> {
    let run: () async -> Result<Success, Failure>

    init(_ run: @escaping () async -> Result<Success, Failure>) {
        self.run = run
    }

    public static func fromResult(_ result: Result<Success, Failure>) -> AsyncResult {
        AsyncResult { result }
    }

    public static func success(_ value: Success) -> AsyncResult {
        AsyncResult { .success(value) }
    }

    public static func fail(_ error: Failure) -> AsyncResult {
        AsyncResult { .failure(error) }
    }

    public static func of(_ value: Success) -> AsyncResult {
        AsyncResult { .success(value) }
    }

    func callAsFunction() async -> Result<Success, Failure> {
        await run()
    }
}

/// Functor
extension AsyncResult {
    func map<T>(_ transform: @escaping (Success) -> T) -> AsyncResult<T, Failure> {
        AsyncResult<T, Failure> {
            await self().map(transform)
        }
    }
}

/// Monad
extension AsyncResult {
    func flatMap<T>(_ transform: @escaping (Success) -> AsyncResult<T, Failure>) -> AsyncResult<
        T, Failure
    > {
        AsyncResult<T, Failure> {
            let result = await self()
            switch result {
            case .success(let value):
                return await transform(value)()
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    func flatMap<T>(_ transform: @escaping (Success) -> Result<T, Failure>) -> AsyncResult<
        T, Failure
    > {
        AsyncResult<T, Failure> {
            let result = await self()
            switch result {
            case .success(let value):
                return transform(value)
            case .failure(let error):
                return .failure(error)
            }
        }
    }
}

// MARK: Error handling

extension AsyncResult {
    public func orElse(
        _ alternative: @escaping () -> AsyncResult<Success, Failure>
    ) -> AsyncResult<Success, Failure> {
        AsyncResult {
            let result = await self()
            switch result {
            case .success:
                return result
            case .failure(_):
                return await alternative()()
            }
        }
    }

    public func orElse(
        if matches: @escaping (Failure) -> Bool,
        _ alternative: @escaping () -> AsyncResult<Success, Failure>
    ) -> AsyncResult<Success, Failure> {
        AsyncResult {
            let result = await self()
            switch result {
            case .success:
                return result
            case .failure(let error):
                if matches(error) {
                    return await alternative()()
                } else {
                    return .failure(error)
                }
            }
        }
    }
}

// MARK: Operators

public func |> <A, Z, E>(lhs: AsyncResult<A, E>, rhs: @escaping (A) -> Z) -> AsyncResult<Z, E> {
    lhs.map(rhs)
}

public func |> <A, Z, Error>(
    lhs: AsyncResult<A, Error>, rhs: @escaping (A) -> AsyncResult<Z, Error>
) -> AsyncResult<Z, Error> {
    lhs.flatMap(rhs)
}

public func |> <A, Z, E>(lhs: AsyncResult<A, E>, rhs: @escaping (A) async -> Result<Z, E>)
    -> AsyncResult<Z, E>
{
    AsyncResult<Z, E> {
        let result = await lhs()
        switch result {
        case .success(let value):
            return await rhs(value)
        case .failure(let error):
            return .failure(error)
        }
    }
}

public func |> <A, Z, E>(lhs: AsyncResult<A, E>, rhs: @escaping (A) -> Result<Z, E>) -> AsyncResult<
    Z, E
> {
    lhs.flatMap(rhs)
}
