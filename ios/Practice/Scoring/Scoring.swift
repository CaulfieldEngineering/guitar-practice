import Foundation

/// How timing error becomes credit (Joe, 2026-11-14: "The ms accuracy should be part of the algorithm determining
/// percentage accuracy, not a user feature"). Each note earns full credit inside a tight window and falls off smoothly
/// to nothing by a wider one. Both windows are a share of the gap to the nearest neighbouring note, so sixteenths at
/// 160 are not judged like eighths at 80, and both are kept between a floor and a ceiling in milliseconds. A missed
/// note earns nothing, and each extra note counts as one more note that earned nothing.
/// The numbers live in the catalog (catalog/scoring.json, served by the drill server), so they can be tuned without
/// an app update; `standard` is the copy used until a catalog has been read.
struct ScoringConfig: Codable, Equatable {
    var schema: Int = 1
    /// Full credit within this share of the gap between notes.
    var fullFraction: Double = 0.12
    /// No credit from this share of the gap.
    var zeroFraction: Double = 0.45
    var fullMinMs: Double = 12
    var fullMaxMs: Double = 25
    var zeroMinMs: Double = 35
    var zeroMaxMs: Double = 90
    /// How much of a note each extra note adds to the count the credit is divided by.
    var extraWeight: Double = 1

