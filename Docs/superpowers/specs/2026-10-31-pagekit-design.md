# PageKit, NewsClient and the Demo App: Design

Date: 2026-10-31
Source of truth for library behaviour: `Docs/Building PageKit A Reusable Swift Pagination Library.md` ("the Doc"). This document records only the scope, the structure, and where the build departs from or resolves the Doc. Section numbers (§) refer to the Doc.

## Intent

Frank is preparing for interviews and plans to open source PageKit. Two things must be true at the end:

1. PageKit is a real, adoptable open-source Swift package that implements the Doc.
2. The code is something Frank can open in an interview and defend: clean, tidy, SOLID, with pagination architecture as the visible focus.

## Goals

- Implement PageKit to the Doc: all of FR-1 to FR-20, the NFRs, and the §17 packaging.
- Add a `NewsClient` package with an interface target (models, protocol, mocks, mock service) and a live target.
- Build a SwiftUI, MVVM news app that reads like The Economist, in retro colours, that can run entirely on simulated data.
- Full test coverage: every testable line in the three codebases where practical, and never below the Doc's 90% on PageKit.
- A comprehensive README in `PageKit` so developers can adopt it easily.

## Non-goals

- Everything in the Doc's non-goals: UI in the library, image caching, write-back sync, a database, bidirectional scrolling.
- Version 2 items: memory windowing, Relay adapter, background refresh.
- In the demo: search and a UIKit screen. Frank chose "both styles + simulator panel" for the demo, and that choice narrows §17's example list. The README still documents search and UIKit usage from §18.
- Accounts, bookmarks or article reading inside the app. Tapping an article opens its source URL.

## Anti-goals

- Over-engineering: no abstraction without a second implementation or a test that needs it, no use-case/repository layering on top of `PageSource`.
- Pagination logic leaking into views or view models. Pagination decisions live in `Paginator`.
- Default-looking UI. The app must have a designed identity.

## Repositories and layout

Two public GitHub repos, both empty today. Frank supplied both URLs and the push commands, so pushing to `main` is authorised.

```
PageKitLibrary/                      <- git root of github.com/frankthamel/PageKitDemo
  PageKitWS.xcworkspace              references all packages and the app
  Docs/
  PageKitDemo/                       Xcode app project and its test targets
  Packages/
    NewsClient/                      plain folder in this repo
    PageKit/                         git submodule -> github.com/frankthamel/PageKit
```

- `Packages/PageKit` is its own repo with `Package.swift` at its root, so it can be added by URL.
- Keeping PageKit as a submodule preserves the local layout and makes one recursive clone build. The Demo README states `git clone --recurse-submodules`.
- The Doc's §17 `Examples/PageKitDemo` folder is therefore not used. The PageKit README links to the PageKitDemo repo instead.

## PageKit

### Package

- `swift-tools-version: 6.0` per §17, Swift 6 language mode, iOS 15 / macOS 12 / tvOS 15 / watchOS 8, empty `dependencies`, `PrivacyInfo.xcprivacy` resource.
- Single `PageKit` target. Imports only Foundation, Network, CryptoKit and `os`.
- Because the floor is iOS 15, code uses `Task.sleep(nanoseconds:)` and avoids iOS 16-only APIs such as `Clock`.

### File structure

```
Sources/PageKit/
  Models/        Page, PageToken, IndexToken, CursorToken, PaginationState,
                 PaginationSnapshot, PaginationError, FeedManifest, StoredPage, PageKey
  Sources/       PageSource, URLSessionPageSource
  Configuration/ PaginationConfiguration, CachePolicy, RetryPolicy, DiskStorage
  Engine/        Paginator (+ extensions by concern: Loading, Prefetch, LocalEdits),
                 Retrier, ErrorClassifier
  Cache/         MemoryPageCache, CachedPage, DiskPageStore, DiskMaintenance
  Connectivity/  ConnectivityMonitoring, ConnectivityStatus, NetworkPathMonitor
  PageKit.swift  public clearing API
  PageKit.docc/  catalogue, 4 articles, 1 tutorial
```

Dependency direction: `Paginator` depends on internal protocols for each external effect, and concrete types are injected through an internal initialiser used by tests. The public initialiser stays as in §6.

### Where the build resolves the Doc

The Doc's samples disagree with each other or leave a gap in these places. These are the builder's decisions and need a test each.

