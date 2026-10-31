import Foundation
import NewsClient
import Testing
@testable import NewsClientLive

/// Answers every request from a closure and records what was asked.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    static func install(_ handler: @escaping Handler) {
        lock.withLock {
            self.handler = handler
            recorded = []
        }
    }

    static var requests: [URLRequest] { lock.withLock { recorded } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { () -> Handler? in
            Self.recorded.append(request)
            return Self.handler
        }
        guard let handler, let url = request.url else { return }
        let reply = handler(request)
        let response = HTTPURLResponse(
            url: url, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct LiveNewsServiceTests {
    private static let sample = """
    {"count":36732,"next":"https://api.spaceflightnewsapi.net/v4/articles/?limit=2&offset=2","previous":null,
    "results":[
    {"id":40668,"title":"APOD: Night on a Spooky Planet","authors":[{"name":"NASA","socials":null}],
    "url":"https://science.nasa.gov/image-article/apod/","image_url":"https://assets.science.nasa.gov/a.jpg",
    "news_site":"NASA","summary":"Today's APOD.","published_at":"2026-10-31T04:05:00Z",
    "updated_at":"2026-10-31T04:50:11.988095Z","featured":false,"launches":[],"events":[]},
    {"id":40667,"title":"Live coverage: Falcon 9","authors":[{"name":"Will Robinson-Smith","socials":null}],
    "url":"https://spaceflightnow.com/2026/10/30/live/","image_url":"https://spaceflightnow.com/b.jpg",
    "news_site":"Spaceflight Now","summary":"Starlink 15-18.","published_at":"2026-10-30T22:46:02Z",
    "updated_at":"2026-10-30T22:50:27.258514Z","featured":false,"launches":[],"events":[]}]}
    """

    private func service(
        status: Int = 200,
        headers: [String: String] = [:],
        body: String = sample
    ) -> LiveNewsService {
        StubURLProtocol.install { _ in (status, headers, Data(body.utf8)) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return LiveNewsService(session: URLSession(configuration: configuration))
    }

    private func article(published: String = "2026-10-31T04:05:00Z", image: String = "null", url: String = "\"https://a.example/x\"") -> String {
        """
        {"count":1,"next":null,"results":[{"id":1,"title":"T","authors":[],"url":\(url),
        "image_url":\(image),"news_site":"S","summary":"X","published_at":"\(published)"}]}
        """
    }

    @Test func decodesSampleResponse() async throws {
        let page = try await service().articles(section: .articles, offset: 0, limit: 2)
        #expect(page.total == 36732)
        #expect(page.nextCursor == "https://api.spaceflightnewsapi.net/v4/articles/?limit=2&offset=2")
        #expect(page.articles.map(\.id) == [40668, 40667])
        let first = page.articles[0]
        #expect(first.title == "APOD: Night on a Spooky Planet")
        #expect(first.source == "NASA")
        #expect(first.author == "NASA")
        #expect(first.url == URL(string: "https://science.nasa.gov/image-article/apod/"))
        #expect(first.imageURL == URL(string: "https://assets.science.nasa.gov/a.jpg"))
        #expect(first.publishedAt == Date(timeIntervalSince1970: 1_793_419_500))
    }

    @Test func offsetRequestBuildsQuery() async throws {
        _ = try await service().articles(section: .articles, offset: 20, limit: 10)
        let url = try #require(StubURLProtocol.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host == "api.spaceflightnewsapi.net")
        #expect(items.contains(URLQueryItem(name: "limit", value: "10")))
        #expect(items.contains(URLQueryItem(name: "offset", value: "20")))
    }

    @Test func firstCursorRequestUsesSectionPath() async throws {
        let live = service()
        _ = try await live.articles(section: .blogs, cursor: nil, limit: 5)
        _ = try await live.articles(section: .articles, cursor: nil, limit: 5)
        let urls = StubURLProtocol.requests.compactMap { $0.url?.absoluteString }
        #expect(urls.count == 2)
        #expect(urls[0].hasPrefix("https://api.spaceflightnewsapi.net/v4/blogs/?"))
        #expect(urls[1].hasPrefix("https://api.spaceflightnewsapi.net/v4/articles/?"))
        let query = StubURLProtocol.requests.first?.url?.query ?? ""
        #expect(query.contains("limit=5"))
    }

    @Test func cursorIsUsedVerbatim() async throws {
        let cursor = "https://api.spaceflightnewsapi.net/v4/blogs/?limit=7&offset=14&search=x%20y"
        _ = try await service().articles(section: .blogs, cursor: cursor, limit: 99)
        #expect(StubURLProtocol.requests.first?.url?.absoluteString == cursor)
    }

    @Test func offHostCursorIsRejected() async {
        let live = service()
        await #expect(throws: NewsClientError.invalidCursor) {
            try await live.articles(section: .articles, cursor: "https://evil.example/v4/articles/?offset=2", limit: 2)
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func httpCursorIsRejected() async {
        let live = service()
        await #expect(throws: NewsClientError.invalidCursor) {
            try await live.articles(section: .articles, cursor: "http://api.spaceflightnewsapi.net/v4/articles/?offset=2", limit: 2)
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func http429MapsWithRetryAfter() async {
        let live = service(status: 429, headers: ["Retry-After": "7"], body: "{}")
        await #expect(throws: NewsClientError.http(status: 429, retryAfter: 7)) {
            try await live.articles(section: .articles, offset: 0, limit: 2)
        }
    }

    @Test func http500Maps() async {
        let live = service(status: 500, body: "{}")
        await #expect(throws: NewsClientError.http(status: 500, retryAfter: nil)) {
            try await live.articles(section: .articles, offset: 0, limit: 2)
        }
    }

    @Test func badJSONMapsToDecoding() async {
        let live = service(body: "not json")
        await #expect(throws: NewsClientError.decoding) {
            try await live.articles(section: .articles, offset: 0, limit: 2)
        }
    }

    @Test func emptyImageURLBecomesNil() async throws {
        let page = try await service(body: article(image: "\"\"")).articles(section: .articles, offset: 0, limit: 1)
        #expect(page.articles.first?.imageURL == nil)
        #expect(page.articles.count == 1)
    }

    @Test func fractionalSecondDatesDecode() async throws {
        let page = try await service(body: article(published: "2026-10-31T04:05:00.250Z"))
            .articles(section: .articles, offset: 0, limit: 1)
        let date = try #require(page.articles.first?.publishedAt)
        #expect(abs(date.timeIntervalSince1970 - 1_793_419_500.25) < 0.001)
    }

    @Test func unusableArticleURLDropsOnlyThatArticle() async throws {
        let body = """
        {"count":3,"next":null,"results":[
        {"id":1,"title":"Good","authors":[],"url":"https://a.example/1","image_url":null,"news_site":"S","summary":"X","published_at":"2026-10-31T04:05:00Z"},
        {"id":2,"title":"Empty","authors":[],"url":"","image_url":null,"news_site":"S","summary":"X","published_at":"2026-10-31T04:05:00Z"},
        {"id":3,"title":"Missing","authors":[],"image_url":null,"news_site":"S","summary":"X","published_at":"2026-10-31T04:05:00Z"}]}
        """
        let page = try await service(body: body).articles(section: .articles, offset: 0, limit: 3)
        #expect(page.articles.map(\.id) == [1])
        #expect(page.total == 3)
    }
}
