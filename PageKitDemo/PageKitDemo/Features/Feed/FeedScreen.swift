import NewsClient
import PageKit
import SwiftUI

/// A feed of stories. It works with any source of articles, whichever token that source
/// pages by, and draws everything from the view model's one snapshot.
struct FeedScreen<Source: PageSource>: View where Source.Item == Article {
    let title: String
    let viewModel: FeedViewModel<Source>
    /// Opens the simulator panel. The masthead shows its button only when this is set.
    var onOpenSimulator: (() -> Void)?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let snapshot = viewModel.snapshot
        ScrollView {
            LazyVStack(spacing: 0) {
                Masthead(section: title, onOpenSimulator: onOpenSimulator)
                Rule(weight: 3, color: Palette.ink)
                if let lead = snapshot.items.first {
                    LeadArticleCard(article: lead)
                        .id(lead.id)    // a new lead story must not inherit the last one's picture
                        .onAppear { viewModel.itemAppeared(lead) }
                    Rule(weight: 3, color: Palette.ink)
                    Rule(weight: 0.5, color: Palette.ink).padding(.top, 2)
                }
                ForEach(snapshot.items.dropFirst()) { article in
                    ArticleRow(article: article)
                        .onAppear { viewModel.itemAppeared(article) }
                }
                PageFooter(
                    state: snapshot.state,
                    onLoadMore: viewModel.loadMore,
                    onRetry: viewModel.retry
                )
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.paper)
        .overlay {
            if snapshot.items.isEmpty {
                FirstPageOverlay(state: snapshot.state, onRetry: viewModel.retry)
            }
        }
        .overlay(alignment: .top) { StatusBarBlock() }
        .safeAreaInset(edge: .top, spacing: 0) { notice(for: snapshot) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DebugFooter(
                tokenStyle: viewModel.tokenStyleLabel,
                itemsLoaded: viewModel.itemsLoadedLabel,
                isStale: snapshot.isStale
            )
        }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.run() }
        .onChange(of: scenePhase) { _, phase in
            viewModel.sceneBecameActive(phase == .active)
        }
    }

    @ViewBuilder
    private func notice(for snapshot: PaginationSnapshot<Article>) -> some View {
        if let notice = FeedNotice(
            lastError: snapshot.lastError,
            isOffline: snapshot.isOffline,
            hasItems: !snapshot.items.isEmpty
        ) {
            OfflineBanner(notice: notice)
        }
    }
}

/// The nameplate: the paper's red block, with the section and today's date under the title.
private struct Masthead: View {
    let section: String
    let onOpenSimulator: (() -> Void)?
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The Orbital")
                .font(.system(size: titleSize, weight: .black, design: .serif))
                .tracking(-0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.trailing, 84)     // leaves the emblem clear
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    sectionName
                    Spacer(minLength: 12)
                    date
                }
                VStack(alignment: .leading, spacing: 2) {
                    sectionName
                    date
                }
            }
        }
        .foregroundStyle(Palette.onSignal)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            OrbitEmblem(
                planet: Palette.mustard,
                ring: Palette.onSignal,
                satellite: Palette.onSignal,
                satelliteAngle: .degrees(195)
            )
            .frame(width: 150, height: 150)
            .offset(x: 50, y: -32)
        }
        .background(Palette.signal)
        .clipped()
        .accessibilityElement(children: .combine)
        .overlay(alignment: .topTrailing) { simulatorButton }
    }

    @ViewBuilder
    private var simulatorButton: some View {
        if let onOpenSimulator {
            Button(action: onOpenSimulator) {
                Image(systemName: "slider.horizontal.3")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.onSignal)
                    .frame(width: 32, height: 32)
                    .background(Palette.signal, in: Circle())   // keeps the icon clear of the planet
                    .overlay(Circle().stroke(Palette.onSignal, lineWidth: 1.5))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Simulator")
            .accessibilityIdentifier("simulator.open")
        }
    }

    private var sectionName: some View {
        Text(section).font(Typography.kicker)
    }

    private var date: some View {
        Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide).year())
            .font(Typography.meta)
    }
}

/// Keeps the status bar on red once the masthead has scrolled away.
private struct StatusBarBlock: View {
    var body: some View {
        Color.clear
            .frame(height: 0)
            .background(Palette.signal, ignoresSafeAreaEdges: .top)
    }
}

/// Small print for the demo: shows the pagination at work as you scroll.
private struct DebugFooter: View {
    let tokenStyle: String
    let itemsLoaded: String
    let isStale: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(tokenStyle).fontWeight(.semibold)
            Text(itemsLoaded).monospacedDigit()
            Spacer(minLength: 0)
            if isStale { Text("Saved copy").italic() }
        }
        .font(Typography.meta)
        .foregroundStyle(Palette.inkSoft)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Palette.paperShade)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed.debug")
    }
}
