import XCTest
@testable import Practice

/// The shared scoring vectors (shared/scoring-vectors.json, made by scripts/make-scoring-vectors.mjs). The desktop
/// app passes the same file (desktop/tests), so a run scores the same on the phone and on the computer. When a
/// scoring rule changes, it changes in Scoring.swift, desktop/src/core/Scoring.cpp and shared/scoring.mjs together,
/// and the vectors are made again.
final class ScoringVectorTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func vectors() throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("shared/scoring-vectors.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func num(_ x: Any?) -> Double { (x as? NSNumber)?.doubleValue ?? 0 }
    private func int(_ x: Any?) -> Int? { (x is NSNull || x == nil) ? nil : (x as? NSNumber)?.intValue }
    private func list(_ x: Any?) -> [Any] { x as? [Any] ?? [] }

    private func config(_ v: [String: Any]) throws -> ScoringConfig {
        let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(v["config"]))
        return try JSONDecoder().decode(ScoringConfig.self, from: data)
    }

    func testRunsScoreAsTheVectorsSay() throws {
        let v = try vectors()
        let cfg = try config(v)
        let tol = num(v["tolerance"])
        let cases = list(v["score"])
        XCTAssertGreaterThan(cases.count, 5)
        for case let c as [String: Any] in cases {
            let name = c["name"] as? String ?? "?"
            let notes: [Exercise.Note] = list(c["notes"]).map { n in
                let a = list(n)
                return Exercise.Note(time: num(a[0]), accent: num(a[1]) != 0, beat: int(a[2]) ?? 0)
            }
            let played: [Onset] = list(c["played"]).map { p in
                let a = list(p)
                return Onset(time: num(a[0]), strength: Float(num(a[1])))
            }
            let rule = c["rule"] as? [String: Any] ?? [:]
            let r = Scoring.score(notes: notes, played: played, window: num(c["window"]),
                                  rule: ScoringRule(passMark: int(rule["passMark"]) ?? 85, tightMs: num(rule["tightMs"]),
                                                    closeMs: num(rule["closeMs"])),
                                  config: cfg)
            let e = c["expect"] as? [String: Any] ?? [:]
            XCTAssertEqual(r.score, int(e["score"]), name)
            XCTAssertEqual(r.expected, int(e["expected"]), name)
            XCTAssertEqual(r.hits, int(e["hits"]), name)
            XCTAssertEqual(r.missed, int(e["missed"]), name)
            XCTAssertEqual(r.extra, int(e["extra"]), name)
            XCTAssertEqual(r.within20, int(e["within20"]), name)
            XCTAssertEqual(r.within40, int(e["within40"]), name)
            XCTAssertEqual(r.full, int(e["full"]), name)
            XCTAssertEqual(r.pct20, int(e["pct20"]), name)
            XCTAssertEqual(r.pct40, int(e["pct40"]), name)
            XCTAssertEqual(r.passed, e["passed"] as? Bool, name)
            XCTAssertEqual(r.accentsLanded, int(e["accentsLanded"]), name)
            XCTAssertEqual(r.accentBeats, int(e["accentBeats"]), name)
            XCTAssertEqual(r.meanError, num(e["meanError"]), accuracy: tol, name)
            XCTAssertEqual(r.spread, num(e["spread"]), accuracy: tol, name)
            XCTAssertEqual(r.fullMs, num(e["fullMs"]), accuracy: tol, name)
            XCTAssertEqual(r.zeroMs, num(e["zeroMs"]), accuracy: tol, name)
            XCTAssertEqual(Scoring.band(spreadMs: r.spread), e["band"] as? String, name)
            let errors = list(e["errors"])
            XCTAssertEqual(r.errors.count, errors.count, name)
            for (k, x) in errors.enumerated() where k < r.errors.count {
                if x is NSNull { XCTAssertNil(r.errors[k], name) } else { XCTAssertEqual(r.errors[k] ?? .nan, num(x), accuracy: tol, name) }
            }
            let extras = list(e["extraOffsets"])
            XCTAssertEqual(r.extraOffsets.count, extras.count, name)
            for (k, x) in extras.enumerated() where k < r.extraOffsets.count {
                XCTAssertEqual(r.extraOffsets[k], num(x), accuracy: tol, name)
            }
        }
    }

    func testDoublesAccuracyCreditAndCalibration() throws {
        let v = try vectors()
        let cfg = try config(v)
        let tol = num(v["tolerance"])
        for case let c as [String: Any] in list(v["doubles"]) {
            let picks = list(c["picks"]).map { p -> Onset in let a = list(p); return Onset(time: num(a[0]), strength: Float(num(a[1]))) }
            let kept = Scoring.dropDoubles(picks, within: num(c["within"]), weakerThan: Float(num(c["ratio"])))
            let want = list(c["expect"]).map { list($0) }
            XCTAssertEqual(kept.count, want.count, c["name"] as? String ?? "")
            for (k, w) in want.enumerated() where k < kept.count {
                XCTAssertEqual(kept[k].time, num(w[0]), accuracy: tol)
                XCTAssertEqual(Double(kept[k].strength), num(w[1]), accuracy: tol)
            }
        }
        for case let c as [String: Any] in list(v["accuracy"]) {
            let errors: [Double?] = list(c["errors"]).map { $0 is NSNull ? nil : num($0) }
            let gaps: [Double] = list(c["gaps"]).map { num($0) }
            let a = Scoring.accuracy(errors: errors[0..<errors.count], gaps: gaps[0..<gaps.count], extras: int(c["extras"]) ?? 0, config: cfg)
            XCTAssertEqual(a, num(c["expect"]), accuracy: tol)
        }
        for case let c as [String: Any] in list(v["credit"]) {
            let w = cfg.windows(gap: num(c["gap"]))
            XCTAssertEqual(w.full, num(c["fullMs"]), accuracy: tol)
            XCTAssertEqual(w.zero, num(c["zeroMs"]), accuracy: tol)
            XCTAssertEqual(cfg.credit(errorMs: num(c["errorMs"]), gap: num(c["gap"])), num(c["expect"]), accuracy: tol)
        }
        for case let c as [String: Any] in list(v["calibration"]) {
            let found = Scoring.calibration(clicks: list(c["clicks"]).map { num($0) }, played: list(c["played"]).map { num($0) })
            if let want = c["expect"] as? [String: Any] {
                let f = try XCTUnwrap(found)
                XCTAssertEqual(f.offset, num(want["offset"]), accuracy: tol)
                XCTAssertEqual(f.spread, num(want["spread"]), accuracy: tol)
                XCTAssertEqual(f.hits, int(want["hits"]))
            } else {
                XCTAssertNil(found)
            }
        }
    }

    func testTheGridOfEveryDrill() throws {
        let v = try vectors()
        let tol = num(v["tolerance"])
        let data = try Data(contentsOf: root.appendingPathComponent("catalog/exercises/right-hand.json"))
        // Every drill's grid, the archived ones too (they come back one day).
        let drills = try Library.decodeExercises(data, includeArchived: true)
        for case let c as [String: Any] in list(v["grid"]) {
            let id = c["drill"] as? String ?? ""
            let ex = try XCTUnwrap(drills.first(where: { $0.id == id }), id)
            let bpm = num(c["bpm"])
            XCTAssertEqual(ex.shortestGap(bpm: bpm), num(c["shortestGap"]), accuracy: tol, id)
            XCTAssertEqual(ex.window(bpm: bpm), num(c["window"]), accuracy: tol, id)
            let notes = ex.notes(bpm: bpm, start: num(c["start"]), seconds: num(c["seconds"]))
            let times = list(c["times"]).map { num($0) }
            XCTAssertEqual(notes.count, times.count, id)
            for (k, t) in times.enumerated() where k < notes.count {
                XCTAssertEqual(notes[k].time, t, accuracy: tol, id)
                XCTAssertEqual(notes[k].accent, num(list(c["accents"])[k]) != 0, id)
                XCTAssertEqual(notes[k].beat, int(list(c["beats"])[k]), id)
            }
        }
    }
}
