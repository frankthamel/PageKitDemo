import Foundation

/// Knobs that make a mock service behave like a flaky network.
public struct SimulationSettings: Sendable, Equatable {
    /// Longest artificial delay, in seconds. Each call waits a random time up to this. 0 means no delay.
    public var maxLatency: TimeInterval
    /// Chance from 0 to 1 that a call fails.
    public var failureRate: Double
    /// When `true`, every call throws `URLError(.notConnectedToInternet)`.
    public var isOffline: Bool

    /// Creates settings. The defaults are a perfect network.
    public init(maxLatency: TimeInterval = 0, failureRate: Double = 0, isOffline: Bool = false) {
        self.maxLatency = maxLatency
        self.failureRate = failureRate
        self.isOffline = isOffline
    }

    /// A rough network: up to 3 seconds of delay and one failure in five calls.
    public static let chaos = SimulationSettings(maxLatency: 3, failureRate: 0.2)
}
