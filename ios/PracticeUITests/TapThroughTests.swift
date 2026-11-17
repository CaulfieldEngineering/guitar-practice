import XCTest

/// Taps through every screen on a simulator with no audio interface, the way Joe uses the app (0.1.4 crashed on
/// choosing a drill and froze on the Settings gear; on 0.1.6 a drill kept playing after he left it and he could not
/// find how to stop it), and keeps a screenshot of each screen, dark and light, in the test results (the workflow
/// puts them on the ci-screens branch).
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

    /// "running" or "stopped": whether the app's one player is making sound (a debug-only line on the Drills list).
    private func engineState(_ app: XCUIApplication) -> String {
        let t = app.staticTexts["engine.state"]
        return t.waitForExistence(timeout: 10) ? t.label : "missing"
    }

    private func waitForEngine(_ app: XCUIApplication, _ wanted: String) -> Bool {
        for _ in 0..<20 {
            if engineState(app) == wanted { return true }
            usleep(250_000)
        }
        return false
    }

    func testDrillSettingsAndProgress() {
        let app = launch()

        // Metronome: starts; on the Drills tab a bar says it is running and stops it.
        let metro = app.buttons["metronome.start"]
        XCTAssertTrue(metro.waitForExistence(timeout: 20))
        shot("01-metronome-dark")
        metro.tap()
        XCTAssertEqual(app.state, .runningForeground)
        app.tabBars.buttons["Drills"].tap()
        let drill = app.buttons["exercise.alt8"]
        XCTAssertTrue(drill.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForEngine(app, "running"), "the metronome is ticking")
        let barStop = app.buttons["running.stop"]
        XCTAssertTrue(barStop.waitForExistence(timeout: 5), "the running bar shows on the other tab")
        shot("02-drills-running-bar-dark")
        barStop.tap()
        XCTAssertTrue(waitForEngine(app, "stopped"), "the bar's Stop stops the metronome")
        shot("03-drills-table-dark")

        // Open a drill. Start with the audio input on and no interface: a clear message, no crash.
        drill.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10), "the drill's own screen opens")
        shot("04-setup-dark")
        app.buttons["start"].tap()
        XCTAssertTrue(app.staticTexts["message"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        shot("05-setup-no-interface-dark")
        app.buttons["Back"].tap()

        // The flagship with the audio input off: it starts with no interface, pauses on a tap, resumes, and stops.
        let flagship = app.buttons["exercise.trip16x4"]
        XCTAssertTrue(flagship.waitForExistence(timeout: 10))
        flagship.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        app.swipeUp()
        let input = app.switches["Audio Input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        shot("06-setup-audio-input-off-dark")
        startRun(app)
        let pause = app.buttons["run.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15), "the run screen shows, with Pause and Stop on it")
        XCTAssertTrue(app.buttons["run.stop"].exists, "Stop is always on the run screen")
        sleep(5)
        shot("07-run-audio-input-off-dark")
        pause.tap()
        let resume = app.buttons["run.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "a tap on Pause holds the run")
        XCTAssertTrue(app.buttons["run.end"].exists)
        shot("08-run-paused-dark")
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 15), "Resume picks it up")
        sleep(7)
        app.buttons["run.stop"].tap()
        let done = app.buttons["result.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Stop ends the run")
        shot("09-result-audio-input-off-dark")
        done.tap()

        // Leaving a drill that is running ends it: start, pause, go back by the edge swipe or by End, and nothing plays.
        startRun(app)
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        sleep(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        if !flagship.waitForExistence(timeout: 3) {
            // The swipe is not offered while a run is on the screen: end it and go back.
            if app.buttons["run.stop"].exists { app.buttons["run.stop"].tap() } else if app.buttons["run.end"].exists { app.buttons["run.end"].tap() }
            if done.waitForExistence(timeout: 10) { done.tap() }
            XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10))
            app.buttons["Back"].tap()
        }
        XCTAssertTrue(flagship.waitForExistence(timeout: 10), "back on the list")
        XCTAssertTrue(waitForEngine(app, "stopped"), "nothing keeps playing after the drill is left")
        XCTAssertFalse(app.buttons["running.stop"].exists, "and no running bar")

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

    /// Taps the debug-only button that fakes a route change (an interface plugged in, the Shokz picked), on
    /// whichever screen is in front.
    private func changeRoute(_ app: XCUIApplication) {
        let buttons = app.buttons.matching(identifier: "debug.routeChange").allElementsBoundByIndex
        let b = buttons.first { $0.exists && $0.isHittable } ?? buttons.first
        XCTAssertNotNil(b, "the route-change button is there")
        b?.tap()
    }

    /// Joe, 2026-11-16: "during the calibrate or anywhere else, when I swap the audio device it closes that current
    /// window". A route change on each screen keeps the screen, keeps the sound going and says what changed.
    func testRouteChangeKeepsEveryScreen() {
        let app = launch("dark", ["-debugRoute", "1"])
        let notice = app.staticTexts["route.notice"]

        // The metronome keeps ticking.
        let metro = app.buttons["metronome.start"]
        XCTAssertTrue(metro.waitForExistence(timeout: 20))
        metro.tap()
        changeRoute(app)
        XCTAssertTrue(notice.waitForExistence(timeout: 5), "a notice says the device changed")
        shot("50-route-metronome-dark")
        app.tabBars.buttons["Drills"].tap()
        XCTAssertTrue(waitForEngine(app, "running"), "the metronome carried on across the change")
        app.buttons["running.stop"].tap()
        XCTAssertTrue(waitForEngine(app, "stopped"))

        // A drill's setup stays open.
        let flagship = app.buttons["exercise.trip16x4"]
        XCTAssertTrue(flagship.waitForExistence(timeout: 10))
        flagship.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        changeRoute(app)
        sleep(1)
        XCTAssertTrue(app.buttons["start"].exists, "the setup is still there")
        shot("51-route-setup-dark")

        // A run goes on.
        app.swipeUp()
        let input = app.switches["Audio Input"]
        if input.waitForExistence(timeout: 5), (input.value as? String) == "1" { input.tap() }
        startRun(app)
        let pause = app.buttons["run.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        sleep(2)
        changeRoute(app)
        sleep(2)
        XCTAssertTrue(pause.exists, "the run is still running, not paused or closed")
        shot("52-route-run-dark")
        app.buttons["run.stop"].tap()
        let done = app.buttons["result.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()

        // The calibration's first step stays on screen.
        app.swipeUp()
        let options = app.buttons["Options"]
        if options.waitForExistence(timeout: 5) { options.tap(); app.swipeUp() }
        let calibrate = app.buttons["calibrate"]
        if calibrate.waitForExistence(timeout: 5) {
            calibrate.tap()
            let calDone = app.buttons["calibration.done"]
            XCTAssertTrue(calDone.waitForExistence(timeout: 10))
            sleep(1)
            changeRoute(app)
            sleep(2)
            XCTAssertTrue(calDone.exists, "the calibration did not close")
            shot("53-route-calibration-dark")
            calDone.tap()
        }
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        app.buttons["Back"].tap()

        // Settings and its Audio screen stay open.
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.buttons["settings.audio"].tap()
        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 10), "the Audio screen opens")
        sleep(2)
        shot("54-audio-dark")
        app.swipeUp()
        shot("55-audio-scrolled-dark")
        app.swipeDown()
        changeRoute(app)
        sleep(2)
        XCTAssertTrue(app.navigationBars["Audio"].exists, "the Audio screen did not close")
        shot("56-route-audio-dark")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// The Audio screen in light, and its Input list.
    func testAudioScreenLight() {
        let app = launch("light")
        XCTAssertTrue(app.buttons["metronome.start"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Drills"].tap()
        XCTAssertTrue(app.buttons["Settings"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.buttons["settings.audio"].tap()
        XCTAssertTrue(app.navigationBars["Audio"].waitForExistence(timeout: 10))
        sleep(2)
        shot("57-audio-light")
        let inputRow = app.buttons["audio.input"]
        if inputRow.waitForExistence(timeout: 5) {
            inputRow.tap()
            sleep(1)
            shot("58-audio-input-list-light")
            if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap() }
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Start, and past the spoken intro if it is on.
    private func startRun(_ app: XCUIApplication) {
        app.buttons["start"].tap()
        let skip = app.buttons["intro.skip"]
        if skip.waitForExistence(timeout: 4) { skip.tap() }
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
        shot("31-drills-table-light")
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
            for screen in ["run", "runUnscored", "runFretted", "runPaused", "result", "resultEndurance", "unscored"] {
                let app = launch(appearance, ["-screen", screen])
                XCTAssertEqual(app.state, .runningForeground)
                sleep(2)
                switch screen {
                case "run", "runUnscored", "runFretted":
                    XCTAssertTrue(app.buttons["run.stop"].waitForExistence(timeout: 10), "\(screen) shows")
                case "runPaused":
                    XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 10), "\(screen) shows")
                default:
                    XCTAssertTrue(app.buttons["result.done"].waitForExistence(timeout: 10), "\(screen) shows")
                }
                shot("40-\(screen)-\(appearance)")
                app.terminate()
            }
        }
    }
}
