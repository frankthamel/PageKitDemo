import PageKit
import SwiftUI

/// What the row after the last story shows for a given state.
nonisolated enum PageFooterContent: Equatable {
    case none, loading, retry, offline, endOfFeed

    init(state: PaginationState) {
        switch state {
        case .idle, .loadingFirstPage, .refreshing, .empty, .loaded(hasMore: true),
             .failed(_, isFirstPage: true):
            self = .none
        case .loadingNextPage:
            self = .loading
        case .failed(.offline, isFirstPage: false):
            self = .offline
        case .failed(_, isFirstPage: false):
            self = .retry
        case .loaded(hasMore: false):
            self = .endOfFeed
        }
    }

    /// The printed text, for the states that have any.
    var message: String? {
        switch self {
        case .none, .loading: nil
        case .retry: "Couldn't load more. Tap to retry."
        case .offline: "Connect to load more"
        case .endOfFeed: "You're all caught up"
        }
    }
}

/// The row after the last story. It is its own row, never a fake item in the list.
struct PageFooter: View {
    let state: PaginationState
    let onRetry: () -> Void

    var body: some View {
        let content = PageFooterContent(state: state)
        Group {
            switch content {
            case .none:
                Color.clear.frame(height: 1)
            case .loading:
                ProgressView()
                    .tint(Palette.signalText)
                    .accessibilityLabel("Loading more stories")
            case .retry:
                Button(action: onRetry) { label(content, color: Palette.signalText) }
                    .buttonStyle(.plain)
            case .offline:
                label(content, color: Palette.inkSoft)
            case .endOfFeed:
                VStack(spacing: 6) {
                    OrbitEmblem(planet: Palette.signal, ring: Palette.ink, satellite: Palette.mustard)
                        .frame(width: 44, height: 44)
                    label(content, color: Palette.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: content == .none ? 1 : 64)
        .padding(.horizontal, 16)
        .padding(.vertical, content == .none ? 0 : 8)
        .accessibilityIdentifier("feed.footer")
    }

    private func label(_ content: PageFooterContent, color: Color) -> some View {
        Text(content.message ?? "")
            .font(Typography.notice)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
    }
}
