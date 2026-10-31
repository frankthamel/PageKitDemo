import PageKit
import SwiftUI

/// A problem worth mentioning while stories stay on screen.
nonisolated enum FeedNotice: Equatable {
    case offline, refreshFailed

    /// Returns `nil` when there is nothing to say. A next-page failure never gets here:
    /// it shows in the footer and doesn't set `lastError`.
    init?(lastError: PaginationError?, isOffline: Bool, hasItems: Bool) {
        guard hasItems else { return nil }
        if isOffline {
            self = .offline
        } else if lastError != nil {
            self = .refreshFailed
        } else {
            return nil
        }
    }

    var message: String {
        switch self {
        case .offline: "You're offline. Showing saved stories."
        case .refreshFailed: "Couldn't refresh"
        }
    }
}

/// A small strip under the status bar. It never replaces the list.
struct OfflineBanner: View {
    let notice: FeedNotice

    var body: some View {
        Text(notice.message)
            .font(Typography.meta.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .background(Palette.mustard, ignoresSafeAreaEdges: [])
            .environment(\.colorScheme, .light)
            .accessibilityIdentifier("feed.banner")
    }
}
