# Building PageKit: A Reusable Swift Pagination Library

Oct 31, 2026 · @Frank

## 1. Overview

PageKit is a zero-dependency Swift package that loads any list in pages, from either an index-based or a cursor-based API, and keeps scrolling smooth with a two-level cache: NSCache in memory and JSON files on disk for offline use.

Almost every app has at least one infinite feed: products, posts, orders, messages. Teams rewrite the same logic every time: track the current page, stop duplicate requests, show a spinner at the bottom, handle errors, cache what you have. PageKit packages that logic once, behind a small generic API, so an app only has to say *how to fetch one page*. Everything else is the library's job.

**Goals**

- One API for both pagination styles, with the difference hidden behind a generic token type.
- Works with any model type, any backend and any UI framework, because the library contains no UI code at all.
- Instant first paint from cache, then a silent refresh from the network.
- Readable offline: the last pages you saw are still there with no connection.
- No third-party code. Only Foundation, Network (for connectivity) and Apple's concurrency features.
- Every public type documented in plain English, so a junior developer can adopt it in an afternoon.

**Non-goals (version 1)**

- **Any UI.** No views, view models, footers, spinners, and no SwiftUI, UIKit or AppKit imports. The library publishes state and accepts commands; the app decides how everything looks. Section 18 shows the app side.
- Image loading and image caching. Images are a separate problem with different sizes and lifetimes; apps keep their own image pipeline.
- Two-way sync or writes back to the server. PageKit reads lists; it does not post to them.
- A full database. Pages are stored as simple files, not as a queryable store.
- Bidirectional scrolling (loading older items above, like a chat). The design leaves room for it in version 2.

**How to read this document.** Sections 2 and 3 list what the library must do and how well. Sections 4 to 15 explain each design decision and the reason behind it. Section 18 is the app-side guide: how an app uses the library for each pagination type and common use cases. Section 19 condenses the trade-offs into answers you can give in an interview.

## 2. Functional requirements

Functional requirements describe *what* the library does. Each one has an ID so tests and pull requests can point at it.

| ID | Requirement | Priority |
| --- | --- | --- |
| FR-1 | Load the first page of a list and expose the items to the UI. | Must |
| FR-2 | Load the next page on demand, and know when there are no more pages. | Must |
| FR-3 | Support index-based APIs (`?page=3&limit=20` or `?offset=40&limit=20`). | Must |
| FR-4 | Support cursor-based APIs (`?after=abc123&limit=20`). | Must |
| FR-5 | Work with any item type that is `Identifiable`, `Codable` and `Sendable`. | Must |
| FR-6 | Never send two requests for the same page at the same time. | Must |
| FR-7 | Remove duplicate items across pages, matched by `id`. | Must |
| FR-8 | Pull-to-refresh: reload from the first page and replace the list. | Must |
| FR-9 | Cache loaded pages in memory with NSCache for instant re-display. | Must |
| FR-10 | Persist pages to disk and show them when the device is offline. | Must |
| FR-11 | Prefetch the next page before the user reaches the bottom. | Must |
| FR-12 | Expose a clear state the UI can render: loading, loaded, empty, error, end of list, offline. | Must |
| FR-13 | Retry failed requests, automatically for temporary errors and manually from the UI. | Must |
| FR-14 | Let the app choose a cache policy per feed (network first, cache first, cache only, network only). | Must |
| FR-15 | Clear caches: per feed, all feeds, by age, by size, and on logout. | Must |
| FR-16 | Resume loading automatically when the network comes back. | Should |
| FR-17 | Update or remove a single item in place (for example, after the user deletes a post) and keep caches in sync. | Should |
| FR-18 | Cancel in-flight work when the screen goes away or a refresh starts. | Should |
| FR-19 | Ship no UI code: expose state as a framework-agnostic AsyncStream plus async commands, so any SwiftUI, UIKit or AppKit app can drive it. | Should |
| FR-20 | Provide a ready-made `URLSession` page source for simple JSON APIs. | Could |

## 3. Non-functional requirements

Non-functional requirements describe *how well* the library behaves. For an open-source library these matter as much as features: they decide whether strangers trust it in production.

| Area | Requirement | How we measure it |
| --- | --- | --- |
| Performance | Scrolling stays at the display's refresh rate (60 or 120 fps) while pages load. | Instruments Animation Hitches: hitch time ratio under 5 ms/s on an iPhone 12. |
| Performance | No disk or JSON work on the main thread. | Main Thread Checker and `OSSignposter` intervals in tests. |
| Latency | A cached feed paints its first screen in under 100 ms after the view appears. | Signpost from `onAppear` to first items published. |
| Memory | Memory cache has a hard cost limit (default 20 MB) and gives memory back under pressure. | Simulated memory warning in the sample app. |
| Disk | Disk cache has a size cap (default 50 MB) and an age limit (default 7 days). | Unit tests on the eviction routine. |
| Thread safety | No data races. Compiles cleanly under Swift 6 strict concurrency. | `swift build -Xswiftc -strict-concurrency=complete` in CI. |
| Reliability | A failed next page never erases items already on screen. | State machine tests. |
| Genericity | No assumptions about the backend, the model or the UI framework. | Sample app uses three different APIs. |
| Dependencies | Zero third-party dependencies. | `Package.swift` has an empty `dependencies` array. |
| Testability | Every external effect (network, disk, clock, connectivity) sits behind a protocol. | 90% line coverage on the core module. |
| Platform | iOS 15+, macOS 12+, tvOS 15+, watchOS 8+ (the first versions with async/await). | CI matrix. |
| API stability | Semantic versioning; no breaking change without a major version. | `swift package diagnose-api-breaking-changes` in CI. |
| Documentation | Every public symbol has DocC comments; a getting-started tutorial ships with the package. | DocC build with warnings as errors. |
| Privacy | Cached data stays in the app's sandbox, excluded from iCloud backup, and is easy to wipe on logout. | Unit test checks the backup-exclusion flag. |

## 4. Core concepts: index vs cursor pagination

Both styles answer the same question, "give me the next chunk", so PageKit treats the thing that identifies a chunk as a generic **token**. The engine never looks inside the token; it only stores it and hands it back.

**Index-based (also called offset or page-number).** The client asks for a position: "page 3, 20 per page" or "skip 40, take 20". It is simple and lets you jump to any page. Its weakness is *drift*: if a new item is inserted at the top while you scroll, everything shifts down by one, so page 3 now repeats the last item of page 2. Items can also be skipped if something is deleted.

**Cursor-based (also called keyset).** The server returns an opaque string with each page, such as `"eyJpZCI6MTIzfQ"`, meaning "continue after the item with id 123". The client sends it back to get the next page. It is stable when data changes and fast on large tables, but you can only move forward one page at a time, and you cannot jump to page 50.

|  | Index-based | Cursor-based |
| --- | --- | --- |
| Token | Page number or offset (`Int`) | Opaque string from the server |
| Who computes the next token | The client: `page + 1` | The server, inside the response |
| How we know it ended | Fewer items than the page size, or `page >= totalPages` | Next cursor is `nil` or `hasMore == false` |
| Jump to a page | Yes | No |
| Stable when data changes | No: duplicates and gaps possible | Yes |
| Can prefetch pages in parallel | Yes | No: page N+1 needs page N's cursor |
| Typical APIs | REST admin lists, search results | Social feeds, GraphQL connections, Stripe, Slack |

**How PageKit unifies them.** Every page response becomes the same shape: a list of items plus an optional next token. If the next token is `nil`, the list has ended.

```swift
public struct Page<Item, Token> {
    public let items: [Item]
    public let nextToken: Token?   // nil means "no more pages"
}
```

- For an index API, the token is a small struct, `IndexToken(page: 3, size: 20)`, and the *client* builds the next one.
- For a cursor API, the token is `CursorToken(value: "eyJpZ...")`, and the *server* supplies the next one.

