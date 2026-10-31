import PageKit
import SwiftUI

/// What fills the screen when there are no stories to show.
nonisolated enum FirstPageContent: Equatable {
    case none, loading, empty, offline, failed

    init(state: PaginationState) {
        switch state {
        case .idle, .loadingFirstPage:
            self = .loading
        case .empty:
            self = .empty
        case .failed(.offline, isFirstPage: true):
            self = .offline
        case .failed(_, isFirstPage: true):
            self = .failed
        case .loaded, .loadingNextPage, .refreshing, .failed(_, isFirstPage: false):
            self = .none
        }
    }

    /// Whether the screen shows a Retry button.
    var offersRetry: Bool { self == .offline || self == .failed }

    var title: String {
        switch self {
        case .none: ""
        case .loading: "Loading the latest stories"
        case .empty: "No stories yet"
        case .offline: "You're offline"
        case .failed: "Couldn't load stories"
        }
    }

    var detail: String? {
        switch self {
        case .none, .loading: nil
        case .empty: "Pull down to check again."
        case .offline: "Stories load when you reconnect."
        case .failed: "Check back shortly, or try again now."
        }
    }
}

/// Covers the space under the masthead until the first page arrives.
struct FirstPageOverlay: View {
    let state: PaginationState
    let onRetry: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let content = FirstPageContent(state: state)
        if content != .none {
            VStack(spacing: 12) {
                orbit(isMoving: content == .loading && !reduceMotion)
                    .frame(width: 96, height: 96)
                Text(content.title)
                    .font(Typography.stateTitle)
                    .foregroundStyle(Palette.ink)
                if let detail = content.detail {
                    Text(detail)
                        .font(Typography.summary)
                        .foregroundStyle(Palette.inkSoft)
                }
                if content.offersRetry {
                    Button("Retry", action: onRetry)
                        .font(Typography.kicker)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(Palette.signal)
                        .padding(.top, 4)
                }
            }
            .multilineTextAlignment(.center)
            .padding(32)
            .accessibilityElement(children: .contain)
            .allowsHitTesting(content.offersRetry)
        }
    }

    /// The loading screen's one movement: the satellite circling the planet.
    private func orbit(isMoving: Bool) -> some View {
        TimelineView(.animation(paused: !isMoving)) { timeline in
            OrbitEmblem(
                planet: Palette.signal,
                ring: Palette.ink,
                satellite: Palette.mustard,
                satelliteAngle: isMoving ? .degrees(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) * 120) : .degrees(35)
            )
        }
    }
}
