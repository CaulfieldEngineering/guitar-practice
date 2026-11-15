import XCTest
@testable import Practice

final class ScoringTests: XCTestCase {
    func ex(_ groups: [Int], accent: Bool = false) -> Exercise {
        Exercise(id: "t", name: "t", cycleBeats: groups.count, notes: Exercise.expand(groups: groups, accentFirst: accent), tempo: TempoRule(start: 100))
    }

    func testNotesOnTheGrid() {
        let n = ex([3, 4]).notes(bpm: 60, start: 1, seconds: 4)
        XCTAssertEqual(n.count, 14)
        XCTAssertEqual(n[0].time, 1, accuracy: 1e-9)
        XCTAssertEqual(n[1].time, 1 + 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(n[3].time, 2, accuracy: 1e-9)
        XCTAssertEqual(n[4].time, 2.25, accuracy: 1e-9)
        XCTAssertEqual(n.map(\.pick).prefix(5), [.down, .up, .down, .up, .down])
    }

    func testPerfectRun() {
        let notes = ex([4]).notes(bpm: 100, start: 0, seconds: 6)
        let played = notes.map { Onset(time: $0.time, strength: 1) }
        let r = Scoring.score(notes: notes, played: played, window: 0.05)
        XCTAssertEqual(r.score, 100)
        XCTAssertEqual(r.missed, 0)
        XCTAssertEqual(r.extra, 0)
        XCTAssertEqual(r.pct20, 100)
    }

    func testLateMissedAndExtra() {
        let notes = ex([2]).notes(bpm: 60, start: 0, seconds: 4) // 8 notes, 0.5 s apart
        var played = notes.map { Onset(time: $0.time + 0.030, strength: 1) } // 30 ms late
        played.remove(at: 3)                                                 // one missed
        played.append(Onset(time: 1.25, strength: 1))                        // one extra between notes
        played.sort { $0.time < $1.time }
        let r = Scoring.score(notes: notes, played: played, window: 0.1)
        XCTAssertEqual(r.missed, 1)
        XCTAssertEqual(r.extra, 1)
        XCTAssertEqual(r.within20, 0)
        XCTAssertEqual(r.within40, 7)
        XCTAssertEqual(r.meanError, 30, accuracy: 0.01)
        XCTAssertNil(r.errors[3])
        XCTAssertLessThan(r.score, 85)
    }

    func testMatchPrefersClosestPairs() {
        let m = Scoring.match(expected: [0, 0.1], played: [0.06], window: 0.08)
        XCTAssertEqual(m, [nil, 0])
    }

    func testAccents() {
        let notes = ex([4], accent: true).notes(bpm: 60, start: 0, seconds: 2)
        let played = notes.map { Onset(time: $0.time, strength: $0.accent ? 2 : 1) }
        let r = Scoring.score(notes: notes, played: played, window: 0.05)
        XCTAssertEqual(r.accentBeats, 2)
        XCTAssertEqual(r.accentsLanded, 2)
    }

    func testCalibrationIsTheMedian() {
        let clicks = (0..<8).map { Double($0) * 0.75 }
        let played = clicks.enumerated().map { $1 + ($0 == 3 ? 0.2 : 0.045) }
        XCTAssertEqual(Scoring.calibrate(clicks: clicks, played: played)!, 0.045, accuracy: 1e-9)
        XCTAssertNil(Scoring.calibrate(clicks: clicks, played: [0.0, 0.75]))
    }

    func testCycleBuilderAndCues() {
        let e = ex([3, 3, 3, 3, 4, 4, 4, 4])
        let slot = RunBuilder.cycle(e, index: 1, start: 10, bpm: 120, guided: true)
        XCTAssertEqual(slot.duration, 4, accuracy: 1e-9)
        XCTAssertEqual(slot.notes.count, 28)
        XCTAssertEqual(slot.notes.first!.beat, 8)
        let clicks = slot.events.filter { $0.kind == .accent || $0.kind == .beat }
        XCTAssertEqual(clicks.count, 8)
        XCTAssertEqual(clicks.first?.kind, .accent)
        let plucks = slot.events.filter { $0.kind == .pluck || $0.kind == .pluckAccent }
        XCTAssertEqual(plucks.count, 28)
        // The switch to sixteenths (beat 4) and back to triplets (beat 0, after the 4s of the last cycle) are louder.
        let loud = slot.events.filter { $0.kind == .pluckAccent }.map(\.time)
        XCTAssertEqual(loud, [10, 12])
        XCTAssertEqual(RunBuilder.groupSizes(e), [3, 3, 3, 3, 4, 4, 4, 4])
    }

    func testTimedRunCutsTheLastCycle() {
        let e = ex([4, 4, 4, 4])
        let slot = RunBuilder.cycle(e, index: 0, start: 0, bpm: 60, guided: false, limit: 2.5)
        XCTAssertEqual(slot.duration, 2.5, accuracy: 1e-9)
        XCTAssertEqual(slot.notes.count, 10)
        XCTAssertTrue(slot.notes.allSatisfy { $0.time < 2.5 })
    }

    func testEnduranceRollingAndLadder() {
        XCTAssertNil(RunBuilder.rolling([0.9], noteCounts: [10], window: 2))
        XCTAssertEqual(RunBuilder.rolling([0.9, 0.7], noteCounts: [10, 30], window: 2)!, 0.75, accuracy: 1e-9)
        let errors: [Double?] = [5, -5, nil, 200]
        let gaps: [Double] = [0.25, 0.25, 0.25, 0.25]
        XCTAssertEqual(Scoring.accuracy(errors: errors[...], gaps: gaps[...]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(RunBuilder.nextBPM(current: 100, lastPassed: true, step: 4, maxBPM: 200), 104)
        XCTAssertEqual(RunBuilder.nextBPM(current: 100, lastPassed: false, step: 4, maxBPM: 200), 100)
        XCTAssertEqual(RunBuilder.nextBPM(current: 198, lastPassed: true, step: 4, maxBPM: 200), 200)
    }

    /// The windows follow the note spacing: sixteenths at 160 are judged tighter than eighths at 80.
    func testGradedCreditScalesWithTheSpacing() {
        let c = ScoringConfig.standard
        let fast = 60.0 / 160 / 4      // sixteenths at 160: 93.75 ms apart
        let slow = 60.0 / 80 / 2       // eighths at 80: 375 ms apart
        XCTAssertEqual(c.windows(gap: fast).full, 12, accuracy: 1e-9)
        XCTAssertEqual(c.windows(gap: fast).zero, 0.45 * 93.75, accuracy: 1e-9)
        XCTAssertEqual(c.windows(gap: slow).full, 25, accuracy: 1e-9)
        XCTAssertEqual(c.windows(gap: slow).zero, 90, accuracy: 1e-9)
        XCTAssertEqual(c.credit(errorMs: 10, gap: fast), 1)
        XCTAssertEqual(c.credit(errorMs: -10, gap: fast), 1)
        XCTAssertEqual(c.credit(errorMs: 45, gap: fast), 0)
        XCTAssertLessThan(c.credit(errorMs: 30, gap: fast), 0.5)
        XCTAssertGreaterThan(c.credit(errorMs: 30, gap: slow), 0.95)
        XCTAssertEqual(c.credit(errorMs: -50, gap: slow), c.credit(errorMs: 50, gap: slow), accuracy: 1e-12)
        // It only ever falls as the error grows.
        var last = 1.0
        for ms in stride(from: 0.0, through: 120, by: 2) {
            let v = c.credit(errorMs: ms, gap: slow)
            XCTAssertLessThanOrEqual(v, last + 1e-12)
            last = v
        }
        XCTAssertEqual(last, 0)
    }

    func testMissedAndExtraNotesEarnNothing() {
        let gaps: [Double] = [0.25, 0.25]
        let clean: [Double?] = [0, 0]
        XCTAssertEqual(Scoring.accuracy(errors: clean[...], gaps: gaps[...]), 1, accuracy: 1e-9)
        XCTAssertEqual(Scoring.accuracy(errors: clean[...], gaps: gaps[...], extras: 2), 0.5, accuracy: 1e-9)
        let oneMissed: [Double?] = [0, nil]
        XCTAssertEqual(Scoring.accuracy(errors: oneMissed[...], gaps: gaps[...]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Scoring.gaps([0, 0.25, 1]), [0.25, 0.25, 0.75], "the nearest neighbour")
        // The run's score is the same accuracy as a percentage.
        let notes = ex([4]).notes(bpm: 120, start: 0, seconds: 2)         // 16 notes, 125 ms apart
        var played = notes.map { Onset(time: $0.time, strength: 1) }
        played.removeLast(4)                                               // four missed
        let r = Scoring.score(notes: notes, played: played, window: 0.05)
        XCTAssertEqual(r.score, 75)
        XCTAssertEqual(r.full, 12)
        XCTAssertEqual(r.fullMs, 15, accuracy: 1e-9)
    }

    func testScoringConfigFromTheCatalog() throws {
        let partial = try Library.decodeScoring(Data(#"{"schema": 1, "fullMaxMs": 20, "extraWeight": 0.5}"#.utf8))
        XCTAssertEqual(partial.fullMaxMs, 20)
        XCTAssertEqual(partial.extraWeight, 0.5)
        XCTAssertEqual(partial.zeroFraction, ScoringConfig.standard.zeroFraction)
        XCTAssertThrowsError(try Library.decodeScoring(Data(#"{"schema": 1, "zeroFraction": 0.05}"#.utf8)))
        XCTAssertThrowsError(try Library.decodeScoring(Data(#"{"schema": 9}"#.utf8)))
        let bundled = try XCTUnwrap(Library.read(folder: XCTUnwrap(Library.bundledFolder)))
        XCTAssertNotNil(bundled.scoring, "catalog/scoring.json is bundled and reads")
    }

    func testStatsBestsIgnoreGuided() {
        func r(_ score: Int, guided: Bool, bpm: Int = 100, mode: String = "cycles", held: Double? = nil) -> SessionResult {
            SessionResult(id: UUID(), date: Date(), exerciseID: "x", exerciseVersion: 1, exerciseName: "x", mode: mode, ladderStep: 0,
                          guided: guided, startBPM: bpm, topBPM: bpm, seconds: 30, cycles: 4, notes: 10, hits: 10, missed: 0, extra: 0,
                          pct20: 0, pct40: 0, tightMs: 20, closeMs: 40, meanErrorMs: 0, spreadMs: 0, toleranceMs: 30, targetPercent: 85,
                          accuracyPercent: 90, sustainedSeconds: held, score: score, passed: score >= 85, accentsPercent: nil,
                          offsetMs: nil, appVersion: "0")
        }
        let list = [r(70, guided: false), r(99, guided: true), r(88, guided: false), r(0, guided: false, mode: "endurance", held: 95)]
        XCTAssertEqual(Stats.best(list, exerciseID: "x", mode: "cycles", bpm: 100), 88)
        XCTAssertEqual(Stats.best(list, exerciseID: "x", mode: "endurance", bpm: 100), 95)
        XCTAssertEqual(Stats.fastestPass(list, exerciseID: "x"), 100)
    }
}
