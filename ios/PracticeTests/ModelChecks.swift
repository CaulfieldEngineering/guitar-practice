import Foundation
#if os(iOS)
@testable import Practice
#endif

/// Checks of the model that need no device: ascending tempo, the Challenge clock, the routine runner's clock, the
/// drill catalog filter, X notes and pitch, the click options, the pitch detector and routines. The same file runs
/// in the iPhone unit tests (ModelCheckTests) and on Windows with the Swift toolchain (scripts/model-check.sh,
/// ios/ModelCheck), so the logic is tested on the mini PC too, where there is no Mac.
/// The vectors are the shared ones (shared/*.json, made by scripts/make-*-vectors.mjs from shared/*.mjs).
struct ModelChecks {
    private(set) var failures: [String] = []
    private(set) var count = 0

    mutating func expect(_ ok: Bool, _ what: @autoclosure () -> String) {
        count += 1
        if !ok { failures.append(what()) }
    }
    mutating func near(_ a: Double?, _ b: Double?, _ what: @autoclosure () -> String, tol: Double = 1e-6) {
        let ok: Bool
        switch (a, b) {
        case (nil, nil): ok = true
        case let (x?, y?): ok = abs(x - y) <= tol
        default: ok = false
        }
        expect(ok, "\(what()): \(a.map { "\($0)" } ?? "nil") vs \(b.map { "\($0)" } ?? "nil")")
    }

    static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    static func json(_ rel: String) -> [String: Any] {
        let d = (try? Data(contentsOf: root.appendingPathComponent(rel))) ?? Data()
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
    }
    static func num(_ x: Any?) -> Double { (x as? NSNumber)?.doubleValue ?? 0 }
    static func int(_ x: Any?) -> Int? { (x is NSNull || x == nil) ? nil : (x as? NSNumber)?.intValue }
    static func list(_ x: Any?) -> [Any] { x as? [Any] ?? [] }
    static func dict(_ x: Any?) -> [String: Any] { x as? [String: Any] ?? [:] }
    static func decode<T: Decodable>(_ t: T.Type, _ x: Any?) -> T? {
        guard let x, let d = try? JSONSerialization.data(withJSONObject: x) else { return nil }
        return try? JSONDecoder().decode(t, from: d)
    }

    /// Every check, by name.
    static let all: [(String, (inout ModelChecks) -> Void)] = [
        ("tempo per loop", { $0.perLoop() }),
        ("tempo by accuracy", { $0.governor() }),
        ("tempo zones and bounds", { $0.zonesAndBounds() }),
        ("challenge clock", { $0.challenge() }),
        ("routine clock", { $0.routineClock() }),
        ("drill catalog filter", { $0.catalogFilter() }),
        ("X notes and pitch", { $0.pitch() }),
        ("click options", { $0.clickOptions() }),
        ("pitch detector", { $0.pitchDetector() }),
        ("routines", { $0.routines() }),
    ]

    // MARK: Ascending tempo

    mutating func perLoop() {
        let v = Self.json("shared/tempo-vectors.json")
        let cases = Self.list(v["perLoop"])
        expect(cases.count >= 5, "per-loop vectors read")
        for case let c as [String: Any] in cases {
            guard let plan = Self.decode(TempoPlan.self, c["plan"]) else { expect(false, "plan decodes"); continue }
            let start = Self.int(c["start"]) ?? 0, top = Self.int(c["top"]) ?? 0
            let got = Self.list(c["loops"]).map { l -> Int in
                let a = Self.list(l)
                return plan.perLoopBPM(start: start, top: top, loop: Self.int(a[0]) ?? 0, elapsed: Self.num(a[1]))
            }
            let want = Self.list(c["expect"]).map { Self.int($0) ?? -1 }
            expect(got == want, "\(c["name"] ?? ""): \(got) vs \(want)")
        }
    }