Because the engine only ever asks "is there a next token, and what is it?", the same code drives both styles. This is the single most important design decision in the library.

**Fixing drift for index APIs.** PageKit removes duplicates by `id` when it appends a page (FR-7). It keeps a `Set` of seen IDs, so the check costs O(1) per item. Gaps from deletions cannot be fixed on the client; the docs recommend a cursor API when the backend allows it.

## 5. High-level architecture

The library stops at one public type, the `Paginator` actor; everything above it (screens, view models, spinners, footers) is app code. Below it sit three data layers that the engine reads in a fixed order.

&#91;embedded content: PageKit architecture · UI, engine, three data layers\]

A request for a page tries memory first, then disk, then the network; every page that comes from the network is written back to both caches.

- **Your screen (app code)** can be SwiftUI, UIKit or AppKit. It knows nothing about tokens or caches; it draws items and a footer for the current state.
- **Your view model (app code)** is a small `@MainActor` class the app writes. It listens to `paginator.snapshots`, stores the latest snapshot for the screen, and forwards user events (item appeared, pull to refresh, retry tapped) to the paginator. Section 18 shows complete examples.
- **Paginator (library)** is the brain and the whole public API, isolated in an actor. It owns the page order and next token, de-duplicates requests, applies the cache policy and retries, decides when to prefetch, and emits snapshots.
- **The data layers (library)** each do one job. `MemoryPageCache` makes repeat reads instant and `DiskPageStore` survives relaunches and offline. `PageSource` is the protocol the app implements to fetch one page.
- **Connectivity (library)** feeds online and offline events to the paginator, which uses them to set `isOffline` and to resume loading.

This separation is the dependency rule of the library: arrows only point down, and nothing in the package imports SwiftUI, UIKit or AppKit. That is why it can be unit-tested without a simulator, used from a widget or a watch app, and adopted by apps with any UI architecture (MVVM, TCA, MVC).

## 6. Public API design

The app writes one small type, a `PageSource`, that knows how to fetch a single page. PageKit does everything else. Keeping the public surface this small is what makes the library easy to adopt and hard to misuse.

**Step 1: tokens.** A token is anything that is `Hashable` (so it can be a dictionary key for in-flight requests and cache keys), `Codable` (so it can be saved to disk) and `Sendable` (so it can cross threads safely).

```swift
public protocol PageToken: Hashable, Codable, Sendable {}

/// Index-based: the client works out the next page.
public struct IndexToken: PageToken {
    public let page: Int        // 1-based
    public let size: Int        // items per page
    public var offset: Int { (page - 1) * size }
    public var next: IndexToken { IndexToken(page: page + 1, size: size) }
    public static func first(size: Int = 20) -> IndexToken { IndexToken(page: 1, size: size) }
}

/// Cursor-based: the server hands back the next cursor.
public struct CursorToken: PageToken {
    public let value: String?   // nil means "first page"
    public let size: Int
}
```

Apps can also define their own token, for example a cursor plus a search query, just by conforming to `PageToken`.

**Step 2: the page source.** This is the only protocol most apps implement. It uses Swift's primary associated types, so the engine is generic over *any* item and *any* token without type erasure.

```swift
public protocol PageSource<Item, Token>: Sendable {
    associatedtype Item: Identifiable & Codable & Sendable where Item.ID: Codable & Sendable
    associatedtype Token: PageToken

    /// A stable, unique name for this list, e.g. "products.home" or "search.shoes".
    /// Used as the cache key, so two lists never overwrite each other.
    var feedID: String { get }

    /// The token for the very first page.
    var firstToken: Token { get }

    /// Fetch one page. Throw on failure; PageKit handles retries and caching.
    func loadPage(_ token: Token) async throws -> Page<Item, Token>
}
```

Why each constraint exists:

- `Identifiable`: needed to remove duplicates and to give SwiftUI and diffable data sources stable identity, which is what keeps scrolling smooth.
- `Codable`: needed to write pages to disk for offline use.
- `Sendable`: needed because items are loaded on a background task and shown on the main actor.

**Step 3: write a source.** Index-based example:

```swift
struct ProductsSource: PageSource {
    let api: APIClient
    let feedID = "products.home"
    let firstToken = IndexToken.first(size: 20)

    func loadPage(_ token: IndexToken) async throws -> Page<Product, IndexToken> {
        let response = try await api.products(page: token.page, limit: token.size)
        let isLastPage = response.items.count < token.size
        return Page(items: response.items, nextToken: isLastPage ? nil : token.next)
    }
}
```

Cursor-based example:

```swift
struct TimelineSource: PageSource {
    let api: APIClient
    let feedID = "timeline"
    let firstToken = CursorToken(value: nil, size: 25)

    func loadPage(_ token: CursorToken) async throws -> Page<Post, CursorToken> {
        let response = try await api.timeline(after: token.value, limit: token.size)
        let next = response.nextCursor.map { CursorToken(value: $0, size: token.size) }
        return Page(items: response.posts, nextToken: next)
    }
}
```

**Step 4: configure behaviour.** Every knob has a safe default, so most apps pass nothing.

```swift
public enum CachePolicy: Sendable {
    case networkOnly        // never read cache (e.g. live prices)
    case cacheOnly          // never hit the network (e.g. offline mode)
    case networkFirst       // try the network, fall back to cache on failure
    case cacheThenNetwork   // show cache instantly, then refresh (default)
}

public struct PaginationConfiguration: Sendable {
    public var cachePolicy: CachePolicy = .cacheThenNetwork
    public var prefetchDistance = 5                  // start loading 5 items before the end
    public var lookaheadPages = 1                    // pages to read ahead in the background
    public var memoryCostLimit = 20 * 1024 * 1024    // bytes for NSCache
    public var diskSizeLimit = 50 * 1024 * 1024      // bytes on disk
    public var maxAge: TimeInterval = 7 * 24 * 3600  // disk entries older than this are deleted
    public var retry = RetryPolicy.default
    public var schemaVersion = 1                     // bump when Item's shape changes
    public var storage = DiskStorage.caches          // or .durable for guaranteed offline
}
```

**Step 5: drive it through the Paginator.** The `Paginator` actor is the only type the app talks to. Its signatures contain no UI types: state goes out through an `AsyncStream`, and user intent comes in through async methods.

```swift
public actor Paginator<Source: PageSource> {
    public init(source: Source,
                configuration: PaginationConfiguration = .init(),
                connectivity: any ConnectivityMonitoring = NetworkPathMonitor())

    /// A new stream on every call. It starts with the current snapshot, then every change.
    /// Any number of observers may listen at once; each stream ends on cancel().
    public nonisolated func snapshots() -> AsyncStream<PaginationSnapshot<Source.Item>>

    public func start()                              // begins loading and returns at once; results arrive on snapshots()
    public func loadNextPage() async                 // no-op unless state is .loaded(hasMore: true)
    public func itemAppeared(id: Source.Item.ID)     // prefetch hook, O(1)
    public func prefetch(upToIndex index: Int)       // prefetch hook for index-path based UIs
    public func refresh() async                      // reload from the first page
    public func retry() async                        // repeat the last failed load
    public func remove(id: Source.Item.ID) async     // local edits, kept in sync with both caches
    public func update(_ item: Source.Item) async
    public func cancel()                             // stop all in-flight work
}

public struct PaginationSnapshot<Item: Identifiable & Sendable>: Sendable {
    public let items: [Item]
    public let state: PaginationState
    public let isStale: Bool      // showing cached data while a refresh is in flight
    public let isOffline: Bool
}
```

**Why an AsyncStream and not ObservableObject or @Observable.** Those exist to serve SwiftUI. An `AsyncStream` is plain Swift concurrency, so a SwiftUI view model, a UIKit view controller, a TCA reducer and a unit test all consume it the same way. The app wraps it in whatever its architecture prefers; section 18 shows complete SwiftUI and UIKit versions.

