import NewsClient
import PageKit

/// The Articles feed. It pages by index: the app works out the next offset itself
/// and stops when it has reached the total the server reports.
///
/// `nonisolated` because the project defaults to the main actor, and a `PageSource`
/// is called from the paginator's own task.
nonisolated struct ArticlesIndexSource: PageSource {
    let service: any NewsService
    let feedID: String
    let firstToken = IndexToken.first(size: 20)

    /// Creates the source. `feedID` names its cache, so give each service its own.
    init(service: any NewsService, feedID: String = "news.articles") {
        self.service = service
        self.feedID = feedID
    }

    func loadPage(_ token: IndexToken) async throws -> Page<Article, IndexToken> {
        let page = try await mappingHTTPErrors {
            try await service.articles(section: .articles, offset: token.offset, limit: token.size)
        }
        let isLastPage = token.offset + page.articles.count >= page.total
        return Page(items: page.articles, nextToken: isLastPage ? nil : token.next)
    }
}
