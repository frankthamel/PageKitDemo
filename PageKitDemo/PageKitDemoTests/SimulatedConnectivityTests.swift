import PageKit
import Testing
@testable import PageKitDemo

struct SimulatedConnectivityTests {
    @Test func aNewStreamStartsWithTheCurrentStatus() async {
        let connectivity = SimulatedConnectivity()
        connectivity.setOnline(false)

        var updates = connectivity.updates().makeAsyncIterator()

        #expect(await updates.next()?.isOnline == false)
    }

    @Test func everyStreamHearsAChange() async {
        let connectivity = SimulatedConnectivity()
        var first = connectivity.updates().makeAsyncIterator()
        var second = connectivity.updates().makeAsyncIterator()
        #expect(await first.next()?.isOnline == true)
        #expect(await second.next()?.isOnline == true)

        connectivity.setOnline(false)

        #expect(await first.next()?.isOnline == false)
        #expect(await second.next()?.isOnline == false)
    }

    @Test func sayingTheSameThingTwiceIsNotAChange() async {
        let connectivity = SimulatedConnectivity()
        var updates = connectivity.updates().makeAsyncIterator()
        _ = await updates.next()

        connectivity.setOnline(true)
        connectivity.setOnline(false)

        #expect(await updates.next()?.isOnline == false)
    }
}