## 7. The Paginator engine and its state machine

The engine is a small state machine: the list is always in exactly one named state, and only the **Loaded** state is allowed to start the next page. This single rule is what prevents duplicate loads, loads after the end, and retry storms after an error.

&#91;embedded content: Pagination state machine · 9 states\]

A next page returns to Loaded when it arrives; both error states go back to loading only when the user or the auto-retry asks.

```swift
public enum PaginationState: Equatable, Sendable {
    case idle
    case loadingFirstPage
    case loaded(hasMore: Bool)          // hasMore == false means end of list
    case loadingNextPage
    case refreshing
    case empty
    case failed(PaginationError, isFirstPage: Bool)

    /// The only state from which a next-page load may start.
    var canLoadMore: Bool { self == .loaded(hasMore: true) }
}
```

Why an enum instead of several booleans (`isLoading`, `hasError`, `isEnd`): three booleans allow eight combinations, and most of them are nonsense, such as loading *and* ended. An enum makes impossible states impossible to represent, and the `switch` in the UI must handle every case or it will not compile.

**Offline is a flag, not a state.** Being offline can overlap with any state: you can be offline and Loaded (showing cached pages) or offline and in First-page error (nothing cached). So the snapshot carries `isOffline` alongside the state rather than adding it to the enum.

**What the engine does when a page arrives**, in order:

1. Check the generation number; drop the page if a refresh happened meanwhile.
2. Remove items whose IDs are already in the list.
3. Append the rest and record the page's token in the page order.
4. Store the page in memory and write it to disk, without waiting for the disk.
5. Set the state to `.loaded(hasMore: nextToken != nil)`.
6. Emit one snapshot on the snapshots stream; the app's view model receives it on the main actor.
7. If read-ahead is enabled and allowed, start loading the following page into the cache.

## 8. Networking and data loading

PageKit does not own your networking; it calls your `PageSource` and wraps every call with de-duplication, cancellation, retry and caching. Apps already have an API client with auth headers, token refresh and logging. Forcing them to replace it would block adoption, so the library stays on the far side of one async function.

**De-duplicating requests (FR-6).** Prefetching, fast scrolling and `onAppear` can all ask for the same page within milliseconds. The engine keeps a dictionary of in-flight tasks keyed by token. A second request for the same token simply waits for the first one's result.

```swift
actor Paginator<Source: PageSource> {
    private var inFlight: [Source.Token: Task<Page<Source.Item, Source.Token>, Error>] = [:]

    func fetch(_ token: Source.Token) async throws -> Page<Source.Item, Source.Token> {
        if let existing = inFlight[token] {
            return try await existing.value          // join the request already running
        }
        let task = Task { try await withRetry(policy) { try await source.loadPage(token) } }
        inFlight[token] = task
        defer { inFlight[token] = nil }
        return try await task.value
    }
}
```

Because `Paginator` is an actor, reading and writing `inFlight` is serialised automatically. No locks are needed.

**Dropping stale responses.** If the user pulls to refresh while page 4 is still loading, page 4 belongs to the old list and must not be appended to the new one. The engine keeps a `generation` number. Refresh increments it and cancels in-flight tasks. When a response arrives, the engine compares the generation it started with against the current one and throws the result away if they differ. Cancelling alone is not enough, because a request can finish in the instant between cancel and check.

**Keeping work off the main thread.** `loadPage` is called from the `Paginator` actor, which runs on Swift's background thread pool. JSON decoding, de-duplication and disk writes all happen there. Only the final, ready-to-display array crosses to the main actor. (On Swift 6.2 with *nonisolated(nonsending)* enabled, mark heavy helper functions `@concurrent` so they do not inherit the caller's actor.)

**Optional built-in source (FR-20).** For simple JSON APIs, PageKit ships a generic `URLSessionPageSource`, so an app can paginate without writing a type at all.

```swift
let source = URLSessionPageSource(
    feedID: "articles",
    firstToken: CursorToken(value: nil, size: 20),
    request: { token in
        var components = URLComponents(string: "https://api.example.com/articles")!
        components.queryItems = [URLQueryItem(name: "limit", value: "\(token.size)")]
        if let cursor = token.value { components.queryItems?.append(URLQueryItem(name: "after", value: cursor)) }
        return URLRequest(url: components.url!)
    },
    map: { (response: ArticlesResponse, token) in
        Page(items: response.data,
             nextToken: response.next.map { CursorToken(value: $0, size: token.size) })
    }
)
```

Inside, it does four things and nothing more:

1. Builds the `URLRequest` from the token, and sets `cachePolicy = .reloadIgnoringLocalCacheData`. PageKit owns caching; letting `URLCache` cache the same JSON again would waste disk and cause confusing stale reads.
2. Calls `URLSession.data(for:)` with a 15-second request timeout, so an offline device falls back to the disk cache quickly instead of hanging.
3. Checks the HTTP status. 2xx decodes; 429 and 5xx throw a retryable error that carries the `Retry-After` header; other 4xx throw a permanent error.
4. Decodes with `JSONDecoder` and calls the app's `map` closure to turn the response into a `Page`.

## 9. In-memory caching with NSCache

The memory cache holds already-decoded pages in an `NSCache`, so returning to a feed, or rebuilding it after a refresh fails, costs no network, no disk read and no JSON decoding. It is the first layer checked on every read; disk is second and the network is last.

**Why NSCache and not a Dictionary.** A plain `[Key: Page]` grows until the app is killed. NSCache gives us four things for free:

- It **evicts automatically** when the system is short of memory, before iOS has to terminate the app.
- It respects a **cost limit** (`totalCostLimit`) and a **count limit** (`countLimit`) that we set.
- It is **thread-safe** on its own: reads and writes from any thread are fine without extra locks.
- It does **not copy keys**, unlike `NSMutableDictionary`, so it is cheap.

The price is that NSCache can drop any entry at any moment, without warning. So the rule is: **memory is a speed-up, never the source of truth.** Every read that misses memory falls through to disk.

**Why not URLCache.** `URLCache` stores raw HTTP bytes. Every hit would need decoding again, which is exactly the main-thread spike we want to avoid. It also only works for GET requests with cache headers, and many APIs (GraphQL over POST) have neither.

**What we store.** NSCache needs class types for both keys and values, so we wrap them:

```swift
/// NSCache only stores reference types, so a page is boxed in a class.
/// It also remembers its own key and feed, because NSCache's eviction
/// callback hands us the object, not the key.
final class CachedPage<Item: Sendable, Token: PageToken> {
    let page: Page<Item, Token>
    let feedID: String
    let key: NSString
    let storedAt: Date

    init(page: Page<Item, Token>, key: PageKey, storedAt: Date = .now) {
        self.page = page
        self.feedID = key.feedID
        self.key = key.nsKey
        self.storedAt = storedAt
    }
}

/// A cache key is the feed name plus a stable string for the token.
struct PageKey: Hashable, Sendable {
    let feedID: String
    let token: String      // JSON of the token with sorted keys, so it is always identical
    var nsKey: NSString { "\(feedID)|\(token)" as NSString }
}
```

**The cache itself.**

