import Foundation
import Testing
@testable import NewsClient

@Suite struct MockNewsServiceTests {
    private func service(
        count: Int = 2000,
        settings: SimulationSettings = .init(),
        random: @escaping @Sendable () -> Double = { 0.5 }
    ) -> MockNewsService {
        MockNewsService(articlesPerSection: count, settings: settings, random: random)
    }

    @Test func articlesAreDeterministic() async throws {
        let first = try await service().articles(section: .articles, offset: 10, limit: 5)
        let second = try await service().articles(section: .articles, offset: 10, limit: 5)
        #expect(first.articles == second.articles)
        #expect(Article.mock(id: 7, section: .blogs) == Article.mock(id: 7, section: .blogs))
    }

    @Test func offsetPagingCoversTheFeedWithoutGaps() async throws {
        let service = service()
        var ids: [Int] = []
        var offset = 0
        while true {
            let page = try await service.articles(section: .articles, offset: offset, limit: 150)
            #expect(page.total == 2000)
            if page.articles.isEmpty { break }
            ids += page.articles.map(\.id)
            offset += page.articles.count
        }
        #expect(ids.count == 2000)
        #expect(Set(ids).count == 2000)
    }

    @Test func cursorPagingCoversTheFeedAndEnds() async throws {
        let service = service()
        var ids: [Int] = []
        var cursor: String?
        var pages = 0
        repeat {
            let page = try await service.articles(section: .blogs, cursor: cursor, limit: 300)
            ids += page.articles.map(\.id)
            cursor = page.nextCursor
            pages += 1
        } while cursor != nil
        #expect(ids.count == 2000)
        #expect(Set(ids).count == 2000)
        #expect(pages == 7)
    }

    @Test func sectionsHaveDistinctIDs() async throws {
        let service = service()
        let a = try await service.articles(section: .articles, offset: 0, limit: 2000)
        let b = try await service.articles(section: .blogs, offset: 0, limit: 2000)
        #expect(Set(a.articles.map(\.id)).isDisjoint(with: b.articles.map(\.id)))
    }

    @Test func offlineThrowsNotConnected() async {
        let service = service(settings: .init(isOffline: true))
        await #expect(throws: URLError(.notConnectedToInternet)) {
            _ = try await service.articles(section: .articles, offset: 0, limit: 10)
        }
        await #expect(throws: URLError(.notConnectedToInternet)) {
            _ = try await service.articles(section: .articles, cursor: nil, limit: 10)
        }
    }

    @Test func failureRateOneAlwaysFails() async {
        let service = service(settings: .init(failureRate: 1))
        for _ in 0..<5 {
            await #expect(throws: (any Error).self) {
                _ = try await service.articles(section: .articles, offset: 0, limit: 10)
            }
        }
    }

    @Test func failureRateZeroNeverFails() async throws {
        let service = service(settings: .init(failureRate: 0), random: { 0 })
        for _ in 0..<5 {
            _ = try await service.articles(section: .articles, offset: 0, limit: 10)
        }
    }

    @Test func settingsCanChangeLive() async throws {
        let service = service()
        _ = try await service.articles(section: .articles, offset: 0, limit: 10)
        await service.update(.init(isOffline: true))
        await #expect(throws: URLError(.notConnectedToInternet)) {
            _ = try await service.articles(section: .articles, offset: 0, limit: 10)
        }
        await service.update(.init())
        _ = try await service.articles(section: .articles, offset: 0, limit: 10)
    }

    @Test func latencyPathRunsWithoutWaitingWhenRandomIsZero() async throws {
        let service = service(settings: .init(maxLatency: 3), random: { 0 })
        let page = try await service.articles(section: .articles, offset: 0, limit: 3)
        #expect(page.articles.count == 3)
    }

    @Test func badCursorThrows() async {
        let service = service()
        await #expect(throws: NewsClientError.invalidCursor) {
            _ = try await service.articles(section: .articles, cursor: "garbage", limit: 10)
        }
    }

    @Test func chaosPresetMatchesSpec() {
        #expect(SimulationSettings.chaos.maxLatency == 3)
        #expect(SimulationSettings.chaos.failureRate == 0.2)
    }
}
