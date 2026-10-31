import NewsClient
import SwiftUI

/// The top story: a full-width picture over a large headline.
struct LeadArticleCard: View {
    private let article: Article
    private let display: ArticleDisplay
    @ScaledMetric(relativeTo: .largeTitle) private var imageHeight: CGFloat = 220

    init(article: Article) {
        self.article = article
        display = ArticleDisplay(article)
    }

    var body: some View {
        Link(destination: article.url) {
            VStack(alignment: .leading, spacing: 10) {
                ArticleImage(url: article.imageURL, swatch: display.swatch, monogram: display.monogram)
                    .frame(height: imageHeight)
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: display.kicker, swatch: display.swatch)
                    Text(article.title)
                        .font(Typography.leadHeadline)
                        .foregroundStyle(Palette.ink)
                    Text(display.summary)
                        .font(Typography.leadSummary)
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(4)
                    Text(byline)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.inkSoft)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .multilineTextAlignment(.leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilityLabel)
        .accessibilityAddTraits(.isLink)
        .accessibilityIdentifier("feed.row.\(article.id)")
    }

    private var byline: String {
        display.byline.map { "\($0), \(display.age)" } ?? display.age
    }
}
