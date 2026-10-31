import NewsClient
import SwiftUI

/// One story in the list. Tapping it opens the story in the system browser.
struct ArticleRow: View {
    let article: Article
    @ScaledMetric(relativeTo: .body) private var imageSide: CGFloat = 76
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let display = ArticleDisplay(article)
        Link(destination: article.url) {
            VStack(alignment: .leading, spacing: 6) {
                header(display)
                content(display)
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

    private func header(_ display: ArticleDisplay) -> some View {
        let layout = stack(spacing: isLarge ? 2 : 12, alignment: .firstTextBaseline)
        return layout {
            Kicker(display: display)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(display.age)
                .font(Typography.meta)
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
        }
    }

    private func content(_ display: ArticleDisplay) -> some View {
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
            ArticleImage(url: article.imageURL, display: display)
                .frame(maxWidth: isLarge ? .infinity : imageSide)
                .frame(height: imageSide)
        }
    }
}
