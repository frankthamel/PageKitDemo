import NewsClient
import SwiftUI

/// The top story: a full-width picture over a large headline.
struct LeadArticleCard: View {
    let article: Article
    @ScaledMetric(relativeTo: .largeTitle) private var imageHeight: CGFloat = 220

    var body: some View {
        let display = ArticleDisplay(article)
        Link(destination: article.url) {
            VStack(alignment: .leading, spacing: 10) {
                ArticleImage(url: article.imageURL, display: display)
                    .frame(height: imageHeight)
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(display: display)
                    Text(article.title)
                        .font(Typography.leadHeadline)
                        .foregroundStyle(Palette.ink)
                    Text(display.summary)
                        .font(Typography.leadSummary)
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(4)
                    Text(byline(display))
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

    private func byline(_ display: ArticleDisplay) -> String {
        display.byline.map { "\($0), \(display.age)" } ?? display.age
    }
}
