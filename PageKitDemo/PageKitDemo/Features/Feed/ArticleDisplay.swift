import Foundation
import NewsClient

/// One of the paper's three spot colours.
nonisolated enum Swatch: CaseIterable, Hashable {
    case signal, mustard, teal
}

/// What the lead story and the rows print for an article, worked out once in one place.
nonisolated struct ArticleDisplay {
    /// The label above the headline.
    let kicker: String
    /// The summary on one line. Sources often send stray line breaks and runs of spaces.
    let summary: String
    /// "By <author>", when the article has one.
    let byline: String?
    /// The large character on the image placeholder.
    let monogram: String
    /// Each source keeps its colour across launches, which `hashValue` wouldn't give.
    let swatch: Swatch
    /// How long ago the story ran.
    let age: String
    /// The whole story as one sentence for VoiceOver.
    let accessibilityLabel: String

    init(_ article: Article) {
        kicker = article.source
        summary = article.summary.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        byline = article.author.map { "By \($0)" }
        monogram = article.title.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "O"
        let sum = article.source.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        swatch = Swatch.allCases[sum % Swatch.allCases.count]
        age = article.publishedAt.formatted(.relative(presentation: .named))

        let credit = article.author.map { "\(article.source), by \($0)" } ?? article.source
        accessibilityLabel = "\(article.title). \(credit), \(age)"
    }
}
