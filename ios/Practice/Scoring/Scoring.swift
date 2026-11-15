import Foundation

/// How a run went: each expected note matched to at most one played note, nearest first.
struct ScoreResult: Equatable {
    var expected: Int
    var hits: Int
    var within20: Int
    var within40: Int
    var missed: Int
    var extra: Int
    /// Signed error of each matched note in ms (positive is late), in note order; nil where the note was missed.
    var errors: [Double?]
    var meanError: Double     // average of the matched errors (positive: behind the click)
    var spread: Double        // standard deviation, ms
    var accentsLanded: Int?   // beats whose accented note stood out, when the exercise has accents
    var accentBeats: Int?
    var score: Int
    var passMark: Int = Scoring.passMark

    var pct20: Int { expected > 0 ? Int((100 * Double(within20) / Double(expected)).rounded()) : 0 }
    var pct40: Int { expected > 0 ? Int((100 * Double(within40) / Double(expected)).rounded()) : 0 }
    var passed: Bool { score >= passMark }
}

enum Scoring {
    static let passMark = 85

    /// The matching window around a note: 100 ms, or less when notes are close together.
    static func window(shortestGap: Double) -> Double { min(0.100, max(0.030, shortestGap * 0.45)) }

    /// Pairs each expected time with the nearest played time within `window` seconds, closest pairs first.
    /// Returns, for each expected note, the index of its played note.
    static func match(expected: [Double], played: [Double], window: Double) -> [Int?] {
        var pairs: [(d: Double, e: Int, p: Int)] = []
        var j0 = 0
        for (i, t) in expected.enumerated() {
            while j0 < played.count && played[j0] < t - window { j0 += 1 }
            var j = j0
            while j < played.count && played[j] <= t + window {
                pairs.append((abs(played[j] - t), i, j)); j += 1
            }
        }
        pairs.sort { $0.d != $1.d ? $0.d < $1.d : $0.e < $1.e }
        var out = [Int?](repeating: nil, count: expected.count)
        var used = Set<Int>()
        for p in pairs where out[p.e] == nil && !used.contains(p.p) {
            out[p.e] = p.p; used.insert(p.p)
        }
        return out
    }

    /// Scores a run. `played` are onset times already moved by the calibration, on the same clock as the notes.
    /// Played notes outside [first note - window, last note + window] are not counted as extra.
    static func score(notes: [Exercise.Note], played: [Onset], window: Double, rule: ScoringRule = .standard) -> ScoreResult {
        let exp = notes.map(\.time)
        let times = played.map(\.time)
        let m = match(expected: exp, played: times, window: window)
        var errors: [Double?] = []
        var hits = 0, w20 = 0, w40 = 0
        var credit = 0.0
        var matched: [Double] = []
        for (i, j) in m.enumerated() {
            guard let j else { errors.append(nil); continue }
            let ms = (times[j] - exp[i]) * 1000
            errors.append(ms)
            matched.append(ms)
            hits += 1
            let a = abs(ms)
            if a <= rule.tightMs { w20 += 1; credit += 1 } else if a <= rule.closeMs { credit += 0.7 } else { credit += 0.3 }
            if a <= rule.closeMs { w40 += 1 }
        }
        var extra = 0
        if let first = exp.first, let last = exp.last {
            let used = Set(m.compactMap { $0 })
            for (j, t) in times.enumerated() where !used.contains(j) && t >= first - window && t <= last + window { extra += 1 }
        }
        let mean = matched.isEmpty ? 0 : matched.reduce(0, +) / Double(matched.count)
        let spread = matched.count < 2 ? 0 : (matched.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(matched.count - 1)).squareRoot()

        // Accents: on each beat with an accented note that was played, did it come out louder than the beat's others?
        var landed: Int?, beats: Int?
        if notes.contains(where: \.accent) {
            var l = 0, b = 0
            var byBeat: [Int: [(Bool, Float)]] = [:]
            for (i, j) in m.enumerated() { if let j { byBeat[notes[i].beat, default: []].append((notes[i].accent, played[j].strength)) } }
            for (_, list) in byBeat {
                guard let acc = list.first(where: { $0.0 })?.1 else { continue }
                let others = list.filter { !$0.0 }.map(\.1)
                guard !others.isEmpty else { continue }
                b += 1
                if acc > 1.4 * (others.reduce(0, +) / Float(others.count)) { l += 1 }
            }
            landed = l; beats = b
        }

        let n = Double(max(1, exp.count))
        let s = exp.isEmpty ? 0 : Int((100 * credit / (n + 0.5 * Double(extra))).rounded())
        return ScoreResult(expected: exp.count, hits: hits, within20: w20, within40: w40, missed: exp.count - hits,
                           extra: extra, errors: errors, meanError: mean, spread: spread,
                           accentsLanded: landed, accentBeats: beats, score: min(100, max(0, s)), passMark: rule.passMark)
    }

    /// Calibration: he plays along to clicks; the offset is the median of (played - click) over the clicks he hit
    /// within 250 ms. Nil when fewer than five clicks were hit.
    static func calibrate(clicks: [Double], played: [Double]) -> Double? {
        let m = match(expected: clicks, played: played, window: 0.25)
        let d = m.enumerated().compactMap { i, j in j.map { played[$0] - clicks[i] } }.sorted()
        guard d.count >= 5 else { return nil }
        return d.count % 2 == 1 ? d[d.count / 2] : (d[d.count / 2 - 1] + d[d.count / 2]) / 2
    }
}
