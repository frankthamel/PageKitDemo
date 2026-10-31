import Foundation
import NewsClient
import PageKit
import Testing
@testable import PageKitDemo

@MainActor
struct FeedViewModelTests {
    /// Never reads or writes a cache, and fails fast instead of retrying.
    private var configuration: PaginationConfiguration {
        var configuration = PaginationConfiguration()
        configuration.cachePolicy = .networkOnly
        configuration.retry = RetryPolicy(maxAttempts: 1)
        return configuration
    }

    private func makeModel(
        service: MockNewsService = MockNewsService(articlesPerSection: 100)
    ) -> FeedViewModel<ArticlesIndexSource> {
        FeedViewModel(source: ArticlesIndexSource(service: service), configuration: configuration)
    }

    @Test func viewModelPublishesSnapshots() async throws {
        let model = makeModel()
        let task = Task { await model.run() }
        defer { task.cancel() }

        #expect(await eventually { model.snapshot.items.count == 20 })
        #expect(model.snapshot.state == .loaded(hasMore: true))
        #expect(model.tokenStyleLabel == "IndexToken")
        #expect(model.pagesLoadedLabel == "1 page loaded")
    }

    @Test func viewModelRetryRecoversAfterFailure() async throws {
        let service = MockNewsService(settings: SimulationSettings(failureRate: 1), random: { 0 })
        let model = makeModel(service: service)
        let task = Task { await model.run() }
        defer { task.cancel() }

        #expect(await eventually { model.snapshot.state == .failed(.timedOut, isFirstPage: true) })

        await service.update(SimulationSettings())
        model.retry()

        #expect(await eventually { model.snapshot.items.count == 20 })
    }

    @Test func itemAppearedLoadsMore() async throws {
        let model = makeModel()
        let task = Task { await model.run() }
        defer { task.cancel() }
        #expect(await eventually { model.snapshot.items.count == 20 })

        model.itemAppeared(try #require(model.snapshot.items.last))

        #expect(await eventually { model.snapshot.items.count >= 40 })
        #expect(model.pagesLoadedLabel.hasPrefix("2 pages") || model.pagesLoadedLabel.hasPrefix("3 pages"))
    }

    @Test func sameViewModelDrivesBothStyles() async throws {
        let service = MockNewsService(articlesPerSection: 100)
        let articles = makeModel(service: service)
        let blogs = FeedViewModel(source: BlogsCursorSource(service: service), configuration: configuration)
        let tasks = [Task { await articles.run() }, Task { await blogs.run() }]
        defer { tasks.forEach { $0.cancel() } }

        #expect(await eventually { articles.snapshot.items.count == 20 && blogs.snapshot.items.count == 20 })
        #expect(articles.tokenStyleLabel == "IndexToken")
        #expect(blogs.tokenStyleLabel == "CursorToken")
        #expect(Set(articles.snapshot.items.map(\.id)).isDisjoint(with: blogs.snapshot.items.map(\.id)))
    }

    /// SwiftUI may cancel the task behind `.refreshable`. The refresh must still finish.
    @Test func refreshSurvivesCancelledCaller() async throws {
        let model = FeedViewModel(source: SlowRefreshSource(), configuration: configuration)
        let task = Task { await model.run() }
        defer { task.cancel() }
        #expect(await eventually { model.snapshot.items.first?.id == 1 })

        let caller = Task { await model.refresh() }
        try await Task.sleep(nanoseconds: 50_000_000)
        caller.cancel()
        await caller.value

        #expect(await eventually { model.snapshot.items.first?.id == 2 })
    }
}

/// Polls until `condition` holds, for up to five seconds.
@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<500 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

/// Answers instantly the first time, then takes 200 ms and returns a different article.
private struct SlowRefreshSource: PageSource {
    let feedID = "tests.slow-refresh"
    let firstToken = IndexToken.first(size: 20)
    private let calls = CallCounter()

    func loadPage(_ token: IndexToken) async throws -> Page<Article, IndexToken> {
        let call = await calls.next()
        if call > 1 { try await Task.sleep(nanoseconds: 200_000_000) }
        return Page(items: [Article.mock(id: call, section: .articles)], nextToken: nil)
    }
}

private actor CallCounter {
    private var count = 0
    func next() -> Int { count += 1; return count }
}