```swift
/// @unchecked Sendable is safe here because NSCache is internally synchronised
/// and `keys` is only touched while holding `lock`.
final class MemoryPageCache<Item: Sendable, Token: PageToken>: NSObject, NSCacheDelegate, @unchecked Sendable {
    private let cache = NSCache<NSString, CachedPage<Item, Token>>()
    private let lock = NSLock()
    private var keys: [String: Set<NSString>] = [:]   // feedID -> keys, so we can clear one feed

    init(costLimit: Int, countLimit: Int = 200) {
        super.init()
        cache.totalCostLimit = costLimit
        cache.countLimit = countLimit
        cache.name = "PageKit.MemoryPageCache"
        cache.delegate = self
    }

    func page(for key: PageKey) -> CachedPage<Item, Token>? {
        cache.object(forKey: key.nsKey)
    }

    func store(_ page: Page<Item, Token>, for key: PageKey, cost: Int) {
        cache.setObject(CachedPage(page: page, key: key), forKey: key.nsKey, cost: cost)
        lock.withLock { keys[key.feedID, default: []].insert(key.nsKey) }
    }

    func removeFeed(_ feedID: String) {
        let feedKeys = lock.withLock { keys.removeValue(forKey: feedID) ?? [] }
        feedKeys.forEach { cache.removeObject(forKey: $0) }
    }

    func removeAll() {
        cache.removeAllObjects()
        lock.withLock { keys.removeAll() }
    }

    // Called by NSCache when it evicts on its own (memory pressure, limits).
    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let evicted = obj as? CachedPage<Item, Token> else { return }
        lock.withLock { _ = keys[evicted.feedID]?.remove(evicted.key) }
    }
}
```

Three decisions in this code are worth explaining:

1. **Cost is real bytes, not a guess.** We encode each page to JSON anyway for the disk cache, so we pass `data.count` as the cost. The 20 MB limit then means roughly 20 MB of content, not an arbitrary number of pages.
2. **We track keys ourselves.** NSCache cannot list its keys, so clearing "just the search feed" would be impossible. A small `[feedID: Set<NSString>]` index, protected by a lock, fixes that.
3. **The delegate keeps the index honest.** When NSCache evicts an entry on its own, `cache(_:willEvictObject:)` fires and we remove the key from the index. Without this the index would slowly fill with keys that point at nothing. The callback gives us the evicted object, not its key, which is why \`CachedPage\` stores its own key and feed.

**How this helps smooth scrolling.** Honest answer for the interview: the cache is not what makes a single scroll smooth; never blocking the main thread is. What the cache does is remove the *pauses around* scrolling: going back to a feed shows it instantly, scrolling back up to pages that were trimmed from memory (see section 14) restores them without a decode, and a failed refresh still has data to show.

## 10. Offline support and disk persistence

Every page that loads from the network is also written to disk as a JSON file, so the feed opens instantly on the next launch and stays readable with no connection. NSCache alone cannot do this: it lives in RAM and is empty after every launch.

**Why plain JSON files and not Core Data or SwiftData.** A page is written once, read whole and never queried by field. Files are the simplest store that fits that pattern, need no schema migrations, work on every platform version we support and add no framework weight. Core Data would buy features (queries, relationships) the library never uses.

**Where the files live.**

- Default: `Library/Caches/PageKit/<feed>/`. iOS may delete this folder when the device runs low on space, which is acceptable for a cache, and it is never backed up.
- Opt-in `.durable` storage: `Library/Application Support/PageKit/<feed>/`, for apps that promise offline reading. PageKit sets `isExcludedFromBackup = true` on it, because cached server data should not use the user's iCloud quota.
- Files are written with `.atomic` (so a crash never leaves half a file) and `.completeFileProtectionUntilFirstUserAuthentication` (encrypted until the user first unlocks the phone, but still readable by background refresh).

**What is on disk.** One manifest per feed plus one file per page:

```
PageKit/
  products.home/
    manifest.json          <- page order, last next-token, timestamps, schema version
    page-3f9a1c.json       <- page 1 (file name = SHA-256 of the token)
    page-b7720e.json       <- page 2
```

```swift
/// The order pages were loaded in. Needed for cursor feeds, where you cannot
/// work out page 3's token without page 2's response.
struct FeedManifest<Token: PageToken>: Codable {
    var schemaVersion: Int
    var tokens: [Token]
    var lastNextToken: Token?      // where to continue from
    var updatedAt: Date
}

struct StoredPage<Item: Codable, Token: PageToken>: Codable {
    let schemaVersion: Int
    let storedAt: Date
    let items: [Item]
    let nextToken: Token?
}
```

File names use a SHA-256 hash of the token (via CryptoKit, which ships with iOS) because cursors can contain characters such as `/` that are illegal in file names.

**Disk access is an actor.** `DiskPageStore` is an actor, so all reads and writes to a feed's folder happen one at a time and never on the main thread. Writes are fire-and-forget: the UI does not wait for the disk.

**Model changes between app versions.** If a new app version renames a field on `Product`, old files will no longer decode. The app sets `configuration.schemaVersion`; when it does not match the manifest, PageKit deletes that feed's folder and starts clean. A single file that fails to decode for any other reason is deleted and treated as a cache miss. A broken cache must never crash the app or block the network.

**Knowing when we are offline.** PageKit uses `NWPathMonitor` from Apple's Network framework, wrapped behind a protocol so tests can fake it.

```swift
public protocol ConnectivityMonitoring: Sendable {
    func updates() -> AsyncStream<Bool>      // true = online
}

public struct NetworkPathMonitor: ConnectivityMonitoring {
    public func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in continuation.yield(path.status == .satisfied) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "PageKit.connectivity"))
        }
    }
}
```

Important subtlety: PageKit **does not skip a request because the monitor says offline**. Apple's own guidance is to always try the request, because path status can be wrong (captive portals, VPNs, a network that just came back). The monitor is used for two things only: labelling the UI as offline, and automatically retrying when the status flips back to online (FR-16).

**Offline behaviour, step by step.**

1. The screen opens. PageKit reads the manifest and shows the cached pages at once, marked as stale.
2. It tries the network for page 1. The request fails with `URLError.notConnectedToInternet`.
3. The snapshot's `isOffline` flag turns on. Cached items stay in the snapshot, and the app can show a banner such as "You're offline. Showing saved items."
4. The user scrolls to the end of the cached pages. If the next page is on disk, it is served from disk. If not, the footer shows "Connect to load more" instead of a spinner.
5. Connectivity returns. PageKit silently refreshes page 1, then retries whatever the footer was waiting for.

## 11. Prefetching

Prefetching starts the next page while the user still has a few items left to read, so in normal use they never see a spinner. PageKit does this at two levels: a **trigger** that fetches the next page when the user gets close to the end, and an optional **read-ahead** that quietly loads one more page into the cache.

&#91;embedded content: Prefetch window · distance trigger and one page of read-ahead\]

The user is still reading page 2 when they enter its last five items; page 3 is already cached, so it appears with no spinner.

**Level 1: the distance trigger.** When an item appears on screen, PageKit checks how far it is from the end of the list. If it is within `prefetchDistance` items (default 5), it asks for the next page.

```swift
// Inside the Paginator actor: library code, no UI types.
public func itemAppeared(id: Source.Item.ID) {
    // O(1) lookup. Scanning items with firstIndex(where:) on every
    // cell appearance would cause jank on long feeds.
    guard let index = indexByID[id] else { return }
    prefetch(upToIndex: index)
}

