/// One page of a feed, as returned by a ``NewsService``.
public struct NewsPage: Sendable {
    /// The stories on this page.
    public let articles: [Article]
    /// How many stories the whole feed holds.
    public let total: Int
    /// Opaque cursor for the next page, or `nil` when this is the last page.
    public let nextCursor: String?

    /// Creates a page.
    public init(articles: [Article], total: Int, nextCursor: String? = nil) {
        self.articles = articles
        self.total = total
        self.nextCursor = nextCursor
    }
}
