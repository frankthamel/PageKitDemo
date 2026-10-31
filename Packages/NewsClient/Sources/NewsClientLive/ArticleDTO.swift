import Foundation
import NewsClient

/// Wire shape of one page from the Spaceflight News API.
struct NewsPageDTO: Decodable {
    let count: Int
    let next: String?
    let results: [ArticleDTO]
}

/// Wire shape of one story. Fields the app does not use are ignored.
struct ArticleDTO: Decodable {
    struct Author: Decodable {
        let name: String
    }

    let id: Int
    let title: String
    let authors: [Author]
    let url: String?
    let imageURL: String?
    let newsSite: String
    let summary: String
    let publishedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, title, authors, url, summary
        case imageURL = "image_url"
        case newsSite = "news_site"
        case publishedAt = "published_at"
    }

    /// The domain article, or `nil` when `url` is missing or not a usable web link.
    var article: Article? {
        guard let link = Self.webURL(url) else { return nil }
        let byline = authors.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
        return Article(
            id: id,
            title: title,
            summary: summary,
            source: newsSite,
            author: byline.isEmpty ? nil : byline,
            url: link,
            imageURL: Self.webURL(imageURL),
            publishedAt: publishedAt
        )
    }

    private static func webURL(_ string: String?) -> URL? {
        guard let string, !string.isEmpty, let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
}

extension JSONDecoder {
    /// Decoder for the API: ISO 8601 dates with or without fractional seconds.
    static var spaceflightNews: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Unrecognised date: \(text)"))
        }
        return decoder
    }
}