public func prefetch(upToIndex index: Int) {
    guard index >= items.count - configuration.prefetchDistance else { return }
    guard state.canLoadMore else { return }   // not already loading, not ended, not failed
    nextPageTask = Task { await loadNextPage() }
}
```

Why count items instead of measuring scroll offset: it works for every layout (lists, grids, carousels, variable-height cells) and in SwiftUI, which has no simple scroll-offset API before iOS 17. It also does not need to know cell heights.

**UIKit gets a better signal.** `UICollectionViewDataSourcePrefetching` tells us which index paths the system expects to show soon, often several screens ahead. A UIKit app forwards the highest one from its own view controller. This is app code; the library only receives the index:

```swift
func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
    guard let furthest = indexPaths.map(\.item).max() else { return }
    Task { await paginator.prefetch(upToIndex: furthest) }
}
```

We deliberately ignore `cancelPrefetchingForItemsAt`. Cancelling a page load because the user flicked back up wastes the bytes already downloaded, and they will almost certainly need that page soon.

**Level 2: read-ahead.** After page N is shown, PageKit can fetch page N+1 in the background and park it in the memory and disk caches, *without* adding it to the visible list. When the trigger fires later, page N+1 comes from memory in under a millisecond and is appended with no network wait. `lookaheadPages` (default 1) controls how far ahead it goes.

- For **cursor** feeds, read-ahead is strictly one page at a time, because page N+1's cursor only exists once page N has arrived.
- For **index** feeds, pages can be read ahead in parallel, capped at two concurrent requests so we do not flood the server.

**When PageKit will not prefetch.** Aggressive prefetching costs data and battery, so there are guard rails:

- Read-ahead is switched off when the network path is `isConstrained` (Low Data Mode) or `isExpensive` (cellular or personal hotspot), unless the app opts in. The distance trigger still runs, because the user is actively asking for more.
- No prefetch while the list is in an error state. Otherwise a broken endpoint would be hit again on every cell appearance, a retry storm.
- No prefetch once the end of the list is reached (`nextToken == nil`).
- No prefetch while the app is in the background.

**Appending without a stutter.** A new page is appended as one batch, which reaches the app as one snapshot, so the app makes one SwiftUI update or one diffable-data-source apply, not twenty. The diffing itself is cheap because items are `Identifiable` (see section 14).

## 12. Cache clearing and invalidation

A cache that never forgets shows wrong data and eats storage, so PageKit clears data on seven well-defined triggers, and it only deletes old data *after* new data has arrived. That ordering is what guarantees a failed refresh never leaves the user with an empty screen.

| Trigger | Memory (NSCache) | Disk | Who starts it |
| --- | --- | --- | --- |
| Memory pressure | NSCache evicts on its own | Untouched | iOS |
| Cost or count limit reached | Oldest-used entries evicted | Untouched | NSCache |
| Pull-to-refresh succeeds | Feed's pages replaced | Feed's pages replaced, manifest rewritten | User |
| Entry older than `maxAge` (7 days) | Ignored on read | Deleted in the maintenance sweep | PageKit |
| Disk over `diskSizeLimit` (50 MB) | Untouched | Least recently used feeds deleted down to 80% of the limit | PageKit |
| `schemaVersion` changed | Feed cleared | Feed folder deleted | App update |
| Logout or account switch | Everything cleared | Everything deleted | App calls `clearAll()` |

**Refresh, in detail.** This is the trigger most likely to go wrong, so the order matters:

1. Increment the generation number and cancel in-flight page loads (section 8).
2. Fetch page 1 from the network, ignoring the cache.
3. **If it fails:** keep every existing item, show a non-blocking error, stop. Nothing is deleted.
4. **If it succeeds:** replace the visible list with page 1, then delete that feed's later pages from memory and disk, then write the new page 1 and a new manifest.

Step 4 throws away later pages because, for a cursor feed, the old cursors describe the *old* ordering. Mixing them with a fresh page 1 creates duplicates and gaps. For index feeds the reason is drift: page 2 from an hour ago no longer follows page 1 from now.

**Why delete down to 80%, not 100%.** If the sweep stopped exactly at the 50 MB limit, the very next write would push it over again, and the sweep would run after every page. Stopping at 40 MB leaves headroom. This is called *hysteresis*.

**Why delete whole feeds, not single pages.** Deleting page 2 of a cursor feed but keeping page 3 leaves a hole you cannot fill: page 3 is useless without the chain before it. So eviction works on the whole feed, oldest `manifest.updatedAt` first.

**Changing one item (FR-17).** When the user deletes or edits a post, the app tells PageKit, and the change lands everywhere at once:

```swift
await paginator.remove(id: post.id)     // removes from the snapshot, the memory page and the disk page
await paginator.update(editedPost)      // replaces in place, same position
```

PageKit keeps a small `[Item.ID: Token]` map that says which page each item came from, so it rewrites only that one page file.

**The public clearing API.**

```swift
public enum PageKit {
    /// Remove one feed from memory and disk, e.g. when a search query changes.
    public static func clear(feedID: String) async

    /// Remove every feed. Call on logout, and await it before showing the login screen,
    /// so the next user never sees the previous user's data.
    public static func clearAll() async

    /// Delete expired files and enforce the size limit. Runs automatically once per launch
    /// at background priority; apps can also call it from a BGAppRefreshTask.
    public static func performMaintenance() async
}
```

The maintenance sweep runs at `.background` task priority, a few seconds after the first feed opens, so it never competes with the work the user is waiting for.

## 13. Concurrency and thread safety

PageKit uses Swift concurrency's actors instead of locks and dispatch queues, and it compiles with zero warnings under Swift 6 strict concurrency. Each component has exactly one owner, so data races are prevented by the compiler rather than by careful reviewing.

| Component | Owner | Isolation | Why |
| --- | --- | --- | --- |
| Your view model | App | `@MainActor` | It holds what the UI reads, and UI must be updated on the main thread. The library never touches the main thread itself. |
| `Paginator` | Library | `actor` | Owns the page tokens, in-flight tasks and generation number. Serialises all decisions about what to load next. |
| `DiskPageStore` | Library | `actor` | File reads and writes for a feed happen one at a time, so two writes never interleave. |
| `MemoryPageCache` | Library | Class, `@unchecked Sendable` | NSCache is already thread-safe; the key index is guarded by an `NSLock`. An actor here would add an `await` to every cache hit for no benefit. |
| `Page`, tokens, items, snapshots | Both | `Sendable` value types | Safe to pass between all of the above. |

**The reentrancy trap.** An actor runs one piece of code at a time, but every `await` is a pause where *other* calls can run. So state read before an `await` can be out of date after it. Example: the paginator checks "not loading", awaits the network, and meanwhile a refresh has reset the list. PageKit's rule: **after every `await`, re-check the generation and the state before changing anything.**

```swift
func loadNextPage() async {
    guard case .loaded(let next?) = state else { return }
    let generation = self.generation
    state = .loadingMore

    let result: Result<Page<Source.Item, Source.Token>, Error>
    do { result = .success(try await fetch(next)) } catch { result = .failure(error) }

    // The world may have changed while we were waiting.
    guard generation == self.generation, !Task.isCancelled else { return }
    apply(result)
}
```

**Cancellation.** In SwiftUI, the `.task` modifier cancels its task when the view disappears; that cancellation flows into `URLSession`, which stops the download. The app's view model calls `paginator.cancel()` in `deinit`, which also finishes the `snapshots` stream. Cancellation is a quiet no-op, never an error the user sees.

**Only one hop to the main thread per page.** The paginator builds the complete new item array (merged, de-duplicated) off the main thread and emits it as one snapshot. The app's view model assigns it on the main actor in one step, so the main thread never loops over items.

## 14. Smooth scrolling: what the library guarantees and what the app must do

A scroll stays smooth when the main thread finishes each frame in under 8 ms (120 Hz) or 16 ms (60 Hz). Because PageKit has no UI, smoothness is a shared contract: the library guarantees that the data side never costs the main thread anything, and the app's UI code must not waste that budget.

**What the library guarantees.**

1. **No I/O or decoding on the main thread.** Network, JSON and disk all run on actors (section 13).
2. **One snapshot per change.** Items, state and flags change together in one value, so the app can update its UI once per page, not once per property.
3. **Stable, de-duplicated identity.** Every item in a snapshot has a unique `id`, so the app can diff old and new lists in linear time and reuse existing cells.
4. **O(1) prefetch hooks.** `itemAppeared(id:)` is a dictionary lookup (section 11).
5. **The next page is usually already there.** Prefetch and read-ahead mean the user rarely reaches the end before data arrives.

**What the app's UI must do** (full code in section 18).

| Do | Don't | Why |
| --- | --- | --- |
| Store the whole snapshot in one `@Published` or `@Observable` property | Copy `items` and `state` into separate properties | Two properties cause two renders per page. |
| Use `List`, `LazyVStack` or `UICollectionView` | Use a plain `VStack` in a `ScrollView` | A plain stack builds every row up front. |
| Key rows by `item.id` | Write `.id(UUID())` or key by array index | A new identity on each render throws the cell away and rebuilds it. |
| In UIKit, put IDs in the diffable snapshot and call `reconfigureItems` for edits | Put whole items in the diffable snapshot | Diffing small IDs is cheaper; reconfigure updates the existing cell instead of replacing it. |
| Apply appended pages with `animatingDifferences: false` | Animate 20 inserted rows at the bottom | The animation costs frames and the user cannot see it. |
| Load images asynchronously with the app's own image pipeline | Decode images in the row's `body` or `cellForItemAt` | Image decoding is the most common cause of scroll hitches. |
| Keep the loading footer as its own row driven by `state` | Insert a fake "loading" item into the item array | A fake item breaks identity and diffing. |

**Very long feeds: memory windowing (version 2).** A user who scrolls 5,000 items deep keeps 5,000 items in RAM. The planned `maxResidentPages` option lets the paginator drop far-away pages from the snapshot and restore them from NSCache, or from disk if NSCache evicted them, when the app reports that the user is scrolling back up through `prefetch(upToIndex:)`. This is where the memory cache directly protects scrolling. It stays off by default because most feeds never get that long.

## 15. Error handling and retries

PageKit sorts every failure into retryable or permanent, retries the retryable ones automatically with exponential backoff, and never lets an error remove items that are already on screen.

```swift
public enum PaginationError: Error, Sendable {
    case offline                          // URLError.notConnectedToInternet, .networkConnectionLost
    case timedOut
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)              // 5xx
    case client(status: Int)              // 4xx other than 429
    case decoding(underlying: String)
    case other(underlying: String)
}
```

| Error | Retried automatically? | Why |
| --- | --- | --- |
| Offline | No; waits for connectivity, then retries | Retrying with no network only burns battery. |
| Timed out | Yes | Usually a slow or busy network; a second try often works. |
| Rate limited (429) | Yes, after `Retry-After` | The server told us exactly when to come back. |
| Server (5xx) | Yes | Often a short outage or a deploy in progress. |
| Client (4xx) | No | The request itself is wrong (bad auth, bad parameter); repeating it gives the same answer. |
| Decoding | No | The response shape does not match the model. Retrying changes nothing; it is logged for the developer. |
| Cancelled | Not an error | The user left the screen or refreshed. Nothing is shown. |

**Exponential backoff with jitter.** Each retry waits longer than the last: 0.5 s, then 1 s, then 2 s, capped at 8 s. A random factor ("jitter") between 50% and 100% of that delay is applied, so that a thousand phones that lost signal in the same tunnel do not all hit the server in the same millisecond when they come out.

```swift
public struct RetryPolicy: Sendable {
    public var maxAttempts = 3
    public var baseDelay: TimeInterval = 0.5
    public var maxDelay: TimeInterval = 8

