import XCTest
@testable import Practice

final class OnsetTests: XCTestCase {
    /// Picked notes: short decaying noise bursts at known times over a quiet noise floor.
    func signal(sr: Double, seconds: Double, at times: [Double], amp: Float = 0.5) -> [Float] {
        var seed: UInt32 = 7
        func rnd() -> Float { seed = seed &* 1664525 &+ 1013904223; return Float(Int32(bitPattern: seed)) / Float(Int32.max) }
        var x = (0..<Int(sr * seconds)).map { _ in rnd() * 0.002 }
        for t in times {
            let start = Int(t * sr)
            for k in 0..<Int(0.08 * sr) where start + k < x.count {
                x[start + k] += amp * rnd() * Float(exp(-Double(k) / sr * 40))
            }
        }
        return x
    }

    func testFindsPicksWithinTwoMilliseconds() {
        let sr = 48000.0
        let times = stride(from: 0.5, to: 4.0, by: 0.125).map { $0 } // sixteenths at 120
        let x = signal(sr: sr, seconds: 4.2, at: times)
        var d = OnsetDetector(sampleRate: sr)
        var found: [Onset] = []
        var i = 0
        while i < x.count {   // in blocks, as the input tap delivers them
            let n = min(4800, x.count - i)
            found += d.process(Array(x[i..<(i + n)]), time: Double(i) / sr)
            i += n
        }
        if let last = d.flush() { found.append(last) }
        XCTAssertEqual(found.count, times.count)
        for (o, t) in zip(found, times) { XCTAssertEqual(o.time, t, accuracy: 0.002) }
    }

    func testSilenceAndNoiseGiveNothing() {
        let sr = 44100.0
        var d = OnsetDetector(sampleRate: sr)
        let x = signal(sr: sr, seconds: 3, at: [])
        var found = d.process(x, time: 0)
        if let last = d.flush() { found.append(last) }
        XCTAssertTrue(found.isEmpty)
    }

    func testAccentedPicksAreStronger() {
        let sr = 48000.0
        let loud = signal(sr: sr, seconds: 1, at: [0.2], amp: 0.8)
        let soft = signal(sr: sr, seconds: 1, at: [0.2], amp: 0.2)
        var a = OnsetDetector(sampleRate: sr), b = OnsetDetector(sampleRate: sr)
        let oa = a.process(loud, time: 0) + [a.flush()].compactMap { $0 }
        let ob = b.process(soft, time: 0) + [b.flush()].compactMap { $0 }
        XCTAssertGreaterThan(oa[0].strength, ob[0].strength * 4)
    }
}

final class SchemaTests: XCTestCase {
    func testBundledCatalogDecodes() throws {
        let folder = try XCTUnwrap(Library.bundledFolder)
        let c = try XCTUnwrap(Library.read(folder: folder))
        XCTAssertEqual(c.exercises.first?.id, "trip16x4")
        XCTAssertEqual(c.exercises.first?.cycleBeats, 8)
        XCTAssertEqual(c.exercises.first?.notes.count, 28)
        XCTAssertEqual(c.exercises.first?.session.kind, .endurance)
        XCTAssertFalse(c.exercises.first!.intro.isEmpty)
        XCTAssertTrue(c.exercises.contains { $0.id == "gallop" && $0.notes.count == 3 && $0.notes[0].accent })
        XCTAssertTrue(c.routines.contains { $0.name == "Starting Protocol" && $0.intervals.count == 8 })
        XCTAssertEqual(Set(c.exercises.map(\.id)).count, c.exercises.count, "ids are unique")
    }

    func testShorthandAndFullFormsAgree() throws {
        let json = """
        {"schema": 1, "exercises": [
          {"id": "a", "name": "A", "groups": [3], "tempo": {"start": 90}},
          {"id": "b", "name": "B", "cycleBeats": 1, "tempo": {"start": 90}, "notes": [
            {"at": {"beat": 0, "step": 0, "of": 3}, "pick": "down"},
            {"at": {"beat": 0, "step": 1, "of": 3}, "pick": "up"},
            {"at": {"beat": 0, "step": 2, "of": 3}, "pick": "down"}]}
        ]}
        """
        let list = try Library.decodeExercises(Data(json.utf8))
        XCTAssertEqual(list[0].notes, list[1].notes)
        XCTAssertEqual(list[0].tempo.max, 300)
        XCTAssertEqual(list[0].scoring, .standard)
    }

