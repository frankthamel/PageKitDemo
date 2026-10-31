import Foundation
import NewsClient
import PageKit
import Testing
@testable import PageKitDemo

struct PageFooterContentTests {
    @Test(arguments: [
        (PaginationState.idle, PageFooterContent.none),
        (.loadingFirstPage, .none),
        (.refreshing, .none),
        (.empty, .none),
        (.failed(.server(status: 503), isFirstPage: true), .none),
        (.loaded(hasMore: true), .loadMore),
        (.loadingNextPage, .loading),
        (.failed(.server(status: 503), isFirstPage: false), .retry),
        (.failed(.timedOut, isFirstPage: false), .retry),
        (.failed(.offline, isFirstPage: false), .offline),
        (.loaded(hasMore: false), .endOfFeed),
    ])
    func mapsEveryState(state: PaginationState, expected: PageFooterContent) {
        #expect(PageFooterContent(state: state) == expected)
    }

    @Test func usesTheAgreedCopy() {
        #expect(PageFooterContent.loadMore.message == "Load more")
        #expect(PageFooterContent.retry.message == "Couldn't load more. Tap to retry.")
        #expect(PageFooterContent.offline.message == "Connect to load more")
        #expect(PageFooterContent.endOfFeed.message == "You're all caught up")
    }
}

struct FirstPageContentTests {
    @Test(arguments: [
        (PaginationState.idle, FirstPageContent.loading),
        (.loadingFirstPage, .loading),
        (.empty, .empty),
        (.failed(.offline, isFirstPage: true), .offline),
        (.failed(.server(status: 500), isFirstPage: true), .failed),
        (.loaded(hasMore: true), .none),
        (.loaded(hasMore: false), .none),
        (.loadingNextPage, .none),
        (.refreshing, .none),
        (.failed(.offline, isFirstPage: false), .none),
    ])
    func mapsEveryState(state: PaginationState, expected: FirstPageContent) {
        #expect(FirstPageContent(state: state) == expected)
    }

    @Test func onlyFailuresOfferRetry() {
        #expect(FirstPageContent.failed.offersRetry)
        #expect(FirstPageContent.offline.offersRetry)
        #expect(!FirstPageContent.loading.offersRetry)
        #expect(!FirstPageContent.empty.offersRetry)
    }
}

struct FeedNoticeTests {
    @Test func isSilentWithNothingWrong() {
        #expect(FeedNotice(lastError: nil, isOffline: false, hasItems: true) == nil)
    }

    @Test func staysAwayFromAnEmptyScreen() {
        #expect(FeedNotice(lastError: .timedOut, isOffline: true, hasItems: false) == nil)
    }

    @Test func reportsAFailedRefreshOverItems() {
        let notice = FeedNotice(lastError: .timedOut, isOffline: false, hasItems: true)
        #expect(notice == .refreshFailed)
        #expect(notice?.message == "Couldn't refresh")
    }

    @Test func prefersTheOfflineMessageOverTheError() {
        let notice = FeedNotice(lastError: .offline, isOffline: true, hasItems: true)
        #expect(notice == .offline)
    }
}

struct ArticleDisplayTests {
    private func article(
        title: String = "Starship flies",
        summary: String = "Summary",
        source: String = "NASA",
        author: String? = "A. Writer"
    ) -> Article {
        Article(
            id: 1, title: title, summary: summary, source: source, author: author,
            url: URL(string: "https://example.com")!, imageURL: nil, publishedAt: .now
        )
    }

    @Test func summaryLosesStrayWhitespace() {
        #expect(ArticleDisplay(article(summary: "\n In this   episode\n, Mike ")).summary == "In this episode , Mike")
    }

    @Test func bylineNamesTheAuthorWhenThereIsOne() {
        #expect(ArticleDisplay(article()).byline == "By A. Writer")
        #expect(ArticleDisplay(article(author: nil)).byline == nil)
    }

    @Test func monogramSkipsPunctuation() {
        #expect(ArticleDisplay(article(title: "“apollo” returns")).monogram == "A")
        #expect(ArticleDisplay(article(title: "2026 in review")).monogram == "2")
        #expect(ArticleDisplay(article(title: "…")).monogram == "O")
    }

    @Test func swatchIsTheSameForTheSameSource() {
        #expect(ArticleDisplay(article(source: "NASA")).swatch == ArticleDisplay(article(title: "Other", source: "NASA")).swatch)
    }

    @Test func differentSourcesReachEverySwatch() {
        let swatches = Set(["NASA", "SpaceNews", "Teslarati", "Orbital Daily", "Launch Pad", "Ground Control", "ESA", "Spaceflight Now"]
            .map { ArticleDisplay(article(source: $0)).swatch })
        #expect(swatches.count == Swatch.allCases.count)
    }

    @Test func accessibilityLabelReadsLikeASentence() {
        let label = ArticleDisplay(article()).accessibilityLabel
        #expect(label.hasPrefix("Starship flies. NASA, by A. Writer, "))
    }
}
