import XCTest

/// Walks the app the way a person would. Everything except the live scroll test runs on
/// simulated news, through the `-mock` launch argument.
@MainActor
final class PageKitDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The 2,000-item mock feed. Mock rows draw placeholders, so this measures the list and
    /// the paging, not image decoding.
    func testScrollPerformance() {
        let app = launch(arguments: ["-mock"])
        XCTAssertTrue(firstRow(in: app).waitForExistence(timeout: 10))
        measureScrolling(in: app)
    }

    /// The real feed, with real images. It needs the network, so it skips itself when the
    /// feed can't load. A simulator reports scroll durations only, not hitches, so run this
    /// on a device to judge `AsyncImage`.
    func testLiveFeedScrollPerformance() throws {
        let app = launch(arguments: [])
        guard firstRow(in: app).waitForExistence(timeout: 20) else {
            throw XCTSkip("The live feed did not load, so there is nothing to measure.")
        }
        measureScrolling(in: app)
    }

    /// Offline stops the feed at "Connect to load more". Coming back online carries on
    /// from the same place without being asked.
    func testChaosFooterStates() {
        let app = launch(arguments: ["-mock"])
        XCTAssertTrue(firstRow(in: app).waitForExistence(timeout: 10))
        setOffline(true, in: app)

        let offlineFooter = app.staticTexts["Connect to load more"]
        scrollDown(in: app, until: offlineFooter)
        XCTAssertTrue(offlineFooter.exists, "The next page should fail while offline.")
        let itemsWhileOffline = itemCount(in: app)

        // Blogs sits at the top of its own feed, so its masthead is a tap away, however
        // far a saved feed from an earlier run took this one.
        app.tabBars.buttons["Blogs"].tap()
        setOffline(false, in: app)
        app.tabBars.buttons["Articles"].tap()

        let hasMoreItems = NSPredicate { _, _ in self.itemCount(in: app) > itemsWhileOffline }
        wait(for: [expectation(for: hasMoreItems, evaluatedWith: app)], timeout: 10)
        XCTAssertFalse(offlineFooter.exists)
    }

    // MARK: - Helpers

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func firstRow(in app: XCUIApplication) -> XCUIElement {
        element("feed.row.", in: app, matching: "identifier BEGINSWITH %@")
    }

    private func simulatorButton(in app: XCUIApplication) -> XCUIElement {
        element("simulator.open", in: app)
    }

    private func element(_ identifier: String, in app: XCUIApplication, matching format: String = "identifier == %@") -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: format, identifier))
            .firstMatch
    }

    /// Records one fast swipe per iteration, then swipes back so each one starts alike.
    private func measureScrolling(in app: XCUIApplication) {
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        let metrics = [XCTOSSignpostMetric.scrollDraggingMetric, XCTOSSignpostMetric.scrollDecelerationMetric]
        measure(metrics: metrics, options: options) {
            app.swipeUp(velocity: .fast)
            stopMeasuring()
            app.swipeDown(velocity: .fast)
        }
    }

    private func scrollDown(in app: XCUIApplication, until target: XCUIElement) {
        for _ in 0..<100 where !target.exists {
            app.swipeUp(velocity: .fast)
        }
    }

    private func setOffline(_ isOffline: Bool, in app: XCUIApplication) {
        simulatorButton(in: app).tap()
        let toggle = app.switches["simulator.offline"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String == "1") != isOffline {
            toggle.switches.firstMatch.tap()
        }
        element("simulator.close", in: app).tap()
    }

    private func itemCount(in app: XCUIApplication) -> Int {
        let label = element("feed.debug", in: app).label
        return label.split(separator: " ").lazy.compactMap { Int($0) }.first ?? 0
    }
}
