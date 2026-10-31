import Foundation

/// An in-memory ``NewsService`` with a deterministic feed per section.
///
/// It honours both paging styles and can simulate latency, failures and being offline
/// through ``SimulationSettings``. Randomness is injected so tests stay predictable.
public actor MockNewsService: NewsService {
    private static let cursorPrefix = "mock:"
    private static let idStride = 1_000_000

    private let articlesPerSection: Int
    private var settings: SimulationSettings
    private let random: @Sendable () -> Double

    /// Creates a service.
    /// - Parameters:
    ///   - articlesPerSection: Feed length of each section.
    ///   - settings: Starting simulation settings.
    ///   - random: Source of numbers in `0..<1`, used for latency and failures.
    public init(
        articlesPerSection: Int = 2000,
        settings: SimulationSettings = .init(),
        random: @escaping @Sendable () -> Double = { .random(in: 0..<1) }
    ) {
        self.articlesPerSection = articlesPerSection
        self.settings = settings
        self.random = random
    }

    /// Replaces the simulation settings. Takes effect on the next call.
    public func update(_ settings: SimulationSettings) {
        self.settings = settings
    }

    public func articles(section: NewsSection, offset: Int, limit: Int) async throws -> NewsPage {
        try await simulateNetwork()
        return page(section: section, offset: max(0, offset), limit: limit)
    }

    public func articles(section: NewsSection, cursor: String?, limit: Int) async throws -> NewsPage {
        try await simulateNetwork()
        let offset = try cursor.map(Self.offset(fromCursor:)) ?? 0
        let result = page(section: section, offset: offset, limit: limit)
        let next = offset + result.articles.count
        return NewsPage(
            articles: result.articles,
            total: result.total,
            nextCursor: next < articlesPerSection ? Self.cursor(forOffset: next) : nil
        )
    }

    // MARK: - Private

    private func page(section: NewsSection, offset: Int, limit: Int) -> NewsPage {
        let start = min(offset, articlesPerSection)
        let end = min(start + max(0, limit), articlesPerSection)
        let base = section == .blogs ? Self.idStride : 0
        let items = (start..<end).map { Article.mock(id: base + $0 + 1, section: section) }
        return NewsPage(articles: items, total: articlesPerSection, nextCursor: nil)
    }

    private func simulateNetwork() async throws {
        if settings.isOffline { throw URLError(.notConnectedToInternet) }
        if settings.maxLatency > 0 {
            let seconds = random() * settings.maxLatency
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        if random() < settings.failureRate { throw URLError(.timedOut) }
    }

    private static func cursor(forOffset offset: Int) -> String { cursorPrefix + String(offset) }

    private static func offset(fromCursor cursor: String) throws -> Int {
        guard cursor.hasPrefix(cursorPrefix),
              let offset = Int(cursor.dropFirst(cursorPrefix.count)),
              offset >= 0 else { throw NewsClientError.invalidCursor }
        return offset
    }
}
