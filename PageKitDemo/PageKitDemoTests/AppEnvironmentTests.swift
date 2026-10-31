import NewsClient
import Testing
@testable import PageKitDemo

@MainActor
struct AppEnvironmentTests {
    private final class Counter {
        var clears = 0
    }

    @Test func defaultsToLive() {
        let environment = AppEnvironment(arguments: ["PageKitDemo"])

        #expect(environment.mode == .live)
        #expect(environment.feeds != nil)
    }

    @Test func mockLaunchArgumentSelectsMock() {
        let environment = AppEnvironment(arguments: ["PageKitDemo", "-mock"])

        #expect(environment.mode == .mock)
    }

    @Test func switchingModeClearsCaches() async {
        let counter = Counter()
        let environment = AppEnvironment(arguments: []) { counter.clears += 1 }

        await environment.switchMode(to: .mock)

        #expect(counter.clears == 1)
        #expect(environment.mode == .mock)
        #expect(environment.feeds != nil)
    }

    @Test func eachModeCachesUnderItsOwnFeedIDs() async {
        let environment = AppEnvironment(arguments: ["-mock"]) { }
        let mockIDs = (environment.makeArticlesSource().feedID, environment.makeBlogsSource().feedID)

        await environment.switchMode(to: .live)
        let liveIDs = (environment.makeArticlesSource().feedID, environment.makeBlogsSource().feedID)

        #expect(mockIDs.0 != liveIDs.0)
        #expect(mockIDs.1 != liveIDs.1)
        #expect(mockIDs.0 != mockIDs.1)
    }

    @Test func liveServiceIsOnlyBuiltForLiveMode() async {
        let counter = Counter()
        let environment = AppEnvironment(arguments: ["-mock"], clearCaches: { }, makeLive: { counter.clears += 1; return MockNewsService() })
        #expect(counter.clears == 0)

        await environment.switchMode(to: .live)

        #expect(counter.clears == 1)
    }

    @Test func aSecondSwitchDuringOneInFlightIsIgnored() async {
        let counter = Counter()
        let environment = AppEnvironment(arguments: []) {
            counter.clears += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let first = Task { await environment.switchMode(to: .mock) }
        while !environment.isSwitching { await Task.yield() }

        await environment.switchMode(to: .live)
        await first.value

        #expect(counter.clears == 1)
        #expect(environment.mode == .mock)
        #expect(!environment.isSwitching)
    }

    @Test func switchingToTheCurrentModeDoesNothing() async {
        let counter = Counter()
        let environment = AppEnvironment(arguments: []) { counter.clears += 1 }

        await environment.switchMode(to: .live)

        #expect(counter.clears == 0)
    }

    @Test func feedsAreMissingWhileCachesClear() async {
        final class Probe {
            var environment: AppEnvironment?
            var feedsDuringClear: AppEnvironment.Feeds?
        }
        let probe = Probe()
        let environment = AppEnvironment(arguments: []) { probe.feedsDuringClear = probe.environment?.feeds }
        probe.environment = environment

        await environment.switchMode(to: .mock)

        #expect(probe.feedsDuringClear == nil)
    }
}
