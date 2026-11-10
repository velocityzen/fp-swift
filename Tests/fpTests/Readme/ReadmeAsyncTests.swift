// Examples from "Async results", "Arrays", "Combining results", "Racing and
// timeouts", "Async sequences of results" and "Concurrent mapping" in README.md.
// The DocC articles are made from README.md. Keep the code here the same.

import FP
import Synchronization
import Testing

private enum AppError: Error, Equatable {
    case notFound
    case timeout
}

private struct User: Equatable, Sendable {
    let id: Int
}

private struct Profile: Equatable, Sendable {
    let user: User
}

private struct Settings: Equatable, Sendable {
    let theme: String
}

private struct Message: Equatable, Sendable {
    let text: String
}

private struct LoadError: Error {}

private actor Analytics {
    var tracked: [User] = []

    func track(_ user: User) {
        tracked.append(user)
    }
}

private struct Downloader: Sendable {
    func fetch(_ ref: Int) async -> String {
        // Later elements finish first, so the order is really kept.
        try? await Task.sleep(for: .milliseconds(10 - ref))
        return "image \(ref)"
    }
}

private struct Renderer: Sendable {
    func thumbnail(for photo: Int) async -> String { "thumb \(photo)" }
}

/// Records values from `@Sendable` closures.
private final class Recorder<Value: Sendable>: Sendable {
    private let values = Mutex<[Value]>([])

    func callAsFunction(_ value: Value) {
        values.withLock { $0.append(value) }
    }

    var all: [Value] { values.withLock { $0 } }
}

private func fetchUser(id: Int) -> Result<User, AppError> {
    id > 0 ? .success(User(id: id)) : .failure(.notFound)
}

private func loadUser(id: Int) async -> Result<User, AppError> {
    fetchUser(id: id)
}

private func loadProfile(of user: User) async -> Result<Profile, AppError> {
    .success(Profile(user: user))
}

private func loadProfile(id: Int) async -> Result<Profile, AppError> {
    .success(Profile(user: User(id: id)))
}

private func loadData() async throws -> String {
    throw LoadError()
}

private func fetchSettings(id: Int) -> Result<Settings, AppError> {
    .success(Settings(theme: "dark"))
}

private func loadMessages(id: Int) async -> Result<[Message], AppError> {
    .success([Message(text: "hi")])
}

private func download(from url: String) async -> Result<String, AppError> {
    url == "backup" ? .success("data from backup") : .failure(.timeout)
}

private func loadName(_ id: Int) async -> String { "name \(id)" }

private func stream<T: Sendable>(_ values: [T]) -> AsyncStream<T> {
    AsyncStream { continuation in
        for value in values { continuation.yield(value) }
        continuation.finish()
    }
}

@Suite("README async")
struct ReadmeAsyncTests {
    private let analytics = Analytics()

    private func profile(id: Int) async -> Result<Profile, AppError> {
        await fetchUser(id: id)
            .tapAsync { user in await analytics.track(user) }
            .flatMapAsync { user in await loadProfile(of: user) }
    }

    @Test
    func asyncResults() async {
        #expect(await profile(id: 1) == .success(Profile(user: User(id: 1))))
        #expect(await analytics.tracked == [User(id: 1)])

        let data = await Result.fromAsync {
            try await loadData()
        }
        #expect(throws: LoadError.self) { try data.get() }
    }

    @Test
    func arrays() async {
        let ids = [1, 2, 3]

        let users = ids.traverse { id in fetchUser(id: id) }
        // .success([User]), or the first failure

        let loaded = await ids.traverseAsync(concurrency: 4) { id in
            await loadUser(id: id)
        }

        #expect(users == .success([User(id: 1), User(id: 2), User(id: 3)]))
        #expect(loaded == users)
        #expect([1, 0, 2].traverse { id in fetchUser(id: id) } == .failure(.notFound))
    }

    @Test
    func combiningResults() async {
        let both = flatten(fetchUser(id: 1), fetchSettings(id: 1))
        // Result<(User, Settings), AppError>

        let home = await withAll(
            await loadUser(id: 1),
            await loadMessages(id: 1)
        )
        // Result<(User, [Message]), AppError>

        #expect(both.map { user, settings in settings.theme } == .success("dark"))
        #expect(home.map { user, messages in messages.count } == .success(1))
    }

    @Test
    func racingAndTimeouts() async {
        let primary = "primary"
        let backup = "backup"

        let data = await withAny(
            await download(from: primary),
            await download(from: backup)
        )
        #expect(data == .success("data from backup"))

        let profile = await withTimeout(.seconds(5), failingWith: .timeout) {
            await loadProfile(id: 1)
        }
        #expect(profile == .success(Profile(user: User(id: 1))))
    }

    @Test
    func asyncSequencesOfResults() async {
        let events = stream([
            Result<Int, AppError>.success(1), .failure(.notFound), .success(2),
        ])
        let log = Recorder<AppError>()
        var shown: [String] = []
        func show(_ name: String) { shown.append(name) }

        let names =
            events
            .tapError { error in log(error) }
            .mapAsync { id in await loadName(id) }
            .successes()

        for await name in names {
            show(name)
        }

        #expect(shown == ["name 1", "name 2"])
        #expect(log.all == [.notFound])

        let stream = AsyncStream<Result<Int, AppError>> { continuation in
            continuation.success(1)
            continuation.finishWithFailure(.timeout)
        }

        var results: [Result<Int, AppError>] = []
        for await result in stream { results.append(result) }
        #expect(results == [.success(1), .failure(.timeout)])
    }

    @Test
    func keepingTheSourceOrder() async {
        let refs = stream(Array(1...6))
        let downloader = Downloader()
        var rendered: [String] = []
        func render(_ image: String) { rendered.append(image) }

        let images = refs.mapAsyncOrdered(concurrency: 8) { ref in
            await downloader.fetch(ref)
        }

        for await image in images {
            render(image)
        }

        #expect(rendered == (1...6).map { "image \($0)" })

        let moreRefs = stream(Array(1...6))
        let limited = moreRefs.mapAsyncOrdered(concurrency: 8, bufferLimit: 64) { ref in
            await downloader.fetch(ref)
        }

        var limitedImages: [String] = []
        for await image in limited { limitedImages.append(image) }
        #expect(limitedImages == rendered)
    }

    @Test
    func inTheOrderTheyFinish() async {
        let photos = stream(Array(1...6))
        let renderer = Renderer()
        var gallery = Set<String>()

        let thumbs = photos.mapAsyncUnordered(concurrency: 8) { photo in
            await renderer.thumbnail(for: photo)
        }

        for await thumb in thumbs {
            gallery.insert(thumb)
        }

        #expect(gallery == Set((1...6).map { "thumb \($0)" }))
    }
}
