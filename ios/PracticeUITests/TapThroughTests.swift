import XCTest

/// Taps through every screen on a simulator with no audio interface, the way Joe uses the app (0.1.4 crashed on
/// choosing a drill and froze on the Settings gear), and keeps a screenshot of each screen, dark and light, in the
/// test results (the workflow publishes them as the "screens" artifact).
final class TapThroughTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// A fresh start each time: the settings the unit tests left behind are cleared (-resetState).
    private func launch(_ appearance: String = "dark", _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetState", "1", "-appearance", appearance] + extra
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testDrillSettingsAndProgress() {
        let app = launch()

        // Metronome: starts and stops.
        let metro = app.buttons["metronome.start"]
        XCTAssertTrue(metro.waitForExistence(timeout: 20))
        shot("01-metronome-dark")
        metro.tap()
        XCTAssertEqual(app.state, .runningForeground)
        metro.tap()

        // Drills: open a drill.
        app.tabBars.buttons["Drills"].tap()
        let drill = app.buttons["exercise.alt8"]
        XCTAssertTrue(drill.waitForExistence(timeout: 10))
        shot("02-drills-dark")
        drill.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10), "the drill's own screen opens")
        XCTAssertEqual(app.state, .runningForeground)
        shot("03-setup-dark")

        // Start with the audio input on and no interface: a clear message, no crash.
        app.buttons["start"].tap()
        XCTAssertTrue(app.staticTexts["message"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        shot("04-setup-no-interface-dark")

        // Audio input off: the run starts with no interface and nothing asks for the microphone.
        app.swipeUp()
        let input = app.switches["Audio input"]
        if input.waitForExistence(timeout: 5) {
            input.tap()
            shot("05-setup-audio-input-off-dark")
            app.buttons["start"].tap()
            let skip = app.buttons["Skip the intro"]
            if skip.waitForExistence(timeout: 5) {
                shot("06-intro-dark")
                skip.tap()
            }
            let stop = app.buttons["run.stop"]
            if stop.waitForExistence(timeout: 10) {
                sleep(1)
                shot("07-run-audio-input-off-dark")
                // A short drill ends by itself; otherwise stop it.
                sleep(3)
                if stop.exists && stop.isHittable { stop.tap() }
                let done = app.buttons["result.done"]
                if done.waitForExistence(timeout: 20) {
                    shot("08-result-audio-input-off-dark")
                    done.tap()
                }
            }
            XCTAssertEqual(app.state, .runningForeground)
        }

        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10))
        app.buttons["Back"].tap()
        let flagship = app.buttons["exercise.trip16x4"]
        XCTAssertTrue(flagship.waitForExistence(timeout: 10))
        flagship.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        shot("09-setup-flagship-dark")
        app.buttons["Back"].tap()

        // A timed routine opens ready to run.
        let routine = app.buttons["routine.Starting Protocol"]
        if routine.waitForExistence(timeout: 5) {
            routine.tap()
            XCTAssertTrue(app.buttons["routine.start"].waitForExistence(timeout: 10), "the routine opens")
            shot("10-routine-dark")
            app.buttons["Back"].tap()
        }

        // Settings opens and closes.
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Settings opens")
        shot("11-settings-dark")
        app.navigationBars["Settings"].buttons["Done"].tap()

        // Progress opens and closes.
        app.buttons["progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10), "Progress opens")
        shot("12-progress-dark")
        app.navigationBars["Progress"].buttons["Done"].tap()
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// With a max on the drill: the zones fit, each says its tempos, and the options unfold.
    func testZonesAndOptions() {
        let app = launch("dark", ["-seedMax", "1"])
        app.tabBars.buttons["Drills"].tap()
        let flagship = app.buttons["exercise.trip16x4"]
        XCTAssertTrue(flagship.waitForExistence(timeout: 20))
        shot("20-drills-with-max-dark")
        flagship.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        for id in ["z1", "z2", "z3", "z4", "z5"] {
            XCTAssertTrue(app.buttons["zone.\(id)"].exists, "zone \(id) is on the screen")
            XCTAssertTrue(app.buttons["zone.\(id)"].isHittable, "zone \(id) is not cut off")
        }
        shot("21-setup-zones-dark")
        app.buttons["zone.z4"].tap()
        shot("22-setup-zone-4-dark")
        app.swipeUp()
        let options = app.buttons["Options"]
        if options.waitForExistence(timeout: 5) {
            options.tap()
            app.swipeUp()
            shot("23-setup-options-dark")
            // The calibration's first step: the marks, the line through the middle, the slider.
            let calibrate = app.buttons["calibrate"]
            if calibrate.waitForExistence(timeout: 5) {
                calibrate.tap()
                let done = app.buttons["calibration.done"]
                if done.waitForExistence(timeout: 10) {
                    sleep(2)
                    shot("24-calibration-step-1-dark")
                    let slider = app.sliders["calibration.slider"]
                    if slider.exists { slider.adjust(toNormalizedSliderPosition: 0.6) }
                    sleep(1)
                    shot("25-calibration-step-1-moved-dark")
                    done.tap()
                    XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10), "back on the drill")
                }
            }
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// The same screens in light.
    func testLightAppearance() {
        let app = launch("light", ["-seedMax", "1"])
        XCTAssertTrue(app.buttons["metronome.start"].waitForExistence(timeout: 20))
        shot("30-metronome-light")
        app.tabBars.buttons["Drills"].tap()
        let flagship = app.buttons["exercise.trip16x4"]
        XCTAssertTrue(flagship.waitForExistence(timeout: 10))
        shot("31-drills-light")
        flagship.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        shot("32-setup-light")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        shot("33-settings-light")
        app.navigationBars["Settings"].buttons["Done"].tap()
    }

    /// The screens that need a guitar and an interface, drawn from made-up values (debug builds, -screen).
    func testRunAndResultScreens() {
        for appearance in ["dark", "light"] {
            for screen in ["run", "runUnscored", "result", "resultEndurance", "unscored"] {
                let app = launch(appearance, ["-screen", screen])
                XCTAssertEqual(app.state, .runningForeground)
                sleep(2)
                if screen == "run" || screen == "runUnscored" {
                    XCTAssertTrue(app.buttons["run.stop"].waitForExistence(timeout: 10), "\(screen) shows")
                } else {
                    XCTAssertTrue(app.buttons["result.done"].waitForExistence(timeout: 10), "\(screen) shows")
                }
                shot("40-\(screen)-\(appearance)")
                app.terminate()
            }
        }
    }
}