    func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponential = min(maxDelay, baseDelay * pow(2, Double(attempt)))
        return exponential * Double.random(in: 0.5...1.0)
    }
}
```

The wait uses `Task.sleep`, which ends early if the task is cancelled, so leaving the screen mid-backoff stops the retries at once. In tests, the sleep function is injected and returns immediately, so retry tests run in milliseconds.

**What the app should show depends on where the error happened. The library reports it in the snapshot; the app's UI decides how to present it.**

- **First page, nothing cached:** full-screen error view with a Retry button.
- **First page, cache available:** cached items stay; a small "Couldn't refresh" banner appears.
- **Next page:** items stay; the footer turns into "Couldn't load more. Tap to retry."
- **Pull-to-refresh:** items stay; the refresh control ends and a short message appears.

**Logging.** Errors are logged with `os.Logger` under the subsystem `PageKit`, with URLs marked `.private`, so developers can filter them in Console.app without leaking user data into system logs.

## 16. Testing and validation

Every requirement in sections 2 and 3 maps to at least one automated test, written with Apple's Swift Testing framework (built into Xcode 16), so the design is validated by CI on every pull request, not by opinion. Because the network, disk, clock and connectivity all sit behind protocols, almost every test runs in memory in milliseconds.

**Test doubles.**

```swift
struct MockSource: PageSource {
    let feedID = "test"
    let firstToken = IndexToken.first(size: 2)
    let handler: @Sendable (IndexToken) async throws -> Page<TestItem, IndexToken>

    func loadPage(_ token: IndexToken) async throws -> Page<TestItem, IndexToken> {
        try await handler(token)
    }
}
```

Others: an in-memory `DiskPageStore` backed by a temporary folder, a `FakeConnectivity` whose online flag a test can flip, and an instant `sleep` for retries. For the built-in `URLSessionPageSource`, a `URLProtocol` subclass intercepts requests and returns canned responses, which is Apple's own way to fake the network without a server.

**Example: the de-duplication guarantee (FR-6).**

```swift
@Test func concurrentRequestsForSamePageHitTheNetworkOnce() async throws {
    let calls = Counter()   // a tiny actor
    let source = MockSource { _ in
        await calls.increment()
        try await Task.sleep(for: .milliseconds(50))
        return Page(items: [TestItem(id: 1)], nextToken: nil)
    }
    let paginator = Paginator(source: source, configuration: .testing)

    async let first = paginator.fetch(source.firstToken)
    async let second = paginator.fetch(source.firstToken)
    _ = try await (first, second)

    #expect(await calls.value == 1)
}
```

**Requirement traceability.** This table is the validation: each line is a test that must pass before a release.

| Requirement | Test | What it proves |
| --- | --- | --- |
| FR-2 | `stopsWhenNextTokenIsNil` | No request is made after the last page. |
| FR-3, FR-4 | `indexAndCursorSourcesProduceSameStates` | One engine drives both styles identically. |
| FR-6 | `concurrentRequestsForSamePageHitTheNetworkOnce` | In-flight de-duplication works. |
| FR-7 | `duplicateIDsAcrossPagesAreDropped` | Index drift does not show duplicate rows. |
| FR-8 | `staleResponseAfterRefreshIsDiscarded` | Generation check drops old pages. |
| FR-9 | `secondOpenServesFromMemoryWithoutCallingSource` | Memory cache hit path. |
| FR-10 | `offlineLaunchShowsDiskPages` | Disk cache and offline state. |
| FR-11 | `appearingWithinDistanceTriggersNextPage` | Prefetch threshold. |
| FR-13 | `serverErrorRetriesThreeTimesThenFails` | Backoff policy and attempt count. |
| FR-15 | `failedRefreshKeepsOldPagesOnDisk` | Delete only after success. |
| FR-15 | `sweepDeletesLeastRecentFeedsToEightyPercent` | Size limit and hysteresis. |
| FR-16 | `reconnectRetriesPendingNextPage` | Auto-resume on connectivity. |
| NFR memory | `memoryWarningEmptiesCacheButNotList` | NSCache gives memory back; UI unaffected. |
| NFR safety | CI builds with `-strict-concurrency=complete` | No data races. |

**Performance validation.**

- A UI test scrolls the sample app's 2,000-item feed and records `XCTOSSignpostMetric.scrollDecelerationMetric` and `scrollDraggingMetric`; CI fails if the hitch ratio regresses by more than 10% against the stored baseline.
- PageKit emits `OSSignposter` intervals for fetch, decode, disk write and main-actor apply, so a developer can see each one in Instruments' Points of Interest track.
- The sample app has a **chaos mode**: random latency up to 3 s, a 20% failure rate, and an offline toggle. It is the quickest way to see every state of the footer by hand.

## 17. Open-source packaging, docs and versioning

PageKit ships as a Swift Package with a single product, `PageKit`, that imports only Foundation, Network and CryptoKit. There is no UI module: a widget extension, a watch app, a command-line tool or any UI framework can use the engine and caches unchanged. All UI lives in the example app, clearly labelled as app code.

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PageKit",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8)],
    products: [
        .library(name: "PageKit", targets: ["PageKit"]),
    ],
    dependencies: [],   // zero third-party code, by design
    targets: [
        .target(name: "PageKit", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "PageKitTests", dependencies: ["PageKit"]),
    ]
)
```

