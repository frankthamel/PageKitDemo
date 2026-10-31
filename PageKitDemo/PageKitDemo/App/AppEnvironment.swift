import Foundation
import NewsClient
import NewsClientLive
import Observation
import PageKit

/// The composition root. It decides whether the app reads from the live service or from
/// the simulated one, and builds the two feeds on top of that choice.
@MainActor @Observable
final class AppEnvironment {
    /// Where stories come from.
    nonisolated enum Mode: String, CaseIterable, Sendable {
        case live, mock
    }

    /// The two feeds on screen, built together so they always share a mode.
    struct Feeds {
        let articles: FeedViewModel<ArticlesIndexSource>
        let blogs: FeedViewModel<BlogsCursorSource>
    }

    /// The launch argument that starts the app on simulated data.
    nonisolated static let mockLaunchArgument = "-mock"

    /// The current source of stories.
    private(set) var mode: Mode
    /// The service for the current mode. The live one is only built once live mode is used.
    private(set) var service: any NewsService
    /// The simulated service. The simulator panel steers it.
    let mock: MockNewsService
    /// The feeds for the current mode, or `nil` for the moment a mode switch is under way.
    private(set) var feeds: Feeds?
    /// Whether a mode switch is under way. A second switch is ignored until it ends.
    private(set) var isSwitching = false

    private let makeLive: () -> any NewsService
    private let clearAllCaches: @MainActor () async -> Void

    /// Creates the environment.
    /// - Parameters:
    ///   - arguments: Launch arguments. `-mock` starts in mock mode.
    ///   - clearCaches: Empties PageKit's caches. Replaced in tests.
    ///   - makeLive: Builds the real service, only when live mode is used.
    ///   - mock: The simulated service.
    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        clearCaches: @escaping @MainActor () async -> Void = { await PageKit.clearAll() },
        makeLive: @escaping () -> any NewsService = { LiveNewsService() },
        mock: MockNewsService = MockNewsService()
    ) {
        let mode: Mode = arguments.contains(Self.mockLaunchArgument) ? .mock : .live
        self.mode = mode
        self.makeLive = makeLive
        self.mock = mock
        self.service = mode == .live ? makeLive() : mock
        self.clearAllCaches = clearCaches
        self.feeds = makeFeeds()
    }

    /// A fresh Articles source on the current service. Its feed ID names the mode, so
    /// live and mock pages can never share a cache.
    func makeArticlesSource() -> ArticlesIndexSource {
        ArticlesIndexSource(service: service, feedID: "news.articles.\(mode.rawValue)")
    }

    /// A fresh Blogs source on the current service, with a feed ID that names the mode.
    func makeBlogsSource() -> BlogsCursorSource {
        BlogsCursorSource(service: service, feedID: "news.blogs.\(mode.rawValue)")
    }

    /// A fresh Articles feed on the current service.
    func makeArticlesFeed() -> FeedViewModel<ArticlesIndexSource> {
        FeedViewModel(source: makeArticlesSource())
    }

    /// A fresh Blogs feed on the current service.
    func makeBlogsFeed() -> FeedViewModel<BlogsCursorSource> {
        FeedViewModel(source: makeBlogsSource())
    }

    /// Empties PageKit's memory and disk caches.
    func clearCaches() async {
        await clearAllCaches()
    }

    /// Switches between live and mock data.
    ///
    /// Each mode caches under its own feed IDs, so the two can't mix even if an old
    /// paginator is slow to stop. The old feeds are also released first, which cancels
    /// them, and the caches are cleared, so the new mode starts from a clean slate.
    func switchMode(to newMode: Mode) async {
        guard newMode != mode, !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        feeds = nil   // releases the old view models, whose deinit cancels their paginators
        await clearCaches()
        mode = newMode
        service = newMode == .live ? makeLive() : mock
        feeds = makeFeeds()
    }

    private func makeFeeds() -> Feeds {
        Feeds(articles: makeArticlesFeed(), blogs: makeBlogsFeed())
    }
}
