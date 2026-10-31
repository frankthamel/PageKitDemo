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
        let id = UUID()
        let articles: FeedViewModel<ArticlesIndexSource>
        let blogs: FeedViewModel<BlogsCursorSource>
    }

    /// The launch argument that starts the app on simulated data.
    nonisolated static let mockLaunchArgument = "-mock"

    /// The current source of stories.
    private(set) var mode: Mode
    /// The simulated service. The simulator panel steers it.
    let mock: MockNewsService
    /// The feeds for the current mode, or `nil` for the moment a mode switch is under way.
    private(set) var feeds: Feeds?

    private let live: any NewsService
    private let clearCaches: @MainActor () async -> Void

    /// The service for the current mode.
    var service: any NewsService {
        switch mode {
        case .live: live
        case .mock: mock
        }
    }

    /// Creates the environment.
    /// - Parameters:
    ///   - arguments: Launch arguments. `-mock` starts in mock mode.
    ///   - live: The real service.
    ///   - mock: The simulated service.
    ///   - clearCaches: Empties PageKit's caches. Replaced in tests.
    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        live: any NewsService = LiveNewsService(),
        mock: MockNewsService = MockNewsService(),
        clearCaches: @escaping @MainActor () async -> Void = { await PageKit.clearAll() }
    ) {
        self.mode = arguments.contains(Self.mockLaunchArgument) ? .mock : .live
        self.live = live
        self.mock = mock
        self.clearCaches = clearCaches
        self.feeds = makeFeeds()
    }

    /// A fresh Articles feed on the current service.
    func makeArticlesFeed() -> FeedViewModel<ArticlesIndexSource> {
        FeedViewModel(source: ArticlesIndexSource(service: service))
    }

    /// A fresh Blogs feed on the current service.
    func makeBlogsFeed() -> FeedViewModel<BlogsCursorSource> {
        FeedViewModel(source: BlogsCursorSource(service: service))
    }

    /// Switches between live and mock data. Live and mock share feed IDs, so the old
    /// feeds are released first, the caches are emptied and awaited, and only then are
    /// new feeds built. No page from one mode can reach the other.
    func switchMode(to newMode: Mode) async {
        guard newMode != mode, feeds != nil else { return }
        feeds = nil   // releases the old view models, whose deinit cancels their paginators
        await clearCaches()
        mode = newMode
        feeds = makeFeeds()
    }

    private func makeFeeds() -> Feeds {
        Feeds(articles: makeArticlesFeed(), blogs: makeBlogsFeed())
    }
}
