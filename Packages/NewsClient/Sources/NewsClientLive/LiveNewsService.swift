import Foundation
import NewsClient

/// A ``NewsService`` backed by the Spaceflight News API (v4), which needs no API key.
///
/// ``NewsSection/articles`` maps to `/articles/` and ``NewsSection/blogs`` to `/blogs/`.
/// Cursors are the API's own `next` URLs. They are used as given, but only if they are
/// `https` URLs on the API host; anything else throws ``NewsClientError/invalidCursor``
/// before a request is made.
///
/// A story whose `url` is missing or not a web link is dropped from its page and the
/// rest of the page is still returned, so `articles.count` can be smaller than `limit`
/// while `total` still comes from the API's `count`.
public struct LiveNewsService: NewsService {
    private static let host = "api.spaceflightnewsapi.net"
    private static let basePath = "/v4"

    private let session: URLSession

    /// Creates a service that sends its requests through `session`.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func articles(section: NewsSection, offset: Int, limit: Int) async throws -> NewsPage {
        try await page(from: endpoint(section, limit: limit, offset: offset))
    }

    public func articles(section: NewsSection, cursor: String?, limit: Int) async throws -> NewsPage {
        guard let cursor else {
            return try await page(from: endpoint(section, limit: limit, offset: nil))
        }
        guard let url = Self.validatedCursor(cursor) else { throw NewsClientError.invalidCursor }
        return try await page(from: url)
    }

    private func endpoint(_ section: NewsSection, limit: Int, offset: Int?) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = "\(Self.basePath)/\(section.rawValue)/"
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
            + (offset.map { [URLQueryItem(name: "offset", value: String($0))] } ?? [])
        return components.url!
    }

    private static func validatedCursor(_ cursor: String) -> URL? {
        guard let url = URL(string: cursor),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == host
        else { return nil }
        return url
    }

    private func page(from url: URL) async throws -> NewsPage {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw NewsClientError.http(status: http.statusCode, retryAfter: retryAfter)
        }
        guard let dto = try? JSONDecoder.spaceflightNews.decode(NewsPageDTO.self, from: data) else {
            throw NewsClientError.decoding
        }
        return NewsPage(articles: dto.results.compactMap(\.article), total: dto.count, nextCursor: dto.next)
    }
}
