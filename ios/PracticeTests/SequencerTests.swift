import XCTest
@testable import Practice

final class SequencerTests: XCTestCase {
    let sr = 48000.0

    func collect(_ run: (Int64, Int, (ClickEvent) -> Void) -> Void, frames: Int, block: Int = 512) -> [ClickEvent] {
        var out: [ClickEvent] = []
        var f: Int64 = 0
        while f < Int64(frames) {
            let n = min(block, frames - Int(f))
            run(f, n) { out.append($0) }
            f += Int64(n)
        }
        return out
    }

    func testFreeClicksLandOnExactFrames() {
        var s = FreeSequencer(sampleRate: sr, bpm: 120, beatsPerBar: 4, subdivision: 1, accent: true, startFrame: 0)
        let ev = collect({ s.events(from: $0, count: $1, $2) }, frames: Int(sr * 4))
        XCTAssertEqual(ev.count, 8)
        for (i, e) in ev.enumerated() { XCTAssertEqual(e.frame, Int64(i) * 24000) }
        XCTAssertEqual(ev.map(\.kind), [.accent, .beat, .beat, .beat, .accent, .beat, .beat, .beat])
        XCTAssertEqual(ev.map(\.beat), [0, 1, 2, 3, 0, 1, 2, 3])
    }

    func testBlockSizeDoesNotChangeTiming() {
        var a = FreeSequencer(sampleRate: sr, bpm: 137, beatsPerBar: 4, subdivision: 3, accent: true, startFrame: 100)
        var b = a
        let x = collect({ a.events(from: $0, count: $1, $2) }, frames: Int(sr * 10), block: 64)
        let y = collect({ b.events(from: $0, count: $1, $2) }, frames: Int(sr * 10), block: 1013)
        XCTAssertEqual(x, y)
    }

    func testNoDriftOverTenMinutes() {
        var s = FreeSequencer(sampleRate: sr, bpm: 133, beatsPerBar: 4, subdivision: 4, accent: true, startFrame: 0)
        let ev = collect({ s.events(from: $0, count: $1, $2) }, frames: Int(sr * 600), block: 4096)
        let spacing = sr * 60 / 133 / 4
        let last = ev.last!
        XCTAssertEqual(Double(last.frame), (Double(ev.count - 1) * spacing).rounded(), accuracy: 1)
    }

    func testSubdivisionKinds() {
        var s = FreeSequencer(sampleRate: sr, bpm: 60, beatsPerBar: 2, subdivision: 2, accent: true, startFrame: 0)
        let ev = collect({ s.events(from: $0, count: $1, $2) }, frames: Int(sr * 2))
        XCTAssertEqual(ev.map(\.kind), [.accent, .sub, .beat, .sub])
    }

    func testRoutineBellsCountInAndDone() {
        let r = Routine(name: "t", intervals: [Interval(.play, 2, bpm: 120), Interval(.rest, 3)], rounds: 2, stepBPM: 60, countInBeats: 2)
        let plan = r.plan
        XCTAssertEqual(plan.segments.map(\.kind), [.countIn, .play, .rest, .play, .rest])
        XCTAssertEqual(plan.segments[3].bpm, 180)
        XCTAssertEqual(plan.total, 1 + 2 + 3 + 2 + 3, accuracy: 1e-9)
        var seq = RoutineSequencer(plan: plan, sampleRate: sr, beatsPerBar: 2, subdivision: 1, origin: 0)
        let ev = collect({ seq.events(from: $0, count: $1, $2) }, frames: Int(sr * 12))
        // count-in: 2 clicks at 0 and 0.5 s
        XCTAssertEqual(Array(ev.prefix(2).map(\.kind)), [.countIn, .countIn])
        XCTAssertEqual(ev[1].frame, 24000)
        // the first play interval starts with the bell at 1 s, then 3 more beats at 120
        XCTAssertEqual(ev[2], ClickEvent(frame: 48000, kind: .change, beat: 0))
        XCTAssertEqual(ev[3].frame, 72000)
        XCTAssertEqual(ev.filter { $0.kind == .change }.count, 2)
        // rest: a lower bell at 3 s, then 2 count-in clicks at the next tempo (180) ending at 6 s
        let rest = ev.first { $0.kind == .rest }!
        XCTAssertEqual(rest.frame, 3 * 48000)
        let counts = ev.filter { $0.kind == .countIn && $0.frame > 3 * 48000 && $0.frame < 6 * 48000 }
        XCTAssertEqual(counts.map(\.frame), [Int64(((6 - 2.0 / 3) * sr).rounded()), Int64(((6 - 1.0 / 3) * sr).rounded())])
        XCTAssertEqual(ev.last?.kind, .done)
        XCTAssertEqual(ev.last?.frame, Int64(11 * sr))
        XCTAssertTrue(seq.finished)
    }