    static let standard = ScoringConfig()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schema, fullFraction, zeroFraction, fullMinMs, fullMaxMs, zeroMinMs, zeroMaxMs, extraWeight
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let s = ScoringConfig()
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        fullFraction = try c.decodeIfPresent(Double.self, forKey: .fullFraction) ?? s.fullFraction
        zeroFraction = try c.decodeIfPresent(Double.self, forKey: .zeroFraction) ?? s.zeroFraction
        fullMinMs = try c.decodeIfPresent(Double.self, forKey: .fullMinMs) ?? s.fullMinMs
        fullMaxMs = try c.decodeIfPresent(Double.self, forKey: .fullMaxMs) ?? s.fullMaxMs
        zeroMinMs = try c.decodeIfPresent(Double.self, forKey: .zeroMinMs) ?? s.zeroMinMs
        zeroMaxMs = try c.decodeIfPresent(Double.self, forKey: .zeroMaxMs) ?? s.zeroMaxMs
        extraWeight = try c.decodeIfPresent(Double.self, forKey: .extraWeight) ?? s.extraWeight
    }

    /// Whether the numbers make sense (a catalog file that does not is refused whole).
    var isValid: Bool {
        fullFraction > 0 && zeroFraction > fullFraction && fullMinMs > 0 && fullMaxMs >= fullMinMs
            && zeroMinMs > 0 && zeroMaxMs >= zeroMinMs && extraWeight >= 0
    }

    /// The two windows in milliseconds for a note whose nearest neighbour is `gap` seconds away.
    func windows(gap: Double) -> (full: Double, zero: Double) {
        let ms = max(0, gap) * 1000
        let full = min(fullMaxMs, max(fullMinMs, fullFraction * ms))
        let zero = min(zeroMaxMs, max(zeroMinMs, zeroFraction * ms))
        return (full, max(zero, full + 1))
    }

    /// Credit for one played note, 0 to 1: all of it inside the full window, a smooth fall to none at the zero window.
    func credit(errorMs: Double, gap: Double) -> Double {
        let w = windows(gap: gap)
        let a = abs(errorMs)
        if a <= w.full { return 1 }
        if a >= w.zero { return 0 }
        let x = (a - w.full) / (w.zero - w.full)
        return 0.5 * (1 + cos(Double.pi * x))
    }
}

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
    /// The accuracy, 0 to 100: the notes' credit over the notes asked for plus the extra ones.
    var score: Int
    var passMark: Int = Scoring.passMark
    /// Notes that earned full credit.
    var full: Int = 0
    /// The windows the notes were judged with, averaged over the run (ms).
    var fullMs: Double = 0
    var zeroMs: Double = 0
    /// Each extra note's distance from its nearest note of the drill, ms (positive: after it), so a run shows what
    /// the extras were (0.2.2).
    var extraOffsets: [Double] = []

    var pct20: Int { expected > 0 ? Int((100 * Double(within20) / Double(expected)).rounded()) : 0 }
    var pct40: Int { expected > 0 ? Int((100 * Double(within40) / Double(expected)).rounded()) : 0 }
    var pctFull: Int { expected > 0 ? Int((100 * Double(full) / Double(expected)).rounded()) : 0 }
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

    /// For each note, the gap in seconds to its nearest neighbour (a lone note gets one second).
    static func gaps(_ times: [Double]) -> [Double] {
        var out = [Double](repeating: 1, count: times.count)
        guard times.count > 1 else { return out }
        for i in times.indices {
            var g = Double.greatestFiniteMagnitude
            if i > 0 { g = min(g, times[i] - times[i - 1]) }
            if i + 1 < times.count { g = min(g, times[i + 1] - times[i]) }
            out[i] = max(0.001, g)
        }
        return out
    }

    /// The accuracy of some notes, 0 to 1: each note's credit (none for a missed one), over the notes plus the extras.
    /// `errors` and `gaps` line up, note by note.
    static func accuracy(errors: ArraySlice<Double?>, gaps: ArraySlice<Double>, extras: Int = 0,
                         config: ScoringConfig = .standard) -> Double {
        guard !errors.isEmpty else { return 1 }
        var credit = 0.0
        for (e, g) in zip(errors, gaps) {
            if let e { credit += config.credit(errorMs: e, gap: g) }
        }
        let count = Double(errors.count) + config.extraWeight * Double(max(0, extras))
        return count > 0 ? min(1, credit / count) : 1
    }

    /// Scores a run. `played` are onset times already moved by the calibration, on the same clock as the notes.
    /// Played notes outside [first note - window, last note + window] are not counted as extra.
    static func score(notes: [Exercise.Note], played: [Onset], window: Double, rule: ScoringRule = .standard,
                      config: ScoringConfig = .standard) -> ScoreResult {
        let exp = notes.map(\.time)
        let times = played.map(\.time)
        let m = match(expected: exp, played: times, window: window)
        let gap = gaps(exp)
        var errors: [Double?] = []
        var hits = 0, w20 = 0, w40 = 0, full = 0
        var credit = 0.0
        var fullSum = 0.0, zeroSum = 0.0
        var matched: [Double] = []
        for (i, j) in m.enumerated() {
            let w = config.windows(gap: gap[i])
            fullSum += w.full
            zeroSum += w.zero
            guard let j else { errors.append(nil); continue }
            let ms = (times[j] - exp[i]) * 1000
            errors.append(ms)
            matched.append(ms)
            hits += 1
            let a = abs(ms)
            let c = config.credit(errorMs: ms, gap: gap[i])
            credit += c
            if c >= 0.999 { full += 1 }
            if a <= rule.tightMs { w20 += 1 }
            if a <= rule.closeMs { w40 += 1 }
        }
        var extra = 0
        var extraOffsets: [Double] = []
        if let first = exp.first, let last = exp.last {
            let used = Set(m.compactMap { $0 })
            for (j, t) in times.enumerated() where !used.contains(j) && t >= first - window && t <= last + window {
                extra += 1
                var near = exp[0]
                for e in exp where abs(e - t) < abs(near - t) { near = e }
                extraOffsets.append((t - near) * 1000)
            }
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

        let n = Double(exp.count)
        let count = n + config.extraWeight * Double(extra)
        let s = exp.isEmpty || count <= 0 ? 0 : Int((100 * credit / count).rounded())
        return ScoreResult(expected: exp.count, hits: hits, within20: w20, within40: w40, missed: exp.count - hits,
                           extra: extra, errors: errors, meanError: mean, spread: spread,
                           accentsLanded: landed, accentBeats: beats, score: min(100, max(0, s)), passMark: rule.passMark,
                           full: full, fullMs: exp.isEmpty ? 0 : fullSum / n, zeroMs: exp.isEmpty ? 0 : zeroSum / n,
                           extraOffsets: extraOffsets)
    }

    /// Adds a pick heard to the run's list, unless it is the same pick heard twice (0.2.2). Two onsets closer than
    /// `within` seconds, one with under `weakerThan` of the other's energy, are one pick: the stronger one is kept.
    /// Two picks of like strength are two notes, so a real extra note is still an extra.
    /// Returns false when the pick was folded into the one before it.
    @discardableResult
    static func addPick(_ o: Onset, to played: inout [Onset], within: Double, weakerThan ratio: Float = 0.5) -> Bool {
        guard let last = played.last, o.time - last.time < within, o.time >= last.time else {
            played.append(o); return true
        }
        if o.strength < last.strength * ratio { return false }
        if last.strength < o.strength * ratio { played[played.count - 1] = o; return false }
        played.append(o); return true
    }

    /// The same over a whole list in time order.
    static func dropDoubles(_ list: [Onset], within: Double, weakerThan ratio: Float = 0.5) -> [Onset] {
        var out: [Onset] = []
        for o in list { addPick(o, to: &out, within: within, weakerThan: ratio) }
        return out
    }

    /// What a run's timing means in plain words, from its spread (the standard deviation of the picks around his own
    /// average, ms). The anchors are the timing research's: session players hold about 10 to 15 ms, a good amateur
    /// 20 to 30, a beginner 40 to 60.
    static func band(spreadMs: Double) -> String {
        switch spreadMs {
        case ..<15: return L.bandLocked
        case ..<25: return L.bandTight
        case ..<40: return L.bandGood
        case ..<60: return L.bandLoose
        default: return L.bandRough
        }
    }

    /// Calibration: he plays along to clicks; the offset is the median of (played - click) over the clicks he hit
    /// within 250 ms. Nil when fewer than five clicks were hit.
    static func calibrate(clicks: [Double], played: [Double]) -> Double? {
        calibration(clicks: clicks, played: played)?.offset
    }

    /// The same, with how steady the notes were: their standard deviation in seconds, and how many were heard.
    static func calibration(clicks: [Double], played: [Double]) -> (offset: Double, spread: Double, hits: Int)? {
        let m = match(expected: clicks, played: played, window: 0.25)
        let d = m.enumerated().compactMap { i, j in j.map { played[$0] - clicks[i] } }.sorted()
        guard d.count >= 5 else { return nil }
        let median = d.count % 2 == 1 ? d[d.count / 2] : (d[d.count / 2 - 1] + d[d.count / 2]) / 2
        let mean = d.reduce(0, +) / Double(d.count)
        let spread = (d.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(d.count - 1)).squareRoot()
        return (median, spread, d.count)
    }
}
