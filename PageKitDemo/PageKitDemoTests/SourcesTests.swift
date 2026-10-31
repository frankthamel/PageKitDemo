import Foundation
import NewsClient
import PageKit
import Testing
@testable import PageKitDemo

struct SourcesTests {
    private let service = MockNewsService(articlesPerSection: 45)

    @Test func indexSourceComputesNextToken() async throws {
        let source = ArticlesIndexSource(service: service)
        let page = try await source.loadPage(source.firstToken)

        #expect(page.items.count == 20)
        #expect(page.nextToken == IndexToken(page: 2, size: 20))
    }

    @Test func indexSourceEndsAtTotal() async throws {
        let source = ArticlesIndexSource(service: service)
        let page = try await source.loadPage(IndexToken(page: 3, size: 20))

        #expect(page.items.count == 5)
        #expect(page.nextToken == nil)
    }

    @Test func cursorSourceUsesServerCursor() async throws {
        let source = BlogsCursorSource(service: service)
        let first = try await source.loadPage(source.firstToken)
        let second = try await source.loadPage(try #require(first.nextToken))

        #expect(first.nextToken == CursorToken(value: "mock:20", size: 20))
        #expect(second.items.first?.id == first.items.last.map { $0.id + 1 })
    }

    @Test func cursorSourceEndsOnNilCursor() async throws {
        let source = BlogsCursorSource(service: service)
        let page = try await source.loadPage(CursorToken(value: "mock:40", size: 20))

        #expect(page.items.count == 5)
        #expect(page.nextToken == nil)
    }

    @Test func httpErrorsMapToPageKitHTTPError() async {
        let source = ArticlesIndexSource(service: FailingService(error: NewsClientError.http(status: 503, retryAfter: 7)))

        await #expect(throws: PageKitHTTPError(status: 503, retryAfter: 7)) {
            try await source.loadPage(source.firstToken)
        }
    }

    @Test func urlErrorsPassThroughUnchanged() async {
        let source = BlogsCursorSource(service: FailingService(error: URLError(.timedOut)))

        await #expect(throws: URLError(.timedOut)) {
            try await source.loadPage(source.firstToken)
        }
    }
}

private struct FailingService: NewsService {
    let error: any Error

    func articles(section: NewsSection, offset: Int, limit: Int) async throws -> NewsPage { throw error }
    func articles(section: NewsSection, cursor: String?, limit: Int) async throws -> NewsPage { throw error }
}