    mutating func governor() {
        let v = Self.json("shared/tempo-vectors.json")
        let cases = Self.list(v["governor"])
        expect(cases.count >= 10, "governor vectors read")
        for case let c as [String: Any] in cases {
            let name = c["name"] as? String ?? "?"
            guard let plan = Self.decode(TempoPlan.self, c["plan"]) else { expect(false, "plan decodes"); continue }
            var g = TempoGovernor(plan: plan, start: Self.int(c["start"]) ?? 0, top: Self.int(c["top"]) ?? 0, floor: Self.int(c["floor"]) ?? 0)
            let expects = Self.list(c["expect"])
            for (i, l) in Self.list(c["loops"]).enumerated() {
                let a = Self.list(l)
                let change = g.judge(accuracy: Self.num(a[0]), seconds: Self.num(a[1]), bpm: Self.int(a[2]) ?? 0)
                let e = Self.dict(expects[i])
                if let want = e["change"] as? [String: Any] {
                    expect(change?.kind.rawValue == want["kind"] as? String && change?.from == Self.int(want["from"]) && change?.to == Self.int(want["to"]),
                           "\(name) loop \(i): \(String(describing: change)) vs \(want)")
                } else {
                    expect(change == nil, "\(name) loop \(i): \(String(describing: change)) vs no change")
                }
                expect(g.target == Self.int(e["target"]), "\(name) loop \(i) target \(g.target)")
                near(g.progress(), Self.num(e["progress"]), "\(name) loop \(i) progress")
                expect(plan.normalized.zone(Self.num(a[0])).rawValue == e["zone"] as? String, "\(name) loop \(i) zone")
            }
        }
    }

    mutating func zonesAndBounds() {
        let v = Self.json("shared/tempo-vectors.json")
        for case let c as [String: Any] in Self.list(v["zones"]) {
            guard let plan = Self.decode(TempoPlan.self, c["plan"]) else { expect(false, "zone plan decodes"); continue }
            expect(plan.zone(Self.num(c["accuracy"])).rawValue == c["expect"] as? String, "zone at \(Self.num(c["accuracy"]))")
        }
        for case let c as [String: Any] in Self.list(v["bounds"]) {
            guard let plan = Self.decode(TempoPlan.self, c["plan"]) else { expect(false, "bounds plan decodes"); continue }
            let r = Self.dict(c["rule"]), e = Self.dict(c["expect"])
            let b = plan.bounds(start: Self.int(c["start"]) ?? 0, rule: TempoRule(start: 0, min: Self.int(r["min"]) ?? 0, max: Self.int(r["max"]) ?? 0))
            expect(b.top == Self.int(e["top"]) && b.floor == Self.int(e["floor"]), "bounds \(b) vs \(e)")
        }
        // The hysteresis: thresholds too close are pulled apart.
        var p = TempoPlan(); p.upPercent = 80; p.downPercent = 82; p.breakOn = true; p.breakPercent = 90
        let n = p.normalized
        expect(n.downPercent <= n.upPercent - 5 && n.breakPercent <= n.downPercent - 5, "hysteresis kept")
    }

    mutating func challenge() {
        let v = Self.json("shared/tempo-vectors.json")
        let cases = Self.list(v["challenge"])
        expect(cases.count >= 4, "challenge vectors read")
        for case let c as [String: Any] in cases {
            let o = Self.dict(c["opts"])
            var k = ChallengeClock(targetSeconds: Self.num(o["targetSeconds"]), percent: Self.int(o["percent"]) ?? 90,
                                   window: Self.int(o["window"]) ?? 2, capSeconds: Self.num(o["capSeconds"]))
            let expects = Self.list(c["expect"])
            for (i, l) in Self.list(c["loops"]).enumerated() {
                let a = Self.list(l)
                let r = k.judge(accuracy: Self.num(a[0]), seconds: Self.num(a[1]))
                let e = Self.dict(expects[i])
                let name = "\(c["name"] ?? "") loop \(i)"
                expect(r.rawValue == e["result"] as? String, "\(name) result \(r)")
                near(k.earned, Self.num(e["earned"]), "\(name) earned")
                near(k.elapsed, Self.num(e["elapsed"]), "\(name) elapsed")
                near(k.bestStreak, Self.num(e["bestStreak"]), "\(name) best streak")
                near((k.share * 1e6).rounded() / 1e6, Self.num(e["share"]), "\(name) share")
                expect(k.inZone == (e["inZone"] as? Bool ?? false), "\(name) in zone")
            }
        }
        // Under the threshold the clock holds; it never passes the target.
        var k = ChallengeClock(targetSeconds: 10, percent: 90, window: 1)
        expect(k.judge(accuracy: 0.89, seconds: 4) == .held && k.earned == 0, "held under the threshold")
        k.judge(accuracy: 0.95, seconds: 4); k.judge(accuracy: 0.95, seconds: 4)
        expect(k.judge(accuracy: 0.95, seconds: 4) == .done && k.earned == 10, "done exactly at the target")
    }

    // MARK: Routine runner

