import Observation
import PageKit

/// One view model for every feed screen. It owns a `Paginator`, publishes its snapshots
/// and forwards what the view does. The Articles and Blogs tabs both use this class.
@MainActor @Observable
final class FeedViewModel<Source: PageSource> {
    /// Everything the screen needs, as one value, so each page causes one render.
    private(set) var snapshot = PaginationSnapshot<Source.Item>.initial
    private let paginator: Paginator<Source>

    /// Which kind of token drives this feed, for the debug footer.
    var tokenStyleLabel: String { String(describing: Source.Token.self) }

    /// How many items are on screen, for the debug footer.
    var itemsLoadedLabel: String { "\(snapshot.items.count) items" }

    /// Creates a view model. Nothing loads until `run()`.
    convenience init(source: Source, configuration: PaginationConfiguration = .init()) {
        self.init(paginator: Paginator(source: source, configuration: configuration))
    }

    /// Creates a view model around a paginator you already have.
    init(paginator: Paginator<Source>) {
        self.paginator = paginator
    }

    deinit {
        let paginator = paginator
        Task { await paginator.cancel() }   // stops loads and ends the stream
    }

    /// Call from the view's `.task`. SwiftUI cancels it when the view disappears.
    func run() async {
        await paginator.start()
        for await snapshot in paginator.snapshots() {
            self.snapshot = snapshot
        }
    }

    /// Runs in its own task, which `.refreshable` can't cancel. Cancelling the caller of
    /// a paginator load aborts that load, and a refresh is what makes SwiftUI cancel.
    func refresh() async {
        await Task { [paginator] in await paginator.refresh() }.value
    }

    /// Loads the next page when asked. Scrolling normally does this by itself, but only
    /// this can move past a blank page, because no row appears to trigger the load.
    func loadMore() {
        Task { await paginator.loadNextPage() }
    }

    /// Tell the view model a row is on screen, so it can load ahead.
    func itemAppeared(_ item: Source.Item) {
        let id = item.id
        Task { await paginator.itemAppeared(id: id) }
    }

    /// Repeats the load that failed.
    func retry() {
        Task { await paginator.retry() }
    }

    /// Pauses read-ahead while the app is in the background.
    func sceneBecameActive(_ isActive: Bool) {
        Task { await paginator.setAppActive(isActive) }
    }
}
