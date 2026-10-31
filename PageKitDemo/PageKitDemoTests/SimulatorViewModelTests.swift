import Foundation
import NewsClient
import PageKit
import Testing
@testable import PageKitDemo

@MainActor
struct SimulatorViewModelTests {
    /// Records every settings value the view model pushes.
    private actor Recorder {
        private(set) var applied: [SimulationSettings] = []
        func record(_ settings: SimulationSettings) { applied.append(settings) }
    }

    private final class Calls {
        var cacheClears = 0
        var memoryClears = 0
    }

    private func makeModel(calls: Calls = Calls()) -> (SimulatorViewModel, Recorder) {
        let recorder = Recorder()
        let model = SimulatorViewModel(
            apply: { await recorder.record($0) },
            clearCaches: { calls.cacheClears += 1 },
            clearMemoryCache: { calls.memoryClears += 1 }
        )
        return (model, recorder)
    }

    @Test func slidersUpdateMockService() async {
        let (model, recorder) = makeModel()

        model.latency = 2
        model.failureRate = 0.5
        model.isOffline = true

        #expect(await eventually { await recorder.applied.last == SimulationSettings(maxLatency: 2, failureRate: 0.5, isOffline: true) })
    }

    @Test func slidersReachARealMockService() async {
        let mock = MockNewsService(articlesPerSection: 10)
        let model = SimulatorViewModel(mock: mock) { }

        model.isOffline = true

        #expect(await eventually {
            do { _ = try await mock.articles(section: .articles, offset: 0, limit: 1); return false } catch { return true }
        })
    }

    @Test func chaosAppliesPreset() async {
        let (model, recorder) = makeModel()
        model.isOffline = true

        model.applyChaos()

        #expect(model.latency == SimulationSettings.chaos.maxLatency)
        #expect(model.failureRate == SimulationSettings.chaos.failureRate)
        #expect(!model.isOffline)
        #expect(await eventually { await recorder.applied.last == .chaos })
    }

    @Test func simulateMemoryWarningClearsOnlyTheMemoryCache() async {
        let calls = Calls()
        let (model, _) = makeModel(calls: calls)

        model.simulateMemoryWarning()

        #expect(calls.memoryClears == 1)
        #expect(calls.cacheClears == 0)
    }

    @Test func simulateMemoryWarningKeepsItems() async {
        let source = ArticlesIndexSource(service: MockNewsService(articlesPerSection: 100))
        let feed = FeedViewModel(source: source, configuration: PaginationConfiguration())
        let task = Task { await feed.run() }
        defer { task.cancel() }
        #expect(await eventually { feed.snapshot.items.count == 20 })
        let calls = Calls()
        let (model, _) = makeModel(calls: calls)

        model.simulateMemoryWarning()

        #expect(calls.memoryClears == 1)
        #expect(feed.snapshot.items.count == 20)
    }

    @Test func clearCachesRunsTheInjectedClear() async {
        let calls = Calls()
        let (model, _) = makeModel(calls: calls)

        await model.clearCaches()

        #expect(calls.cacheClears == 1)
        #expect(calls.memoryClears == 0)
    }
}

private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
}
