import Foundation

/// One news story as shown in a feed.
public struct Article: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier within the whole feed (and across sections).
    public let id: Int
    /// Headline.
    public let title: String
    /// Short description of the story.
    public let summary: String
    /// Name of the publication that produced the story.
    public let source: String
    /// Byline, when the source provides one.
    public let author: String?
    /// Link to the full story on the publisher's site.
    public let url: URL
    /// Link to a lead image, when there is one.
    public let imageURL: URL?
    /// When the story was published.
    public let publishedAt: Date

    /// Creates an article from its parts.
    public init(
        id: Int,
        title: String,
        summary: String,
        source: String,
        author: String? = nil,
        url: URL,
        imageURL: URL? = nil,
        publishedAt: Date
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.source = source
        self.author = author
        self.url = url
        self.imageURL = imageURL
        self.publishedAt = publishedAt
    }
}
