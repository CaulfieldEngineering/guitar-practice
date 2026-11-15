import XCTest

/// Taps through the screens the way Joe did on 0.1.4 (a drill crashed the app; the Settings gear froze it), on a
/// simulator with no audio interface.
final class TapThroughTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDrillSettingsAndProgress() {
        let app = XCUIApplication()
        app.launch()

        // Play along: open a drill, then another.
        app.tabBars.buttons["Play along"].tap()
        let drill = app.buttons["exercise.alt8"]
        XCTAssertTrue(drill.waitForExistence(timeout: 10))
        drill.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10), "the drill's own screen opens")
        XCTAssertEqual(app.state, .runningForeground)

        // Start with no interface: a clear message, no crash.
        app.buttons["start"].tap()
        XCTAssertTrue(app.staticTexts["message"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)

        app.buttons["Back"].tap()
        let flagship = app.buttons["exercise.trip16x4"]
        XCTAssertTrue(flagship.waitForExistence(timeout: 10))
        flagship.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        app.buttons["Back"].tap()

        // Settings opens and closes.
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Settings opens")
        app.navigationBars["Settings"].buttons["Done"].tap()

        // Progress opens and closes.
        app.buttons["progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10), "Progress opens")
        app.navigationBars["Progress"].buttons["Done"].tap()
        XCTAssertEqual(app.state, .runningForeground)
    }
}