| # | Doc | Decision |
| --- | --- | --- |
| 1 | §13's `.loadingMore` and `.loaded(let next?)` disagree with §7's enum. "9 states" caption vs 7 cases. | §7's enum is canonical. The next token is stored in a private property. |
| 2 | `PaginationState: Equatable` holds a non-Equatable `PaginationError`. | `PaginationError` is `Equatable`. |
| 3 | Cancelled is "not an error" but has no representation. | Classifier returns `nil` for cancellation, and the state is restored to what it was before the load. |
| 4 | `ConnectivityMonitoring` yields `Bool`, yet §11 needs expensive/constrained. | Yields a `ConnectivityStatus { isOnline, isExpensive, isConstrained }`. Add `allowsReadAheadOnExpensiveNetwork` (default `false`) to configuration for the "unless the app opts in" case. |
| 5 | §11 says no prefetch in background, but the library cannot import UIKit. | New `Paginator.setAppActive(_:)`, called by the app from `scenePhase`. Defaults to active. |
| 6 | `PaginationSnapshot.initial` used in §18 but undefined. | Public static, state `.idle`. |
| 7 | `MemoryPageCache` is generic per paginator, but `secondOpenServesFromMemory` and `PageKit.clearAll()` need a process-wide cache. | One shared, non-generic `MemoryPageCache` holding `AnyObject` boxes, read back with `as? CachedPage<Item, Token>`. A type mismatch counts as a miss. Its limit is the highest `memoryCostLimit` seen. |
| 8 | `PageKit.clear` has no way to know a feed's storage. | Clears the feed in both the Caches and Application Support roots. |
| 9 | Module and enum both named `PageKit`. | Keep the Doc's API. It is legal without library evolution. Note in README. |
| 10 | `.completeFileProtectionUntilFirstUserAuthentication` is iOS-family only. | Guarded with `#if`; plain `.atomic` on macOS. |
| 11 | `start()` ordering vs the first `snapshots()` subscriber in §18. | Each stream starts with the current snapshot, so ordering is safe. |
| 12 | `Paginator.fetch` called in tests. | `internal`, used through `@testable import`. |
| 13 | §11 wants parallel index read-ahead, but §4's engine never looks inside a token. | `PageToken` gains `var predictedNext: Self? { get }`, defaulting to `nil` in a protocol extension. `IndexToken` returns `next`. The engine reads ahead in parallel (cap 2) whenever a token predicts its successor, with no check on the token's type, so there is still one code path. |
| 14 | "Sample app uses three different APIs". | Met by three backends behind `PageSource`: Articles, Blogs and the mock service. |
| 15 | "Simulated memory warning in the sample app". | Public `PageKit.clearMemoryCache()`, a button in the simulator panel, and `memoryWarningEmptiesCacheButNotList` calls it. A real OS warning cannot be raised in `swift test`. |

### Cache reads (resolves §10, §11 and §12 against each other)

One invariant makes the rest simple: **every page in the cache belongs to the current chain.** Replacing the list deletes the later pages, so a cached page is always safe to append.

- **Opening a feed under `.cacheThenNetwork`:** restore the whole manifest chain at once with `isStale = true`, then fetch page 1 from the network. There is no freshness window.
  - Page 1 has the same IDs in the same order: update it in place, keep the chain, clear `isStale`.
  - Page 1 differs: replace the list and delete later pages, as in §12.
- **Reconnect:** a silent refresh runs only if the user is still on page 1. Past page 1, it never shrinks the list. The items stay stale and only the pending next page is retried.
- **`refresh()` (pull to refresh)** always follows §12: on success, replace and delete.
- **Next page:**
  - `.cacheThenNetwork` and `.cacheOnly`: memory, then disk, then network. `.cacheOnly` skips the network and ends the list when the chain ends.
  - `.networkFirst`: network, falling back to cache on failure.
  - `.networkOnly`: network only, and caches are neither read nor written.
- **`secondOpenServesFromMemoryWithoutCallingSource`** runs under `.cacheOnly`. A companion test under `.cacheThenNetwork` asserts the source is called once, for page 1 only.

### Non-blocking errors (resolves §12 and §15 against §7)

- `PaginationSnapshot` gains `lastError: PaginationError?`. This is an addition to the Doc's public API.
- A failed refresh or silent refresh with items on screen stays in `.loaded`, with `lastError` set. The user can keep scrolling, so §7's "only Loaded may load" rule holds.
- `.failed(_, isFirstPage: true)` occurs only when there are no items, so a full-screen error always means there is nothing to show.
- `retry()` repeats the operation that set the error. `lastError` clears when any later load succeeds.
- A next page that fails while offline is `.failed(.offline, isFirstPage: false)`, and the app's footer shows "Connect to load more".

### Disk maintenance (resolves per-feed limits)

- `FeedManifest` also stores the feed's `maxAge` and `diskSizeLimit`, so `performMaintenance()` works with no paginator alive, for example from `BGAppRefreshTask`.
- Age: each feed expires by its own `maxAge`, in both storage roots.
- Size: only the Caches root is size-evicted, against the largest `diskSizeLimit` recorded there. `.durable` feeds are exempt, which keeps §6's promise of guaranteed offline.

### Behaviour

Everything else follows §4 to §15, including the 7-step page-arrival order, generation check after every `await`, refresh deleting only after success, whole-feed eviction to 80%, jittered backoff, and `.private` URL logging.

Injected for tests: page source, connectivity, sleep function, clock (`now`), disk root.

### Testing

Swift Testing. Every row of §16's traceability table exists under the same test name, plus a test for every decision above. `URLProtocol` stub for `URLSessionPageSource`, temp-folder `DiskPageStore`, `FakeConnectivity`, instant sleep. Tests avoid real sleeps by using controllable continuations. Coverage is measured with `swift test --enable-code-coverage`. `NetworkPathMonitor`'s `NWPathMonitor` callback cannot be unit-tested in isolation, and is the expected exception.

