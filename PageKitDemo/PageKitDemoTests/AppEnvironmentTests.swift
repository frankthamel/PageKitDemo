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
        let before = environment.feeds

        await environment.switchMode(to: .mock)

        #expect(counter.clears == 1)
        #expect(environment.mode == .mock)
        #expect(environment.feeds != nil)
        #expect(environment.feeds?.id != before?.id)
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
