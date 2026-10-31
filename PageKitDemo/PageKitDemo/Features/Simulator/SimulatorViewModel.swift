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
    private let clearAllCaches: @MainActor () async -> Void
    private let clearMemory: @MainActor () -> Void
    private var pending: SimulationSettings?
    private var isPushing = false

    /// Creates a view model.
    /// - Parameters:
    ///   - apply: Receives each new set of settings, in order. A burst of changes may be
    ///     collapsed into its last value.
    ///   - clearCaches: Empties the memory and disk caches.
    ///   - clearMemoryCache: Empties the memory cache only.
    init(
        apply: @escaping @Sendable (SimulationSettings) async -> Void,
        clearCaches: @escaping @MainActor () async -> Void,
        clearMemoryCache: @escaping @MainActor () -> Void = { PageKit.clearMemoryCache() }
    ) {
        self.apply = apply
        self.clearAllCaches = clearCaches
        self.clearMemory = clearMemoryCache
    }

    /// Creates a view model that steers `mock`. `connectivity` hears about the Offline
    /// switch after the mock does, because feeds retry the moment they hear of a reconnect.
    convenience init(
        mock: MockNewsService,
        connectivity: SimulatedConnectivity,
        clearCaches: @escaping @MainActor () async -> Void
    ) {
        self.init(
            apply: { settings in
                await mock.update(settings)
                connectivity.setOnline(!settings.isOffline)
            },
            clearCaches: clearCaches
        )
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
        await clearAllCaches()
    }

    /// Empties the memory cache only, as the system does under memory pressure.
    /// Items already on screen stay.
    func simulateMemoryWarning() {
        clearMemory()
    }

    private var settings: SimulationSettings {
        SimulationSettings(maxLatency: latency, failureRate: failureRate, isOffline: isOffline)
    }

    /// Sends settings one at a time, in order. While one is in flight, newer values replace
    /// each other, so dragging a slider never builds a queue.
    private func push() {
        pending = settings
        guard !isPushing else { return }
        isPushing = true
        Task {
            while let next = pending {
                pending = nil
                await apply(next)
            }
            isPushing = false
        }
    }
}
