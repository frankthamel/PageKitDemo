/// The two feeds a news service can serve.
public enum NewsSection: String, Codable, Sendable, CaseIterable {
    /// News articles.
    case articles
    /// Blog posts.
    case blogs
}
