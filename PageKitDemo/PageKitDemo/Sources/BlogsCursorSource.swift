import NewsClient
import PageKit

/// The Blogs feed. It pages by cursor: the server hands back the cursor for the next
/// page, and no cursor means the end.
nonisolated struct BlogsCursorSource: PageSource {
    let service: any NewsService
    let feedID = "news.blogs"
    let firstToken = CursorToken(value: nil, size: 20)

    func loadPage(_ token: CursorToken) async throws -> Page<Article, CursorToken> {
        let page = try await mappingHTTPErrors {
            try await service.articles(section: .blogs, cursor: token.value, limit: token.size)
        }
        let next = page.nextCursor.map { CursorToken(value: $0, size: token.size) }
        return Page(items: page.articles, nextToken: next)
    }
}
