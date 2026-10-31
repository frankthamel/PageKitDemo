import NewsClient
import SwiftUI

/// One story in the list. Tapping it opens the story in the system browser.
struct ArticleRow: View {
    private let article: Article
    private let display: ArticleDisplay
    @ScaledMetric(relativeTo: .body) private var imageSide: CGFloat = 76
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(article: Article) {
        self.article = article
        display = ArticleDisplay(article)
    }

    var body: some View {
        Link(destination: article.url) {
            VStack(alignment: .leading, spacing: 6) {
                header
                content
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rule().padding(.horizontal, 16) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilityLabel)
        .accessibilityAddTraits(.isLink)
        .accessibilityIdentifier("feed.row.\(article.id)")
    }

    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }

    private func stack(spacing: CGFloat, alignment: VerticalAlignment) -> AnyLayout {
        isLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
    }

    private var header: some View {
        let layout = stack(spacing: isLarge ? 2 : 12, alignment: .firstTextBaseline)
        return layout {
            Kicker(text: display.kicker, swatch: display.swatch)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(display.age)
                .font(Typography.meta)
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
        }
    }

    private var content: some View {
        let layout = stack(spacing: 12, alignment: .top)
        return layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .font(Typography.headline)
                    .foregroundStyle(Palette.ink)
                Text(display.summary)
                    .font(Typography.summary)
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ArticleImage(url: article.imageURL, swatch: display.swatch, monogram: display.monogram)
                .frame(maxWidth: isLarge ? .infinity : imageSide)
                .frame(height: imageSide)
        }
    }
}
