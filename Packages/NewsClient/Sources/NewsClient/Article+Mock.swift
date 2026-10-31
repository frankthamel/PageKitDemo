import Foundation

extension Article {
    private static let epoch = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 UTC
    private static let sources = ["Orbital Daily", "Launch Pad", "Deep Space Review", "Ground Control", "Apogee Weekly"]
    private static let authors = ["A. Hartley", "M. Okafor", "S. Lindqvist", "R. Banerjee", nil]
    private static let subjects = ["Lunar lander", "Mars sample return", "Reusable booster", "Ion thruster", "Space station crew", "Weather satellite", "Deep-space probe"]
    private static let events = ["passes key test", "slips to next quarter", "reaches orbit", "wins new contract", "returns first data", "enters final review"]

    /// Builds a deterministic made-up article. The same `id` and `section` always give the same article.
    /// Mock articles carry no image, so nothing is fetched from the network.
    public static func mock(id: Int, section: NewsSection) -> Article {
        let subject = subjects[id % subjects.count]
        let event = events[(id / subjects.count) % events.count]
        let kind = section == .blogs ? "Blog" : "News"
        return Article(
            id: id,
            title: "\(subject) \(event)",
            summary: "\(kind) item \(id): \(subject.lowercased()) \(event) after weeks of preparation.",
            source: sources[id % sources.count],
            author: authors[id % authors.count],
            url: URL(string: "https://example.com/\(section.rawValue)/\(id)")!,
            imageURL: nil,
            publishedAt: epoch.addingTimeInterval(-Double(id) * 3600)
        )
    }

    /// A short fixed list for SwiftUI previews and tests.
    public static let previewList: [Article] = (1...10).map { mock(id: $0, section: .articles) }
}
