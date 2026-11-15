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
        XCTAssertEqual(RunBuilder.accuracy(errors: [10, -25, 40, nil], toleranceMs: 30), 0.5, accuracy: 1e-9)
        XCTAssertEqual(RunBuilder.nextBPM(current: 100, lastPassed: true, step: 4, maxBPM: 200), 104)
        XCTAssertEqual(RunBuilder.nextBPM(current: 100, lastPassed: false, step: 4, maxBPM: 200), 100)
        XCTAssertEqual(RunBuilder.nextBPM(current: 198, lastPassed: true, step: 4, maxBPM: 200), 200)
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
