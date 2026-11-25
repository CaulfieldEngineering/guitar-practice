import XCTest

/// Taps through every screen on a simulator with no audio interface, the way Joe uses the app, and keeps a
/// screenshot of each screen, dark and light, in the test results (the workflow puts them on the ci-screens branch).
/// 0.3.0: four tabs (Metronome, Drills, Routines, Progress), one drill, the setup's detail screens, routines.
final class TapThroughTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

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

    private func back(_ app: XCUIApplication) {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.waitForExistence(timeout: 5) { b.tap() }
    }

    /// A Form toggle row: tapping the row's middle lands on its label, which does not flip it, so tap the switch itself
    /// (the row's own switch, at its trailing edge) and check that it took.
    private func setSwitch(_ row: XCUIElement, on: Bool) {
        let want = on ? "1" : "0"
        for attempt in 0..<3 where (row.value as? String) != want {
            let inner = row.switches.firstMatch
            if attempt == 0, inner.exists { inner.tap() } else { row.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
            for _ in 0..<10 where (row.value as? String) != want { usleep(150_000) }
        }
        XCTAssertEqual(row.value as? String, want, "\(row.identifier) is \(on ? "on" : "off")")
    }

    private func startRun(_ app: XCUIApplication) {
        app.buttons["start"].tap()
        let skip = app.buttons["intro.skip"]
        if skip.waitForExistence(timeout: 4) { skip.tap() }
    }

    func testDrillAndItsSetup() {
        let app = launch()

        let metro = app.buttons["metronome.start"]
        XCTAssertTrue(metro.waitForExistence(timeout: 20))
        shot("01-metronome-dark")
        metro.tap()
        app.tabBars.buttons["Drills"].tap()
        let drill = app.buttons["exercise.trip16x4"]
        XCTAssertTrue(drill.waitForExistence(timeout: 10), "the one drill is offered")
        XCTAssertFalse(app.buttons["exercise.alt8"].exists, "the archived drills are not")
        XCTAssertTrue(waitForEngine(app, "running"))
        let barStop = app.buttons["running.stop"]
        XCTAssertTrue(barStop.waitForExistence(timeout: 5))
        shot("02-drills-running-bar-dark")
        barStop.tap()
        XCTAssertTrue(waitForEngine(app, "stopped"))
        shot("03-drills-table-dark")

        drill.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        shot("04-setup-dark")
        app.swipeUp()
        shot("04b-setup-scrolled-dark")

        // Ascending tempo: per loop, then by accuracy with its thresholds.
        app.buttons["setup.ascending"].tap()
        XCTAssertTrue(app.buttons["plan.perLoop"].waitForExistence(timeout: 5))
        app.buttons["plan.perLoop"].tap()
        shot("05-ascending-per-loop-dark")
        app.buttons["plan.accuracy"].tap()
        sleep(1)
        shot("06-ascending-by-accuracy-dark")
        app.swipeUp()
        shot("07-ascending-by-accuracy-scrolled-dark")
        if !app.buttons["plan.off"].exists { app.swipeDown() }
        if app.buttons["plan.off"].waitForExistence(timeout: 3) { app.buttons["plan.off"].tap() }
        back(app)

        // Length: Challenge.
        XCTAssertTrue(app.buttons["setup.length"].waitForExistence(timeout: 5))
        app.buttons["setup.length"].tap()
        if app.buttons["length.challenge"].waitForExistence(timeout: 5) {
            app.buttons["length.challenge"].tap()
            shot("08-length-challenge-dark")
            app.buttons["length.cycles"].tap()
        }
        back(app)

        // Options, and the tuning override.
        XCTAssertTrue(app.buttons["setup.options"].waitForExistence(timeout: 5))
        app.buttons["setup.options"].tap()
        sleep(1)
        shot("09-options-dark")
        app.swipeUp()
        let tuning = app.buttons["Tuning"]
        if tuning.waitForExistence(timeout: 5) {
            tuning.tap()
            sleep(1)
            shot("10-tuning-dark")
            back(app)
        }
        back(app)

        // A run with the audio input off: pause, resume, stop, result.
        let input = app.switches["setup.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        setSwitch(input, on: false)
        startRun(app)
        let pause = app.buttons["run.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        sleep(5)
        shot("11-run-unscored-dark")
        pause.tap()
        XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 10))
        shot("12-run-paused-dark")
        app.buttons["run.resume"].tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        sleep(4)
        app.buttons["run.stop"].tap()
        let primary = app.buttons["result.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        shot("13-result-unscored-dark")
        app.buttons["result.done"].tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        back(app)
        XCTAssertTrue(waitForEngine(app, "stopped"), "nothing keeps playing after the drill is left")

        // With the audio input on and no interface: a clear message, no crash.
        drill.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        setSwitch(input, on: true)
        app.buttons["start"].tap()
        XCTAssertTrue(app.staticTexts["message"].waitForExistence(timeout: 10))
        shot("14-setup-no-interface-dark")
        back(app)

        // Progress and Settings.
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10))
        shot("15-progress-dark")
        app.buttons["settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        shot("16-settings-dark")
        app.swipeUp()
        shot("17-settings-scrolled-dark")
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testRoutines() {
        let app = launch()
        XCTAssertTrue(app.buttons["metronome.start"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Routines"].tap()
        let starter = app.buttons["routine.Picking session"]
        XCTAssertTrue(starter.waitForExistence(timeout: 10), "the starter routine is there")
        shot("20-routines-dark")
        starter.tap()
        XCTAssertTrue(app.buttons["routine.start"].waitForExistence(timeout: 10))
        shot("21-routine-editor-dark")

        // A block's editor.
        let warm = app.buttons["block.warmup"].firstMatch
        if warm.waitForExistence(timeout: 5) {
            warm.tap()
            sleep(1)
            shot("22-block-warmup-dark")
            back(app)
        }
        let drillBlock = app.buttons["block.drill"].firstMatch
        if drillBlock.waitForExistence(timeout: 5) {
            drillBlock.tap()
            sleep(1)
            shot("23-block-drill-dark")
            back(app)
        }

        // Run it: the countdown, the warm-up block, pause, skip, end.
        app.buttons["routine.start"].tap()
        XCTAssertTrue(app.staticTexts["runner.countdown"].waitForExistence(timeout: 5), "3, 2, 1 before the first block")
        shot("24-runner-countdown-dark")
        XCTAssertTrue(app.staticTexts["runner.clock"].waitForExistence(timeout: 8), "the warm-up's clock")
        sleep(2)
        shot("25-runner-warmup-dark")
        app.buttons["runner.pause"].tap()
        XCTAssertTrue(app.buttons["runner.resume"].waitForExistence(timeout: 5))
        shot("26-runner-paused-dark")
        app.buttons["runner.resume"].tap()
        app.buttons["runner.skip"].tap()
        sleep(5)
        shot("27-runner-drill-block-dark")
        if app.buttons["runner.pause"].exists { app.buttons["runner.pause"].tap() }
        if app.buttons["runner.end"].waitForExistence(timeout: 5) {
            app.buttons["runner.end"].tap()
            let end = app.buttons["End"].firstMatch
            if end.waitForExistence(timeout: 5) { end.tap() }
        }
        if app.buttons["runner.done"].waitForExistence(timeout: 10) {
            shot("28-runner-finished-dark")
            app.buttons["runner.done"].tap()
        }
        XCTAssertEqual(app.state, .runningForeground)

        // A new routine.
        back(app)
        app.buttons["routines.add"].tap()
        XCTAssertTrue(app.buttons["routine.addBlock"].waitForExistence(timeout: 10))
        shot("29-new-routine-dark")
    }

    /// Joe, 2026-11-16: "when I swap the audio device it closes that current window". A route change keeps each screen.
    func testRouteChangeKeepsEveryScreen() {
        let app = launch("dark", ["-debugRoute", "1"])
        let notice = app.staticTexts["route.notice"]
        let metro = app.buttons["metronome.start"]
        XCTAssertTrue(metro.waitForExistence(timeout: 20))
        metro.tap()
        changeRoute(app)
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        app.tabBars.buttons["Drills"].tap()
        XCTAssertTrue(waitForEngine(app, "running"))
        app.buttons["running.stop"].tap()
        let drill = app.buttons["exercise.trip16x4"]
        XCTAssertTrue(drill.waitForExistence(timeout: 10))
        drill.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        changeRoute(app)
        sleep(1)
        XCTAssertTrue(app.buttons["start"].exists, "the setup is still there")
        let input = app.switches["setup.input"]
        if input.waitForExistence(timeout: 5) { setSwitch(input, on: false) }
        startRun(app)
        let pause = app.buttons["run.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 15))
        sleep(2)
        changeRoute(app)
        sleep(2)
        XCTAssertTrue(pause.exists, "the run goes on")
        app.buttons["run.stop"].tap()
        XCTAssertTrue(app.buttons["result.done"].waitForExistence(timeout: 10))
        app.buttons["result.done"].tap()
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func changeRoute(_ app: XCUIApplication) {
        let buttons = app.buttons.matching(identifier: "debug.routeChange").allElementsBoundByIndex
        let b = buttons.first { $0.exists && $0.isHittable } ?? buttons.last
        XCTAssertNotNil(b)
        b?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func testLightAppearance() {
        let app = launch("light", ["-seedMax", "1"])
        XCTAssertTrue(app.buttons["metronome.start"].waitForExistence(timeout: 20))
        shot("30-metronome-light")
        app.tabBars.buttons["Drills"].tap()
        let drill = app.buttons["exercise.trip16x4"]
        XCTAssertTrue(drill.waitForExistence(timeout: 10))
        shot("31-drills-light")
        drill.tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 10))
        shot("32-setup-with-max-light")
        back(app)
        app.tabBars.buttons["Routines"].tap()
        sleep(1)
        shot("33-routines-light")
        app.tabBars.buttons["Progress"].tap()
        sleep(1)
        shot("34-progress-light")
        app.buttons["settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        shot("35-settings-light")
        app.navigationBars["Settings"].buttons["Done"].tap()
    }

    /// The screens that need a guitar and an interface, from made-up values (debug builds, -screen).
    func testRunAndResultScreens() {
        for appearance in ["dark", "light"] {
            for screen in ["run", "runAccuracy", "runChallenge", "runUnscored", "runFretted", "runPaused", "break",
                           "result", "resultAscending", "resultChallenge", "unscored", "routineDone"] {
                let app = launch(appearance, ["-screen", screen])
                XCTAssertEqual(app.state, .runningForeground)
                sleep(2)
                switch screen {
                case "run", "runAccuracy", "runChallenge", "runUnscored", "runFretted":
                    XCTAssertTrue(app.buttons["run.stop"].waitForExistence(timeout: 10), "\(screen) shows")
                case "runPaused": XCTAssertTrue(app.buttons["run.resume"].waitForExistence(timeout: 10))
                case "break": XCTAssertTrue(app.buttons["break.skip"].waitForExistence(timeout: 10))
                case "unscored": XCTAssertTrue(app.buttons["result.primary"].waitForExistence(timeout: 10))
                case "routineDone": break
                default: XCTAssertTrue(app.buttons["result.primary"].waitForExistence(timeout: 10), "\(screen) shows")
                }
                shot("40-\(screen)-\(appearance)")
                app.terminate()
            }
        }
    }
}
