import XCTest
@testable import Practice

/// 0.2.2: a player who is locked in has to score high (Joe, 2026-11-17: "I believe I'm playing pretty locked in but I
/// struggled to get above 61% accuracy"). His runs had the latency right (average within 4 ms of the click after a
/// 231 ms offset) and a spread of about 20 ms, but 923 extra notes on 1574: one pick heard twice.
final class TimingFairnessTests: XCTestCase {
    /// A seeded normal generator, so the tests are the same every run.
    struct Gauss {
        var seed: UInt64
        mutating func uniform() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Double(seed >> 11) + 0.5) / Double(1 << 53)
        }
        mutating func next(_ sd: Double) -> Double {
            sd * (-2 * log(uniform())).squareRoot() * cos(2 * .pi * uniform())
        }
    }

    let drill = Exercise(id: "t", name: "t", cycleBeats: 8,
                         notes: Exercise.expand(groups: [3, 3, 3, 3, 4, 4, 4, 4], accentFirst: false),
                         tempo: TempoRule(start: 90))

    /// The notes of a minute of the flagship drill at 90, and picks heard `bias` late with `jitter` of spread.
    func run(bias: Double, jitter: Double, seed: UInt64 = 1) -> (notes: [Exercise.Note], heard: [Onset]) {
        var g = Gauss(seed: seed)
        let notes = drill.notes(bpm: 90, start: 1, seconds: 60)
        let heard = notes.map { Onset(time: $0.time + bias + g.next(jitter), strength: 1) }
        return (notes, heard)
    }

    func testConstantLatencyAndRealJitterScoreHighOnceCalibrated() {
        // The calibration: twelve clicks, the same 200 ms and his own 15 ms of spread.
        var g = Gauss(seed: 9)
        let clicks = (0..<12).map { 1 + Double($0) * 0.667 }
        let picks = clicks.map { $0 + 0.200 + g.next(0.015) }
        let offset = Scoring.calibrate(clicks: clicks, played: picks)!
        XCTAssertEqual(offset, 0.200, accuracy: 0.012)

        let (notes, heard) = run(bias: 0.200, jitter: 0.015)
        let moved = heard.map { Onset(time: $0.time - offset, strength: $0.strength) }
        let r = Scoring.score(notes: notes, played: moved, window: drill.window(bpm: 90))
        XCTAssertGreaterThanOrEqual(r.score, 95, "15 ms of spread is a session player's timing")
        XCTAssertEqual(r.extra, 0)
        XCTAssertEqual(r.missed, 0)
        XCTAssertLessThan(abs(r.meanError), 12)
        XCTAssertEqual(r.spread, 15, accuracy: 2)

        // Uncalibrated the picks are judged against the wrong notes (200 ms is about one sixteenth at 90), so the
        // score means nothing; that is what the calibration is for. Not asserted: it depends on the drill's spacing.
    }

    func testTheScaleAgainstPlayers() {
        // What each spread scores at 90 on this drill (no bias, nothing missed or extra).
        func score(_ sd: Double) -> Int {
            let (notes, heard) = run(bias: 0, jitter: sd, seed: 3)
            return Scoring.score(notes: notes, played: heard, window: drill.window(bpm: 90)).score
        }
        XCTAssertGreaterThanOrEqual(score(0.012), 97)       // session player
        XCTAssertGreaterThanOrEqual(score(0.020), 93)       // his runs' spread
        XCTAssertGreaterThanOrEqual(score(0.030), 82)       // good amateur, still over the 85 pass mark on triplets
        XCTAssertLessThan(score(0.050), 80)                 // beginner
        XCTAssertEqual(Scoring.band(spreadMs: 12), "Locked")
        XCTAssertEqual(Scoring.band(spreadMs: 20), "Tight")
        XCTAssertEqual(Scoring.band(spreadMs: 30), "Good")
        XCTAssertEqual(Scoring.band(spreadMs: 50), "Loose")
    }

    func testOnePickHeardTwiceIsOneNote() {
        let (notes, clean) = run(bias: 0, jitter: 0.020, seed: 5)
        // Every other pick also heard again 50 ms later, much weaker: his runs had about one extra for every two notes.
        var stream: [Onset] = []
        for (i, o) in clean.enumerated() {
            stream.append(o)
            if i % 2 == 0 { stream.append(Onset(time: o.time + 0.050, strength: 0.2)) }
        }
        stream.sort { $0.time < $1.time }
        let w = drill.window(bpm: 90)
        let before = Scoring.score(notes: notes, played: stream, window: w)
        XCTAssertGreaterThan(before.extra, notes.count / 3)
        XCTAssertLessThan(before.score, 70, "how 0.2.1 scored it")

        let kept = Scoring.dropDoubles(stream, within: w)
        let after = Scoring.score(notes: notes, played: kept, window: w)
        XCTAssertEqual(after.extra, 0)
        XCTAssertGreaterThanOrEqual(after.score, 93)
    }

    func testARealExtraPickStillCounts() {
        var played: [Onset] = []
        XCTAssertTrue(Scoring.addPick(Onset(time: 1.000, strength: 1), to: &played, within: 0.075))
        // As strong as the note: a second pick, not an echo.
        XCTAssertTrue(Scoring.addPick(Onset(time: 1.050, strength: 0.9), to: &played, within: 0.075))
        // Weak and close: the same pick.
        XCTAssertFalse(Scoring.addPick(Onset(time: 1.090, strength: 0.1), to: &played, within: 0.075))
        // Weak first, the real attack just after: the attack is kept in its place.
        XCTAssertTrue(Scoring.addPick(Onset(time: 2.000, strength: 0.1), to: &played, within: 0.075))
        XCTAssertFalse(Scoring.addPick(Onset(time: 2.010, strength: 1), to: &played, within: 0.075))
        XCTAssertEqual(played.map(\.time), [1.000, 1.050, 2.010])
    }

    func testDetectorIgnoresThePicksOwnRingAndKeepsSoftNotes() {
        // Sixteenths at 90, an accent on each beat and the other three 10 dB softer, every pick with a small second
        // burst 45 ms after it (the string ringing back up, the pick leaving it). Only the picks are notes.
        let sr = 48000.0
        var seed: UInt32 = 11
        func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(Int32(bitPattern: seed)) / Float(Int32.max) }
        let times = stride(from: 0.5, to: 3.0, by: 60.0 / 90 / 4).map { $0 }
        var x = (0..<Int(sr * 3.2)).map { _ in rnd() * 0.002 }
        func burst(_ t: Double, _ amp: Float) {
            let start = Int(t * sr)
            for k in 0..<Int(0.08 * sr) where start + k < x.count {
                x[start + k] += amp * rnd() * Float(exp(-Double(k) / sr * 40))
            }
        }
        for (i, t) in times.enumerated() {
            let amp: Float = i % 4 == 0 ? 0.8 : 0.25
            burst(t, amp); burst(t + 0.045, amp * 0.2)
        }
        var d = OnsetDetector(sampleRate: sr)
        var found = d.process(x, time: 0)
        if let last = d.flush() { found.append(last) }
        XCTAssertEqual(found.count, times.count)
        for (o, t) in zip(found, times) { XCTAssertEqual(o.time, t, accuracy: 0.002) }
    }
}
