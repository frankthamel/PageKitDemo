import Foundation
import PageKit
import Synchronization

/// The network status mock mode reports. The real path monitor can't see the simulator's
/// Offline switch, so without this a mock feed would never learn that the connection came
/// back, and would never pick up where it stopped.
nonisolated final class SimulatedConnectivity: ConnectivityMonitoring {
    private struct State {
        var isOnline = true
        var streams: [UUID: AsyncStream<ConnectivityStatus>.Continuation] = [:]
    }

    private let state = Mutex(State())

    /// A stream that yields the current status first, then every change.
    func updates() -> AsyncStream<ConnectivityStatus> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.streams[id] = nil }
            }
            state.withLock { state in
                state.streams[id] = continuation
                continuation.yield(ConnectivityStatus(isOnline: state.isOnline))
            }
        }
    }

    /// Tells every stream the new status, if it is new.
    func setOnline(_ isOnline: Bool) {
        state.withLock { state in
            guard state.isOnline != isOnline else { return }
            state.isOnline = isOnline
            for continuation in state.streams.values {
                continuation.yield(ConnectivityStatus(isOnline: isOnline))
            }
        }
    }
}