### Packaging (§17, in full)

README, CHANGELOG, CONTRIBUTING, CODE_OF_CONDUCT, MIT LICENSE, issue templates, DocC catalogue with the four named articles and a tutorial, `PrivacyInfo.xcprivacy`, and GitHub Actions for build/test, strict concurrency, DocC warnings-as-errors, API-breaking checks and Pages publishing.

Frank must switch GitHub Pages to the Actions source in the repo settings for the DocC site to go live, unless the API allows it from here, in which case the builder does that.

## NewsClient

Backend: Spaceflight News API v4 (`api.spaceflightnewsapi.net`), confirmed reachable with no key on 2026-10-31. Responses have the shape `{count, next, previous, results[{id, title, authors, url, image_url, news_site, summary, published_at}]}`.

```
Packages/NewsClient/
  Package.swift
  Sources/
    NewsClient/          Article, NewsPage, NewsSection, NewsClientError,
                         NewsService protocol, MockNewsService, SimulationSettings, Article+Mock
    NewsClientLive/      LiveNewsService, DTOs, endpoint building
  Tests/ NewsClientTests, NewsClientLiveTests
```

- `NewsClient` has no networking and no dependency on PageKit. It knows nothing about pagination libraries.
- `NewsService` exposes two calls, one per style:
  - `articles(section:offset:limit:)`: index-style.
  - `articles(section:cursor:limit:)`: cursor-style, where the cursor is the API's opaque `next` URL. In the live service the URL is validated to be on the API host before use.
- Both return `NewsPage { articles, total, nextCursor }`.
- `MockNewsService` is an actor generating a deterministic 2,000-article feed per section, honouring both calls.
- `SimulationSettings`: latency up to 3 s, failure rate (default 20% when chaos is on), and an offline flag that throws `URLError(.notConnectedToInternet)`. These reproduce §16's chaos mode.

## Demo app (PageKitDemo)

SwiftUI, MVVM. Keeps the project's iOS 26.2 deployment target. Project is moved to Swift 6 language mode, and the app target depends on `PageKit`, `NewsClient` and `NewsClientLive`.

```
PageKitDemo/PageKitDemo/
  App/          PageKitDemoApp, AppEnvironment (composition root: live or mock)
  Sources/      ArticlesIndexSource, BlogsCursorSource (PageSource impls)
  Features/
    Feed/       FeedViewModel<Source>, FeedScreen, ArticleRow, LeadArticleCard,
                PageFooter, FirstPageOverlay, OfflineBanner
    Simulator/  SimulatorViewModel, SimulatorPanel
  DesignSystem/ Colors, Typography, Components
```

- Two feeds as tabs: **Articles** on `IndexToken` and **Blogs** on `CursorToken`, driven by the same `FeedViewModel` and the same views. That sameness is the demo's main point.
- `FeedViewModel` follows §18 Step 1, plus `scenePhase` forwarding. A small banner shows `lastError` when items are on screen.
- The project defaults to MainActor isolation, so `PageSource` types are marked `nonisolated`.
- `PageKitWS.xcworkspace` gains a reference to `Packages/NewsClient`.
- A small debug footer on each feed shows token type, pages loaded, and cache state, so the pagination is visible while demoing.
- Simulator panel: live/mock switch, latency, failure rate, offline, and "clear cache". Switching rebuilds the feeds through `AppEnvironment`.
- Tapping an article opens `article.url` in the system browser.

### Look

Economist-like editorial structure in a retro palette: a masthead, a strong red block, a dense serif-led list, thin rules, kicker labels and a large lead story. Palette direction: cream paper, ink near-black, signal red, mustard and faded teal. Exact design is left to the builder using the frontend-design skill. It must not use The Economist's name, logo or wordmark. App name in UI: **The Orbital**.

Images use `AsyncImage`. Mock articles have no remote images and use a typographic retro placeholder.

### Tests

- `PageKitDemoTests`: both `PageSource`s, `FeedViewModel`, `SimulatorViewModel`, `AppEnvironment`, using `MockNewsService`.
- `PageKitDemoUITests`: scroll the 2,000-item mock feed recording `XCTOSSignpostMetric` scroll metrics (§16), and a chaos-mode footer-state walk-through.
- The Doc's "fails if hitch ratio regresses 10% against baseline" CI gate lives in the Demo repo as an Xcode performance baseline, recorded locally. It is not enforced in GitHub Actions, because hosted runners are too noisy for it.

## Delivery

- PageKit is committed and pushed first, so the Demo repo's submodule can point at a real commit. Tag `0.1.0` once tests pass.
- Then NewsClient and the app, pushed to PageKitDemo.
- Done means: `swift test` passes on both packages, `swift build -Xswiftc -strict-concurrency=complete` is warning-free, the demo builds and its tests pass on an iOS simulator, the app has been run and screenshotted in both live and mock modes, and CI is green on PageKit.

## Left to the builder

- Internal helper names, exact visuals, exact mock copy, and how the DocC tutorial is structured.
