import NewsClient
import Observation
import PageKit

/// The state behind the simulator panel. Moving a control pushes the new settings to the
/// mock service, so the next request sees them.
@MainActor @Observable
final class SimulatorViewModel {
    /// Longest artificial delay, in seconds.
    var latency: Double = 0 { didSet { push() } }
    /// Chance from 0 to 1 that a request fails.
    var failureRate: Double = 0 { didSet { push() } }
    /// Whether every request fails as if the device had no connection.
    var isOffline = false { didSet { push() } }

    private let apply: @Sendable (SimulationSettings) async -> Void
    private var lastPush: Task<Void, Never>?

    /// Creates a view model that hands each new set of settings to `apply`.
    init(apply: @escaping @Sendable (SimulationSettings) async -> Void) {
        self.apply = apply
    }

    /// Creates a view model that steers `mock`.
    convenience init(mock: MockNewsService) {
        self.init { await mock.update($0) }
    }

    /// Sets the rough-network preset: slow and flaky, but online.
    func applyChaos() {
        let chaos = SimulationSettings.chaos
        latency = chaos.maxLatency
        failureRate = chaos.failureRate
        isOffline = chaos.isOffline
    }

    /// Empties the memory and disk caches, so the next load goes to the network.
    func clearCaches() async {
        await PageKit.clearAll()
    }

    /// Empties the memory cache only, as the system does under memory pressure.
    /// Items already on screen stay.
    func simulateMemoryWarning() {
        PageKit.clearMemoryCache()
    }

    private var settings: SimulationSettings {
        SimulationSettings(maxLatency: latency, failureRate: failureRate, isOffline: isOffline)
    }

    /// Sends settings one after another, so a slow call can't land after a newer one.
    private func push() {
        let previous = lastPush
        let settings = settings
        let apply = apply
        lastPush = Task {
            await previous?.value
            await apply(settings)
        }
    }
}
