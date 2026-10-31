import PageKit
import SwiftUI

/// What the row after the last story shows for a given state.
nonisolated enum PageFooterContent: Equatable {
    case none, loadMore, loading, retry, offline, endOfFeed

    init(state: PaginationState) {
        switch state {
        case .idle, .loadingFirstPage, .refreshing, .empty, .failed(_, isFirstPage: true):
            self = .none
        case .loaded(hasMore: true):
            self = .loadMore
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
        case .loadMore: "Load more"
        case .retry: "Couldn't load more. Tap to retry."
        case .offline: "Connect to load more"
        case .endOfFeed: "You're all caught up"
        }
    }
}

/// The row after the last story. It is its own row, never a fake item in the list.
struct PageFooter: View {
    let state: PaginationState
    let onLoadMore: () -> Void
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
            case .loadMore:
                button(content, action: onLoadMore)
            case .retry:
                button(content, action: onRetry)
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
        .frame(maxWidth: .infinity, minHeight: content == .none ? 1 : Self.rowHeight)
        .accessibilityIdentifier("feed.footer")
    }

    private static let rowHeight: CGFloat = 80

    private func button(_ content: PageFooterContent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label(content, color: Palette.signalText)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func label(_ content: PageFooterContent, color: Color) -> some View {
        Text(content.message ?? "")
            .font(Typography.notice)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }
}
