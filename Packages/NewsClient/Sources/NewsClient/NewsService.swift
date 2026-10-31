/// Source of news pages, in the two paging styles.
public protocol NewsService: Sendable {
    /// Returns up to `limit` stories starting at `offset` (index-style paging).
    func articles(section: NewsSection, offset: Int, limit: Int) async throws -> NewsPage

    /// Returns up to `limit` stories after `cursor` (cursor-style paging).
    /// Pass `nil` for the first page. Use `NewsPage.nextCursor` for the following ones.
    func articles(section: NewsSection, cursor: String?, limit: Int) async throws -> NewsPage
}