    mutating func routineClock() {
        let v = Self.json("shared/routine-vectors.json")
        let cases = Self.list(v["cases"])
        expect(cases.count >= 8, "routine vectors read")
        for case let c as [String: Any] in cases {
            let name = c["name"] as? String ?? "?"
            let blocks: [Double?] = Self.list(c["blocks"]).map { b in
                let d = Self.dict(b)
                return d["seconds"] is NSNull || d["seconds"] == nil ? nil : Self.num(d["seconds"])
            }
            let estimates = Self.list(c["estimates"]).map(Self.num)
            var k = RoutineClock(blocks: blocks)
            let expects = Self.list(c["expect"])
            for (i, s) in Self.list(c["steps"]).enumerated() {
                let a = Self.list(s)
                let t = Self.num(a[0]), action = a[1] as? String ?? ""
                var events: [RoutineClock.Event] = []
                switch action {
                case "start": events = k.start(t)
                case "tick": events = k.tick(t)
                case "pause": k.pause(t)
                case "resume": events = k.resume(t)
                case "skip": events = k.skip(t)
                case "back": k.back(t)
                case "blockDone": events = k.blockDone(t)
                default: break
                }
                let e = Self.dict(expects[i])
                let want: [RoutineClock.Event] = Self.list(e["events"]).map { x in
                    let p = Self.list(x)
                    switch p.first as? String {
                    case "start": return .start(Self.int(p[1]) ?? 0)
                    case "end": return .end(Self.int(p[1]) ?? 0)
                    default: return .done
                    }
                }
                expect(events == want, "\(name) step \(i) events \(events) vs \(want)")
                let st = k.state(t), ws = Self.dict(e["state"])
                expect(st.phase.rawValue == ws["phase"] as? String, "\(name) step \(i) phase \(st.phase)")
                expect(st.index == Self.int(ws["index"]), "\(name) step \(i) index")
                near(st.left, ws["left"] is NSNull ? nil : Self.num(ws["left"]), "\(name) step \(i) left")
                expect(st.paused == (ws["paused"] as? Bool ?? false), "\(name) step \(i) paused")
                expect(st.countdownTick == Self.int(ws["countdownTick"]), "\(name) step \(i) tick")
                near(k.remaining(t, estimates: estimates), Self.num(e["remaining"]), "\(name) step \(i) remaining")
            }
            for (i, l) in Self.list(c["log"]).enumerated() {
                let d = Self.dict(l)
                near(k.log[i].seconds, Self.num(d["seconds"]), "\(name) log \(i) seconds")
                expect(k.log[i].skipped == (d["skipped"] as? Bool ?? false) && k.log[i].done == (d["done"] as? Bool ?? false), "\(name) log \(i)")
            }
        }
    }

    // MARK: Catalog

    mutating func catalogFilter() {
        let file = Self.root.appendingPathComponent("catalog/exercises/right-hand.json")
        let data = (try? Data(contentsOf: file)) ?? Data()
        let offered = (try? Library.decodeExercises(data)) ?? []
        expect(offered.map(\.id) == ["trip16x4"], "only the triplets drill is offered: \(offered.map(\.id))")
        let raw = Self.list(Self.dict(try? JSONSerialization.jsonObject(with: data))["exercises"])
        expect(raw.count == 9, "every drill is still defined in the file")
        expect(offered.first?.pitchFree == true, "the triplets drill is all X notes")
        expect(Library.active([Exercise.fallback]).count == 1, "the fallback is offered")

        // A newer app catalog than the one pulled before it: the old pull is not read (it would bring drills back).
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("practice-check-\(UUID().uuidString)")
        let bundled = tmp.appendingPathComponent("bundled"), cache = tmp.appendingPathComponent("cache")
        func write(_ folder: URL, version: Int) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? Data("{\"schema\":1,\"version\":\(version),\"files\":[]}".utf8).write(to: folder.appendingPathComponent("index.json"))
        }
        write(bundled, version: 7); write(cache, version: 6)
        expect(Library.folders(bundled: bundled, cache: cache) == [bundled], "an older pulled catalog is skipped")
        write(cache, version: 8)
        expect(Library.folders(bundled: bundled, cache: cache) == [bundled, cache], "a newer pulled catalog is read after the app's")
        try? FileManager.default.removeItem(at: cache)
        expect(Library.folders(bundled: bundled, cache: cache) == [bundled], "no pulled catalog")
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: X notes and pitch

