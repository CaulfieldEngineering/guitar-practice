import XCTest
@testable import Practice

/// What crashed 0.1.4 on the phone (setting the tempo recursed inside its own didSet) and the zones.
@MainActor
final class ModelTests: XCTestCase {
    func testMetronomeTempoChangesAndClamps() {
        let p = Player()
        let start = p.bpm
        p.setBPM(start + 1)
        XCTAssertEqual(p.bpm, start + 1)
        p.setBPM(10_000)
        XCTAssertEqual(p.bpm, Routine.bpmRange.upperBound)
        p.setBPM(-5)
        XCTAssertEqual(p.bpm, Routine.bpmRange.lowerBound)
        p.setBPM(start)
    }

    func testChoosingEveryExerciseAndLevelDoesNotCrash() {
        let pa = PlayAlong(player: Player(), history: History(inMemory: true))
        XCTAssertFalse(pa.exercises.isEmpty)
        for ex in pa.exercises {
            pa.select(ex.id)
            XCTAssertEqual(pa.exercise.id, ex.id)
            XCTAssertTrue((ex.tempo.min...ex.tempo.max).contains(pa.bpm))
            pa.setBPM(pa.bpm + 2)
            for lv in ex.levels { pa.apply(lv) }
            pa.guided.toggle()
            pa.session.kind = .endurance
            pa.session.cycles += 1
            pa.intro.toggle()
            pa.resume.toggle()
        }
        // Remembered per drill.
        let first = pa.exercises[0].id, second = pa.exercises[1].id
        pa.select(first); pa.guided = false; pa.setBPM(97)
        pa.select(second); pa.guided = true
        pa.select(first)
        XCTAssertFalse(pa.guided)
        XCTAssertEqual(pa.bpm, 97)
    }

    func testStartWithoutAnInterfaceSaysSoAndDoesNotCrash() {
        let pa = PlayAlong(player: Player(), history: History(inMemory: true))
        pa.allowPhoneMic = false
        pa.start()
        if !pa.interfacePresent {
            XCTAssertEqual(pa.phase, .ready)
            XCTAssertEqual(pa.message, "Plug in your audio interface: the guitar comes in through it.")
        }
    }

    func testZones() {
        let z = TempoZones.standard
        let z3 = z.zone("z3")!
        XCTAssertEqual(TempoZones.range(z3, max: 150), 120...135)
        XCTAssertEqual(z.start(z3, max: 150), 128)
        var s = SessionSettings()
        s.kind = .endurance
        XCTAssertEqual(z.suggested(for: s)?.id, "z2")
        s.kind = .cycles; s.ladderStep = 4
        XCTAssertEqual(z.suggested(for: s)?.id, "z4")
        XCTAssertEqual(z.zone(forBPM: 132, max: 150)?.id, "z3")
        XCTAssertEqual(z.zone(forBPM: 156, max: 150)?.id, "z5")
        XCTAssertEqual(z.zone(forBPM: 80, max: 150)?.id, "z1")
    }

    func testBundledZonesDecode() throws {
        let c = try XCTUnwrap(Library.read(folder: XCTUnwrap(Library.bundledFolder)))
        XCTAssertEqual(c.zones?.zones.count, 5)
        XCTAssertEqual(c.zones?.suggest["endurance"], "z2")
    }

    func testLearnedMaxIsTheSecondBestRecentPass() {
        func r(_ day: Int, _ top: Int, passed: Bool, guided: Bool = false) -> SessionResult {
            SessionResult(id: UUID(), date: Date(timeIntervalSince1970: Double(day) * 86_400), exerciseID: "x", exerciseVersion: 1,
                          exerciseName: "x", mode: "cycles", ladderStep: 0, guided: guided, startBPM: top, topBPM: top,
                          seconds: 30, cycles: 4, notes: 10, hits: 10, missed: 0, extra: 0, pct20: 0, pct40: 0, tightMs: 20,
                          closeMs: 40, meanErrorMs: 0, spreadMs: 0, toleranceMs: 30, targetPercent: 85, accuracyPercent: 90,
                          sustainedSeconds: nil, score: passed ? 90 : 50, passed: passed, accentsPercent: nil, offsetMs: nil,
                          appVersion: "0")
        }
        XCTAssertNil(Stats.learnedTempo([r(1, 100, passed: false)], exerciseID: "x"))
        XCTAssertEqual(Stats.learnedTempo([r(1, 120, passed: true)], exerciseID: "x"), 116)
        var list = [r(1, 140, passed: true)]                                      // old, outside the last ten
        list += (0..<9).map { r(2 + $0, 100 + $0, passed: $0 % 2 == 0) }
        list.append(r(20, 130, passed: true))                                    // one lucky run
        list.append(r(21, 150, passed: true, guided: true))                      // guided: not counted
        XCTAssertEqual(Stats.learnedTempo(list, exerciseID: "x"), 108)
    }
}