    func testRoutineSeekSkipsEarlierClicks() {
        let r = Routine(name: "t", intervals: [Interval(.play, 4, bpm: 60)], countInBeats: 0)
        var seq = RoutineSequencer(plan: r.plan, sampleRate: sr, beatsPerBar: 4, subdivision: 1, origin: -2 * sr, seek: 2)
        let ev = collect({ seq.events(from: $0, count: $1, $2) }, frames: Int(sr * 3))
        XCTAssertEqual(ev.first?.frame, 0)
        XCTAssertEqual(ev.first?.kind, .beat)
        XCTAssertEqual(ev.map(\.beat).prefix(2), [2, 3])
    }

    func testPlanStatus() {
        let r = Routine(name: "t", intervals: [Interval(.play, 60, bpm: 100), Interval(.rest, 30)], rounds: 3, stepBPM: 5, countInBeats: 0)
        let p = r.plan
        let s = p.status(at: 75)!
        XCTAssertEqual(s.segment.kind, .rest)
        XCTAssertEqual(s.timeLeft, 15, accuracy: 1e-9)
        XCTAssertEqual(s.next?.bpm, 105)
        XCTAssertEqual(s.totalLeft, 270 - 75, accuracy: 1e-9)
        XCTAssertTrue(p.status(at: 270)!.finished)
        XCTAssertEqual(r.summary, "3 rounds, 100 to 110 bpm, 4:30")
    }

    func testEventQueuePlaysAtFramesAcrossBlocks() {
        let q = EventQueue()
        q.append([ClickEvent(frame: 10, kind: .beat), ClickEvent(frame: 600, kind: .pluck), ClickEvent(frame: 1500, kind: .done)])
        var got: [ClickEvent] = []
        q.events(from: 0, count: 512) { got.append($0) }
        XCTAssertEqual(got.map(\.frame), [10])
        q.append([ClickEvent(frame: 2000, kind: .beat)])
        q.events(from: 512, count: 512) { got.append($0) }
        q.events(from: 1024, count: 1024) { got.append($0) }
        XCTAssertEqual(got.map(\.frame), [10, 600, 1500, 2000])
    }

    func testTapTempo() {
        var t = TapTempo()
        XCTAssertNil(t.tap(at: 0))
        XCTAssertEqual(t.tap(at: 0.5)!, 120, accuracy: 0.01)
        _ = t.tap(at: 1.0)
        XCTAssertEqual(t.tap(at: 1.5)!, 120, accuracy: 0.01)
        XCTAssertNil(t.tap(at: 10)) // a long pause starts over
    }

    func testVersionCompare() {
        XCTAssertTrue(isNewer("0.1.12", than: "0.1.9"))
        XCTAssertFalse(isNewer("0.1.9", than: "0.1.9"))
        XCTAssertTrue(isNewer("1.0", than: "0.9.99"))
    }

    func testSoundsAreMadeForEveryKind() {
        for raw in 0...ClickKind.pluckAccent.rawValue {
            let s = ClickSounds.make(ClickKind(rawValue: raw)!, sampleRate: 48000)
            XCTAssertGreaterThan(s.count, 100)
            XCTAssertLessThanOrEqual(s.map(abs).max()!, 1.0)
        }
    }
}