    mutating func pitch() {
        let v = Self.json("shared/scoring-vectors.json")
        let cases = Self.list(v["pitch"])
        expect(cases.count >= 6, "pitch vectors read")
        let cfg = Self.decode(ScoringConfig.self, v["config"]) ?? .standard
        for case let c as [String: Any] in cases {
            let notes: [Exercise.Note] = Self.list(c["notes"]).map { n in
                let a = Self.list(n)
                var note = Exercise.Note(time: Self.num(a[0]), accent: Self.num(a[1]) != 0, beat: Self.int(a[2]) ?? 0)
                note.pitch = Self.int(a[3])
                return note
            }
            let played: [Onset] = Self.list(c["played"]).map { p in
                let a = Self.list(p)
                return Onset(time: Self.num(a[0]), strength: Float(Self.num(a[1])), pitch: a[2] is NSNull ? nil : Self.num(a[2]))
            }
            let r = Scoring.score(notes: notes, played: played, window: 0.05, rule: .standard, config: cfg)
            let e = Self.dict(c["expect"])
            expect(r.score == Self.int(e["score"]) && r.hits == Self.int(e["hits"]) && r.wrongPitch == Self.int(e["wrongPitch"]),
                   "\(c["name"] ?? ""): \(r.score) \(r.hits) \(r.wrongPitch) vs \(e)")
        }

        // Decoding: "fret": "x", "x": true and no fret are X; a fret number on a string is pitched.
        let json = """
        {"id":"t","name":"T","tempo":{"start":80},"notes":[
          {"at":{"beat":0},"string":6,"fret":"x"},{"at":{"beat":1},"string":6,"fret":3,"x":true},
          {"at":{"beat":2}},{"at":{"beat":3},"string":6,"fret":3}]}
        """
        let ex = try? JSONDecoder().decode(Exercise.self, from: Data(json.utf8))
        expect(ex?.notes.map(\.x) == [true, true, true, false], "X notes decode: \(String(describing: ex?.notes.map(\.x)))")
        expect(ex?.hasPitchedNotes == true, "a drill with a fretted note listens for pitch")
        if let ex {
            let dropD = Tuning.preset("dropD")!
            let slot = RunBuilder.cycle(ex, index: 0, start: 0, bpm: 60, guided: false, options: .init(tuning: dropD))
            expect(slot.notes.map(\.pitch) == [nil, nil, nil, 41], "pitches in drop D: \(slot.notes.map(\.pitch))")
            let e = RunBuilder.cycle(ex, index: 0, start: 0, bpm: 60, guided: false, options: .init(tuning: .standard))
            expect(e.notes.last?.pitch == 43, "the same fret in E standard")
        }
        expect(Scoring.pitchMatches(expected: nil, heard: 52.3), "an X note takes any pitch")
        expect(Scoring.pitchMatches(expected: 43, heard: nil), "an unknown pitch is not held against him")
        expect(!Scoring.pitchMatches(expected: 43, heard: 44), "a semitone off is wrong")
        expect(Scoring.pitchMatches(expected: 43, heard: 55.2), "an octave off is right")
        expect(Tuning.preset("seven")?.strings.count == 7 && Tuning.preset("dropA")?.strings.last == 33, "7-string tunings")
        expect(Tuning.preset("dropD")?.lowToHigh == "D A D G B E", "string names low to high")
        expect(Tuning.preset("eb")?.lowToHigh == "Eb Ab Db Gb Bb Eb", "flats where the tuning is written with flats")
    }

    // MARK: Click options

