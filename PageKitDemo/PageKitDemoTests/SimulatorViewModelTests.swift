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

    private func makeModel() -> (SimulatorViewModel, Recorder) {
        let recorder = Recorder()
        return (SimulatorViewModel { await recorder.record($0) }, recorder)
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
        let model = SimulatorViewModel(mock: mock)

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

    @Test func simulateMemoryWarningKeepsItems() async throws {
        let source = ArticlesIndexSource(service: MockNewsService(articlesPerSection: 100))
        var configuration = PaginationConfiguration()
        configuration.cachePolicy = .networkOnly
        let feed = FeedViewModel(source: source, configuration: configuration)
        let task = Task { await feed.run() }
        defer { task.cancel() }
        #expect(await eventually { feed.snapshot.items.count == 20 })

        SimulatorViewModel { _ in }.simulateMemoryWarning()

        #expect(feed.snapshot.items.count == 20)
    }

    @Test func clearCachesFinishes() async {
        await SimulatorViewModel { _ in }.clearCaches()
    }
}

private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return false
}