**Repository layout.**

```
PageKit/
  Sources/
    PageKit/            Tokens, Page, PageSource, Paginator, caches, connectivity (no UI)
      PageKit.docc/     DocC catalogue: articles and a step-by-step tutorial
  Tests/
    PageKitTests/
  Examples/
    PageKitDemo/        App code only: SwiftUI and UIKit screens, view models,
                        index feed, cursor feed, search, offline and chaos modes
  README.md  CHANGELOG.md  CONTRIBUTING.md  CODE_OF_CONDUCT.md  LICENSE
```

**What every open-source user expects, and what we commit to.**

- **README** with a 30-second quick start: add the package, write a source, show a list.
- **DocC** for every public symbol, plus articles: "Choosing a cache policy", "Index vs cursor", "Offline mode", "Migrating from your own pagination code". Published to GitHub Pages from CI.
- **Privacy manifest** (`PrivacyInfo.xcprivacy`). Apple requires SDKs to declare "required reason" APIs; PageKit reads file modification dates for its least-recently-used eviction, so it declares the File Timestamp category with the reason for files inside the app's own container. It collects no data and does no tracking.
- **Semantic versioning.** Patch = bug fix, minor = new feature, major = breaking change. CI runs `swift package diagnose-api-breaking-changes` against the last tag to catch accidental breaks.
- **CI on GitHub Actions:** build and test on the latest two Xcode versions; iOS, macOS and watchOS destinations; strict concurrency; DocC build with warnings as errors.
- **MIT licence**, so companies can adopt it without legal review friction.
- **Issue templates** that ask for the API style (index or cursor), cache policy and a minimal reproduction, which saves a round trip on every bug report.

## 18. App-side guide: using PageKit in an app

An app writes three things: a `PageSource` per API, a small view model per screen, and the screen itself. The library never sees the UI, so every snippet in this section is **app code**, not part of the package.

**Step 1: a reusable view model (SwiftUI, iOS 17+).** One generic class serves every list screen in the app.

```swift
import Observation
import PageKit

@MainActor @Observable
final class FeedViewModel<Source: PageSource> {
    private(set) var snapshot = PaginationSnapshot<Source.Item>.initial   // ONE property: one render per page
    private let paginator: Paginator<Source>

    init(source: Source, configuration: PaginationConfiguration = .init()) {
        paginator = Paginator(source: source, configuration: configuration)
    }

    deinit {
        let paginator = paginator
        Task { await paginator.cancel() }      // stops loads and ends the stream
    }

    /// Called from the view's .task. SwiftUI cancels it when the view disappears.
    func run() async {
        await paginator.start()
        for await snapshot in paginator.snapshots() {
            self.snapshot = snapshot
        }
    }

    func refresh() async { await paginator.refresh() }
    func itemAppeared(_ item: Source.Item) { Task { await paginator.itemAppeared(id: item.id) } }
    func retry() { Task { await paginator.retry() } }
    func delete(_ item: Source.Item) { Task { await paginator.remove(id: item.id) } }
}
```

For iOS 15 and 16, the same class becomes an `ObservableObject` with `@Published private(set) var snapshot`, and the view holds it with `@StateObject`. Nothing else changes.

**Step 2: the screen (SwiftUI, index-based product grid).** Uses `ProductsSource` from section 6.

```swift
struct ProductGridView: View {
    @State private var model = FeedViewModel(source: ProductsSource(api: .live))

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))]) {
                ForEach(model.snapshot.items) { product in          // keyed by product.id
                    ProductCard(product: product)
                        .onAppear { model.itemAppeared(product) }  // drives prefetching
                }
            }
            PageFooter(state: model.snapshot.state, retry: model.retry)
        }
        .overlay { FirstPageOverlay(snapshot: model.snapshot, retry: model.retry) }
        .safeAreaInset(edge: .top) { if model.snapshot.isOffline { OfflineBanner() } }
        .task { await model.run() }
        .refreshable { await model.refresh() }
    }
}

/// App-owned footer: the library only says which state we are in.
struct PageFooter: View {
    let state: PaginationState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .loadingNextPage:
            ProgressView().frame(maxWidth: .infinity).padding()
        case .failed(_, isFirstPage: false):
            Button("Couldn't load more. Tap to retry.", action: retry).padding()
        case .loaded(hasMore: false):
            Text("You're all caught up").foregroundStyle(.secondary).padding()
        default:
            EmptyView()
        }
    }
}
```

`FirstPageOverlay` (also app code) shows a spinner for `.loadingFirstPage`, an empty-state view for `.empty`, and a full-screen error with a Retry button for `.failed(_, isFirstPage: true)`. Because `PaginationState` is an enum, the compiler forces the app to handle every case.

**Step 3: the screen (UIKit, cursor-based timeline).** Uses `TimelineSource` from section 6.

```swift
@MainActor
final class TimelineViewController: UICollectionViewController, UICollectionViewDataSourcePrefetching {
    private let paginator = Paginator(source: TimelineSource(api: .live))
    private var dataSource: UICollectionViewDiffableDataSource<Int, Post.ID>!
    private var postsByID: [Post.ID: Post] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.prefetchDataSource = self
        dataSource = makeDataSource()          // cell registration reads postsByID[id]
        Task { [weak self, paginator] in
            await paginator.start()
            for await snapshot in paginator.snapshots() { self?.render(snapshot) }
        }
    }

    deinit {
        let paginator = paginator
        Task { await paginator.cancel() }      // ends the stream, so the loop above finishes
    }

    private func render(_ snapshot: PaginationSnapshot<Post>) {
        // Posts whose content changed (e.g. like count) are reconfigured, not replaced.
        let edited = snapshot.items.filter { old in postsByID[old.id].map { $0 != old } ?? false }.map(\.id)
        postsByID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })

        var diff = NSDiffableDataSourceSnapshot<Int, Post.ID>()
        diff.appendSections([0])
        diff.appendItems(snapshot.items.map(\.id))
        diff.reconfigureItems(edited)
        dataSource.apply(diff, animatingDifferences: false)
        footerView.render(snapshot.state)      // app-owned supplementary view
    }

    // Two prefetch signals, both forwarded as plain indexes.
    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                                 forItemAt indexPath: IndexPath) {
        Task { await paginator.prefetch(upToIndex: indexPath.item) }
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let furthest = indexPaths.map(\.item).max() else { return }
        Task { await paginator.prefetch(upToIndex: furthest) }
    }
}
```

(`Post` is `Equatable` here so the view controller can spot edited posts.)

**Step 4: choose settings per use case.** The same two app-side types cover every case below; only the source and the configuration change.

| Use case | Example | Token | Cache policy | Other settings |
| --- | --- | --- | --- | --- |
| Page-number API | Product catalogue | `IndexToken` | `.cacheThenNetwork` | Defaults |
| Offset API | Admin table, `?offset=40&limit=20` | `IndexToken` (use `token.offset`) | `.cacheThenNetwork` | Defaults |
| API returns total pages | Order history | `IndexToken` | `.cacheThenNetwork` | End when `page >= totalPages` |
| Cursor feed | Social timeline, notifications | `CursorToken` | `.cacheThenNetwork` | `lookaheadPages = 1` |
| Search results | Product search | `CursorToken` or `IndexToken` | `.networkFirst` | `feedID` includes the query; short `maxAge` |
| Offline-first reading | Saved articles, recipes | Either | `.cacheThenNetwork` | `storage = .durable`, `maxAge` 30 days |
| Live data | Prices, stock levels, bids | Either | `.networkOnly` | `lookaheadPages = 0` |
| Filtered or GraphQL lists | Orders by status, Relay connection | Custom `PageToken` | `.cacheThenNetwork` | Filter inside the token |

