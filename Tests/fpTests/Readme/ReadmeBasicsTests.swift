// Examples from "Quick start", "Pipe operators", "Working with results",
// "Recovering from failures", "Optionals" and "Do notation" in README.md.
// The DocC articles are made from README.md. Keep the code here the same.

import FP
import Testing

private enum AppError: Error, Equatable {
    case notANumber(String)
    case notFound
}

private struct User: Equatable {
    let id: Int
    let name: String
    var discount = 1.0

    static let guest = User(id: 0, name: "guest")
}

private struct Item: Equatable {
    let id: Int
    let price: Double
}

private struct Order: Equatable {
    let user: User
    let item: Item
    let price: Double
}

private struct Config: Equatable {
    let port: Int
}

private final class Cache {
    var saved: [User] = []

    func save(_ user: User) {
        saved.append(user)
    }
}

private func parse(_ text: String) -> Result<Int, AppError> {
    .fromOptional(Int(text), error: .notANumber(text))
}

private func fetchUser(id: Int) -> Result<User, AppError> {
    id == 1 ? .success(User(id: 1, name: "Ann", discount: 0.5)) : .failure(.notFound)
}

private func fetchCachedUser(id: Int) -> Result<User, AppError> {
    .success(User(id: id, name: "cached"))
}

private func fetchItem(id: Int) -> Result<Item, AppError> {
    id == 7 ? .success(Item(id: 7, price: 10)) : .failure(.notFound)
}

private func loadConfig() -> Result<Config, AppError> {
    .success(Config(port: 8080))
}

private func double(_ n: Int) -> Int { n * 2 }
private func label(_ n: Int) -> String { "#\(n)" }
private func add(_ a: Int, _ b: Int) -> Int { a + b }

private func normalize(_ id: String) -> String { id.lowercased() }
private func loadUser(_ id: String) async -> User { User(id: 1, name: id) }
private func render(_ user: User) -> String { "<h1>\(user.name)</h1>" }

private func order(userID: Int, itemID: Int) -> Result<Order, AppError> {
    ResultDo<AppError>()
        .bind { fetchUser(id: userID) }
        .bind { user in fetchItem(id: itemID) }
        .let { user, item in item.price * user.discount }
        .map { user, item, price in
            Order(user: user, item: item, price: price)
        }
}

@Suite("README basics")
struct ReadmeBasicsTests {
    @Test
    func quickStart() {
        let doubled = parse("21")
            .tap { n in print("parsed", n) }  // prints "parsed 21"
            .map { n in n * 2 }
            .getOrElse(0)  // 42

        #expect(doubled == 42)
        #expect(parse("x").map { n in n * 2 }.getOrElse(0) == 0)
    }

    @Test
    func pipeOperators() async {
        let text = 5 |> double |> label  // "#10"
        #expect(text == "#10")

        let sum = 2 |>> (add, 10)  // add(10, 2), so 12
        #expect(sum == 12)

        let id = "ANN"
        let page =
            await id
            |> normalize  // sync
            |> loadUser  // async
            |> render  // sync
        #expect(page == "<h1>ann</h1>")
    }

    @Test
    func pipePrecedence() {
        let x = 3
        let first = 1 + 2 |> double  // double(3), not 1 + double(2)
        let second = x |> double == 6  // (x |> double) == 6

        #expect(first == 6)
        #expect(second)
    }

    @Test
    func workingWithResults() {
        let cache = Cache()
        var logged: [AppError] = []
        func log(_ error: AppError) { logged.append(error) }

        let greeting = fetchUser(id: 1)
            .tap { user in cache.save(user) }
            .tapError { error in log(error) }
            .match(
                { user in "Hello, \(user.name)" },
                { error in "Error: \(error)" }
            )

        #expect(greeting == "Hello, Ann")
        #expect(cache.saved.map(\.name) == ["Ann"])
        #expect(logged.isEmpty)
    }

    @Test
    func recoveringFromFailures() {
        let user = fetchUser(id: 1)
            .alt { fetchCachedUser(id: 1) }
            .getOrElse(.guest)
        #expect(user.name == "Ann")

        let missing = fetchUser(id: 2)
            .alt { fetchCachedUser(id: 2) }
            .getOrElse(.guest)
        #expect(missing.name == "cached")

        // On a failure, getOrExit ends the process, so only the success is run here.
        let config = loadConfig().getOrExit()
        #expect(config == Config(port: 8080))
    }

    @Test
    func optionals() {
        let cachedUser: User? = nil
        let result: Result<User, AppError> =
            .fromOptional(cachedUser, error: .notFound)
        #expect(result == .failure(.notFound))

        let name: String? = nil
        let nickname: String? = "Bo"

        #expect(name.match({ n in "Hi, \(n)" }, "Hi, guest") == "Hi, guest")
        #expect(name.orElse(nickname) == "Bo")
        #expect(name.getOrElse("guest") == "guest")
    }

    @Test
    func doNotation() {
        let user = User(id: 1, name: "Ann", discount: 0.5)
        let item = Item(id: 7, price: 10)

        #expect(order(userID: 1, itemID: 7) == .success(Order(user: user, item: item, price: 5)))
        #expect(order(userID: 1, itemID: 8) == .failure(.notFound))
    }
}