    func testNewerSchemasAreRefusedOrSkipped() throws {
        let newerFile = #"{"schema": 2, "exercises": []}"#
        XCTAssertThrowsError(try Library.decodeExercises(Data(newerFile.utf8))) { e in
            XCTAssertEqual(e as? LibraryError, .newerSchema(2))
        }
        let mixed = """
        {"schema": 1, "exercises": [
          {"id": "ok", "name": "OK", "groups": [2], "tempo": {"start": 90}},
          {"schema": 2, "id": "new", "name": "New", "groups": [2], "tempo": {"start": 90}},
          {"id": "broken", "name": "Broken", "tempo": {"start": 90}}
        ]}
        """
        let list = try Library.decodeExercises(Data(mixed.utf8))
        XCTAssertEqual(list.map(\.id), ["ok"])
    }

    func testIndexRejectsPathsOutsideTheCatalog() {
        let bad = #"{"schema": 1, "version": 3, "files": [{"path": "../x.json", "kind": "exercises"}]}"#
        XCTAssertThrowsError(try Library.decodeIndex(Data(bad.utf8)))
    }

    func testMergeLaterWins() {
        let a = Exercise(id: "x", name: "Old", cycleBeats: 1, notes: [], tempo: TempoRule(start: 1))
        let b = Exercise(id: "x", name: "New", cycleBeats: 1, notes: [], tempo: TempoRule(start: 1))
        let c = Exercise(id: "y", name: "Y", cycleBeats: 1, notes: [], tempo: TempoRule(start: 1))
        let m = Library.merge([[a, c], [b]], id: \.id)
        XCTAssertEqual(m.map(\.name), ["New", "Y"])
    }

    func testRoutineDataDefaults() throws {
        let json = #"{"schema": 1, "routines": [{"name": "R", "intervals": [{"kind": "rest", "seconds": 10}]}]}"#
        let r = try Library.decodeRoutines(Data(json.utf8))[0]
        XCTAssertEqual(r.rounds, 1)
        XCTAssertEqual(r.countInBeats, 4)
        XCTAssertEqual(r.intervals[0].bpm, 100)
    }

    func testResultsRoundTrip() throws {
        let r = SessionResult(id: UUID(), date: Date(timeIntervalSince1970: 1_800_000_000), exerciseID: "x", exerciseVersion: 2,
                              exerciseName: "X", mode: "endurance", ladderStep: 4, guided: false, startBPM: 90, topBPM: 98,
                              seconds: 64, cycles: 8, notes: 224, hits: 220, missed: 4, extra: 1, pct20: 70, pct40: 95,
                              tightMs: 20, closeMs: 40, meanErrorMs: 4.5, spreadMs: 11, toleranceMs: 30, targetPercent: 85,
                              accuracyPercent: 91, sustainedSeconds: 56, score: 88, passed: true, accentsPercent: nil,
                              offsetMs: 42, appVersion: "0.1.1")
        let data = try History.encoder.encode(r)
        XCTAssertEqual(try History.decoder.decode(SessionResult.self, from: data), r)
    }

    @MainActor
    func testHistoryQueuesUntilAcknowledged() {
        let h = History(inMemory: true)
        let r = SessionResult(id: UUID(), date: Date(), exerciseID: "x", exerciseVersion: 1, exerciseName: "X", mode: "cycles",
                              ladderStep: 0, guided: false, startBPM: 90, topBPM: 90, seconds: 30, cycles: 4, notes: 10, hits: 10,
                              missed: 0, extra: 0, pct20: 100, pct40: 100, tightMs: 20, closeMs: 40, meanErrorMs: 0, spreadMs: 0,
                              toleranceMs: 30, targetPercent: 85, accuracyPercent: 100, sustainedSeconds: nil, score: 100,
                              passed: true, accentsPercent: nil, offsetMs: nil, appVersion: "0")
        h.add(r)
        XCTAssertEqual(h.pending().map(\.id), [r.id])
        h.markUploaded([r.id])
        XCTAssertTrue(h.pending().isEmpty)
        XCTAssertEqual(h.results.count, 1)
    }
}