**Use case: an API that tells you the total.**

```swift
func loadPage(_ token: IndexToken) async throws -> Page<Order, IndexToken> {
    let response = try await api.orders(page: token.page, perPage: token.size)
    let hasMore = token.page < response.totalPages
    return Page(items: response.orders, nextToken: hasMore ? token.next : nil)
}
```

**Use case: search, where the query changes.** Each query is its own feed, so results for "shoes" never mix with "boots", and going back to "shoes" is served from cache. The view model swaps paginators and debounces typing.

```swift
struct SearchSource: PageSource {
    let api: APIClient
    let query: String
    var feedID: String { "search." + query.lowercased() }
    let firstToken = CursorToken(value: nil, size: 20)

    func loadPage(_ token: CursorToken) async throws -> Page<Product, CursorToken> {
        let r = try await api.search(query, after: token.value, limit: token.size)
        return Page(items: r.items, nextToken: r.next.map { CursorToken(value: $0, size: token.size) })
    }
}

// In the search view model (app code)
func queryChanged(_ text: String) {
    searchTask?.cancel()
    searchTask = Task {
        try? await Task.sleep(for: .milliseconds(300))        // debounce typing
        guard !Task.isCancelled else { return }
        await paginator?.cancel()                            // stop the previous query
        var config = PaginationConfiguration()
        config.cachePolicy = .networkFirst
        config.maxAge = 60 * 60                              // search results go stale fast
        let next = Paginator(source: SearchSource(api: api, query: text), configuration: config)
        paginator = next
        await next.start()
        for await snapshot in next.snapshots() { self.snapshot = snapshot }
    }
}
```

**Use case: filters or GraphQL, with a custom token.** Anything the server needs to continue the list goes in the token, so it is cached and restored with the page.

```swift
struct OrdersToken: PageToken {
    let after: String?          // pageInfo.endCursor from the previous page
    let status: OrderStatus     // an enum that is Codable, Hashable and Sendable
    let size: Int
}
```

**Use case: offline-first reading list.**

```swift
var config = PaginationConfiguration()
config.storage = .durable                 // Application Support, not Caches
config.maxAge = 30 * 24 * 3600            // keep a month of articles
let model = FeedViewModel(source: SavedArticlesSource(api: .live), configuration: config)
```

The screen reads `snapshot.isOffline` to show a banner and `snapshot.isStale` to show a quiet "Updating…" label while a refresh runs over cached data.

**Use case: live data.** `config.cachePolicy = .networkOnly` and `config.lookaheadPages = 0`. Prices are never shown from cache, and nothing is fetched ahead that would be out of date by the time it is seen.

**Use case: several lists on one screen.** A screen with tabs ("For you", "Following") creates one paginator per tab with distinct `feedID`s. Each has its own state, cache entries and in-flight requests, and switching tabs is instant because the inactive tab keeps its snapshot.

**Use case: the user edits or deletes an item.** Call `paginator.remove(id:)` or `paginator.update(_:)` after the server confirms. The change appears in the next snapshot and is written to both caches, so a relaunch does not resurrect a deleted post.

**Use case: logout.**

```swift
func logOut() async {
    await session.revokeTokens()
    await PageKit.clearAll()      // memory and disk, every feed
    router.showLogin()            // only after the wipe finishes
}
```

**Testing the view model.** Because the paginator takes any `PageSource`, a view-model test injects the `MockSource` from section 16, calls `run()` in a task, and asserts on `snapshot.state` and `snapshot.items`, with no network and no simulator UI.

## 19. Interview talking points and trade-offs

In a system-design interview, lead with requirements, draw the layers, then defend three or four decisions with their trade-offs. These are the questions most likely to follow, with short answers you can say out loud.

**"How do you support both index and cursor pagination without two code paths?"** Every response is normalised to `Page(items, nextToken)`. The engine is generic over the token and only asks whether a next token exists. Index sources compute it; cursor sources read it from the response.

**"Why NSCache?"** It is thread-safe, has cost and count limits, and evicts on memory pressure before iOS kills the app. A dictionary has none of that. The trade-off is that it can drop anything at any time, so it is never the source of truth; disk sits behind it.

**"Why not URLCache, since it already caches responses?"** It caches bytes, so every hit means decoding again on scroll-back, and it depends on HTTP cache headers and GET requests. We want decoded models, keyed by feed and token, under our own expiry rules.

**"How do you stop duplicate network calls when the user scrolls fast?"** An actor holds a dictionary of in-flight tasks keyed by token. A second caller awaits the first task instead of starting a new one.

**"What happens if a refresh starts while page 5 is loading?"** A generation counter. Refresh increments it and cancels tasks; any response that comes back with an old generation is discarded, which also covers the race where the request finished just before cancel.

**"How does offline work?"** Pages and a manifest are written to disk as JSON. On launch we show them at once, then try the network. We never skip a request based on `NWPathMonitor`; we use it only to label the UI and to retry automatically when the network returns.

**"Where does the smoothness actually come from?"** Five things: no I/O or decoding on the main thread, one UI update per page, stable IDs for cheap diffing, O(1) work when a cell appears, and prefetching so data arrives before the user reaches the end. The cache removes pauses around scrolling, such as re-entry and scroll-back after windowing.

**"How would you measure it?"** Instruments' Animation Hitches template for hitch ratio, `XCTOSSignpostMetric` scroll metrics in UI tests with a CI baseline, and signposts around fetch, decode and apply.

**"Why doesn't the library ship any UI?"** Every app already has its own design system, loading indicators and architecture (MVVM, TCA, MVC). A bundled footer or list view would be replaced in almost every real app, and it would tie the package to SwiftUI or UIKit. Publishing plain state through an `AsyncStream` keeps the library small, testable, and usable from widgets, watch apps and AppKit. The app writes about 30 lines of view model once and reuses it for every list.

**"How would an app use this for search, where the query keeps changing?"** One feed per query (`feedID` includes the query), a fresh paginator per query, the old one cancelled, and a 300 ms debounce in the view model. Results for an earlier query come back from cache when the user returns to it.

**Trade-offs at a glance.**

| Decision | Chosen | Alternative | Why chosen |
| --- | --- | --- | --- |
| Concurrency | Actors + async/await | GCD queues + locks | Compiler-checked safety; cancellation built in. Cost: iOS 15 minimum. |
| Memory cache | NSCache | Dictionary with manual LRU | Memory-pressure eviction for free. Cost: unpredictable eviction. |
| Disk format | JSON files per page | Core Data / SwiftData | Pages are written and read whole, never queried. Cost: no partial queries. |
| Disk eviction unit | Whole feed | Single page | A cursor chain with a hole is useless. Cost: coarser eviction. |
| Prefetch trigger | Item distance from end | Scroll offset | Layout-independent, works in SwiftUI on iOS 15. Cost: one fixed threshold. |
| Networking | App-supplied `PageSource` | Built-in HTTP client | Apps keep their auth and logging. Cost: one small type to write. |
| State output | AsyncStream of snapshots, no UI code | `ObservableObject and SwiftUI views in the library` | Works with any UI framework or architecture and is testable without a simulator. Cost: each app writes a small view model (section 18). |

**What I would build next (version 2).** Bidirectional loading for chat-style lists; windowing on by default once it is proven; an adapter for GraphQL Relay connections (`edges`, `pageInfo.endCursor`); and background refresh through `BGAppRefreshTask` so a feed is fresh before the user opens the app.