    mutating func clickOptions() {
        let ex = Exercise.fallback            // 3,3,3,3,4,4,4,4, 4/4
        func accents(_ a: SessionSettings.Accent) -> [Int] {
            RunBuilder.cycle(ex, index: 0, start: 0, bpm: 60, guided: false, options: .init(accent: a)).events
                .filter { $0.kind == .accent }.map { Int($0.time.rounded()) }
        }
        expect(accents(.one) == [0, 4], "accent on beat 1 of each bar: \(accents(.one))")
        expect(accents(.groups) == [0, 4], "accent where the notes per beat change: \(accents(.groups))")
        expect(accents(.off).isEmpty, "no accent")
        // The gap trainer: every 2nd bar has no click (bar 2 is beats 4 to 7), the notes are all still there.
        let gap = RunBuilder.cycle(ex, index: 0, start: 0, bpm: 60, guided: true, options: .init(gapEvery: 2))
        let clicks = gap.events.filter { $0.kind == .accent || $0.kind == .beat }.map { Int($0.time.rounded()) }
        expect(clicks == [0, 1, 2, 3], "every 2nd bar is muted: \(clicks)")
        expect(!gap.events.contains { ($0.kind == .pluck || $0.kind == .pluckAccent) && $0.time >= 4 }, "the guide is muted too")
        expect(gap.notes.count == 28, "the notes are all scored")
        expect(RunBuilder.isGap(bar: 3, every: 4) && !RunBuilder.isGap(bar: 2, every: 4) && !RunBuilder.isGap(bar: 1, every: 0), "gap bars")
        // Settings from before 0.3.0 still read, with the new options at their defaults.
        let old = try? JSONDecoder().decode(SessionSettings.self, from: Data(#"{"kind":"endurance","targetPercent":85,"ladderStep":4}"#.utf8))
        expect(old?.ladderStep == 4 && old?.tempoPlan.mode == .off && old?.countInBars == 1 && old?.accent == .one, "0.2 settings read")
        let ch = try? JSONDecoder().decode(SessionSettings.self, from: Data(#"{"kind":"challenge","seconds":180,"capSeconds":600}"#.utf8))
        expect(ch?.kind == .challenge && ch?.endsItself == true && ch?.capSeconds == 600, "challenge settings read")
    }

    // MARK: Pitch detector

    mutating func pitchDetector() {
        let sr = 48000.0
        let det = PitchDetector(sampleRate: sr)
        func tone(_ hz: Double, harmonics: Bool = true) -> [Float] {
            (0..<det.needed + 64).map { i in
                let t = Double(i) / sr
                var s = sin(2 * .pi * hz * t)
                if harmonics { s += 0.5 * sin(4 * .pi * hz * t) + 0.25 * sin(6 * .pi * hz * t) }
                return Float(0.3 * s * exp(-t * 3))
            }
        }
        for (hz, midi) in [(82.41, 40.0), (55.0, 33.0), (110.0, 45.0), (196.0, 55.0), (329.63, 64.0)] {
            let m = det.midi(tone(hz))
            near(m, midi, "pitch of \(hz) Hz", tol: 0.3)
        }
        var seed: UInt32 = 7
        let noise: [Float] = (0..<det.needed).map { _ in
            seed = seed &* 1664525 &+ 1013904223
            return Float(Int32(bitPattern: seed)) / Float(Int32.max) * 0.2
        }
        expect(det.midi(noise) == nil, "noise has no pitch")
        expect(det.midi([Float](repeating: 0, count: det.needed)) == nil, "silence has no pitch")
    }

    // MARK: Routines

    mutating func routines() {
        let a = PracticeRoutine(id: "r1", name: "A", blocks: [RoutineBlock(kind: .warmup, seconds: 60)], updatedAt: Date(timeIntervalSince1970: 100))
        var b = a; b.name = "B"; b.updatedAt = Date(timeIntervalSince1970: 200)
        expect(PracticeRoutine.merge([a], [b]).first?.name == "B", "the newer edit wins")
        expect(PracticeRoutine.merge([b], [a]).first?.name == "B", "whichever side it is on")
        var gone = a; gone.deleted = true; gone.updatedAt = Date(timeIntervalSince1970: 300)
        expect(PracticeRoutine.merge([b], [gone]).first?.deleted == true, "a newer delete wins")
        let copy = b.duplicate()
        expect(copy.id != b.id && copy.blocks.first?.id != b.blocks.first?.id && copy.name == "B copy", "a duplicate is its own")
        // The starter routine in the catalog decodes, and its drill blocks point at the offered drill.
        let starter = Self.json("catalog/starter-routines.json")
        let list = Self.list(starter["routines"])
        let r = list.first.flatMap { x -> PracticeRoutine? in
            guard let d = try? JSONSerialization.data(withJSONObject: x) else { return nil }
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return try? dec.decode(PracticeRoutine.self, from: d)
        }
        expect(r?.blocks.count == 5, "the starter routine decodes")
        expect(r?.blocks.filter { $0.kind == .drill }.allSatisfy { $0.drillID == "trip16x4" } == true, "its drills are the offered one")
        expect(r?.blocks.contains { $0.drill?.session.kind == .challenge } == true, "it has a challenge block")
        expect(r?.blocks.contains { $0.drill?.session.tempoPlan.mode == .perLoop } == true, "and an ascending one")
        if let r {
            let est = r.estimate(drills: [Exercise.fallback])
            expect(est > 600 && est < 2400, "about a quarter hour or more: \(est)")
            let enc = try? JSONEncoder().encode(r)
            let back = enc.flatMap { try? JSONDecoder().decode(PracticeRoutine.self, from: $0) }
            expect(back?.blocks == r.blocks, "a routine round-trips")
        }
        expect(RoutineBlock(kind: .drill).fixedSeconds == nil && RoutineBlock(kind: .rest, seconds: 30).fixedSeconds == 30, "drill blocks end themselves")
    }
}
