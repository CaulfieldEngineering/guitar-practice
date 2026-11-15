import Foundation

/// One step of a routine: clicking at a tempo, resting, or a timed block with no click ("Motion", for the
/// Perfect Picking warm-ups that are done without a metronome).
struct Interval: Codable, Identifiable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable { case play, rest, motion }
    var id = UUID()
    var kind: Kind
    var seconds: Int
    var bpm: Int
    /// Optional name shown big while it runs ("Wrist Holds", "Breaking point").
    var label: String = ""

    init(_ kind: Kind, _ seconds: Int, bpm: Int = 100, label: String = "") {
        self.kind = kind; self.seconds = seconds; self.bpm = bpm; self.label = label
    }

    private enum CodingKeys: String, CodingKey { case id, kind, seconds, bpm, label }

    /// Data files may leave out the id (made fresh), the tempo (100) and the label.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(Kind.self, forKey: .kind)
        seconds = try c.decode(Int.self, forKey: .seconds)
        bpm = try c.decodeIfPresent(Int.self, forKey: .bpm) ?? 100
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }

    var title: String {
        if !label.isEmpty { return label }
        switch kind { case .play: return "Play"; case .rest: return "Rest"; case .motion: return "No click" }
    }
}

/// A HIIT-style practice routine: the intervals, repeated `rounds` times, every play interval `stepBPM` faster
/// each round.
struct Routine: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var intervals: [Interval]
    var rounds: Int = 1
    var stepBPM: Int = 0
    var beatsPerBar: Int = 4
    var subdivision: Int = 1
    var countInBeats: Int = 4
    var notes: String = ""
    /// What the voice says before it starts.
    var intro: String = ""

    static let bpmRange = 20...400

    init(id: UUID = UUID(), name: String, intervals: [Interval], rounds: Int = 1, stepBPM: Int = 0, beatsPerBar: Int = 4,
         subdivision: Int = 1, countInBeats: Int = 4, notes: String = "") {
        self.id = id; self.name = name; self.intervals = intervals; self.rounds = rounds; self.stepBPM = stepBPM
        self.beatsPerBar = beatsPerBar; self.subdivision = subdivision; self.countInBeats = countInBeats; self.notes = notes
    }

    private enum CodingKeys: String, CodingKey { case id, name, intervals, rounds, stepBPM, beatsPerBar, subdivision, countInBeats, notes, intro }

    /// Data files need only a name and intervals; everything else has a default.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        intervals = try c.decode([Interval].self, forKey: .intervals)
        rounds = try c.decodeIfPresent(Int.self, forKey: .rounds) ?? 1
        stepBPM = try c.decodeIfPresent(Int.self, forKey: .stepBPM) ?? 0
        beatsPerBar = try c.decodeIfPresent(Int.self, forKey: .beatsPerBar) ?? 4
        subdivision = try c.decodeIfPresent(Int.self, forKey: .subdivision) ?? 1
        countInBeats = try c.decodeIfPresent(Int.self, forKey: .countInBeats) ?? 4
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        intro = try c.decodeIfPresent(String.self, forKey: .intro) ?? ""
    }

    /// The same routine, whatever the ids: the name, the blocks, the rounds and the feel.
    func sameContent(as o: Routine) -> Bool {
        guard name == o.name, rounds == o.rounds, stepBPM == o.stepBPM, beatsPerBar == o.beatsPerBar,
              subdivision == o.subdivision, countInBeats == o.countInBeats, intervals.count == o.intervals.count else { return false }
        for (a, b) in zip(intervals, o.intervals) {
            if a.kind != b.kind || a.seconds != b.seconds || a.label != b.label { return false }
            if a.kind == .play && a.bpm != b.bpm { return false }
        }
        return true
    }

    func bpm(of interval: Interval, round: Int) -> Int {
        min(max(interval.bpm + round * stepBPM, Routine.bpmRange.lowerBound), Routine.bpmRange.upperBound)
    }

    var plan: RoutinePlan { RoutinePlan(self) }

    /// "8 rounds, 100 to 128 bpm, 12:00"
    var summary: String {
        let p = plan
        var parts: [String] = []
        if rounds > 1 { parts.append("\(rounds) rounds") }
        let tempos = p.segments.filter { $0.kind == .play }.map { Int($0.bpm) }
        if let lo = tempos.min(), let hi = tempos.max() {
            parts.append(lo == hi ? "\(lo) bpm" : "\(lo) to \(hi) bpm")
        }
        parts.append(formatClock(p.total))
        return parts.joined(separator: ", ")
    }
}

struct Segment: Equatable {
    enum Kind: Equatable { case countIn, play, rest, motion }
    var kind: Kind
    var start: Double      // seconds from the start of the plan
    var duration: Double
    var bpm: Double
    var round: Int          // 0-based
    var intervalIndex: Int  // -1 for the count-in
    var title: String
    var end: Double { start + duration }
}

/// The routine laid out on a timeline: a count-in, then every interval of every round.
struct RoutinePlan: Equatable {
    var segments: [Segment] = []
    var total: Double = 0
    var rounds: Int = 1

    init(_ r: Routine) {
        rounds = max(1, r.rounds)
        var t = 0.0
        let firstPlay = r.intervals.first(where: { $0.kind == .play })
        if r.countInBeats > 0, let first = firstPlay, r.intervals.first?.kind == .play {
            let bpm = Double(r.bpm(of: first, round: 0))
            let d = Double(r.countInBeats) * 60 / bpm
            segments.append(Segment(kind: .countIn, start: 0, duration: d, bpm: bpm, round: 0, intervalIndex: -1, title: "Get ready"))
            t = d
        }
        for round in 0..<rounds {
            for (i, iv) in r.intervals.enumerated() where iv.seconds > 0 {
                let kind: Segment.Kind = iv.kind == .play ? .play : (iv.kind == .rest ? .rest : .motion)
                let bpm = Double(r.bpm(of: iv, round: round))
                segments.append(Segment(kind: kind, start: t, duration: Double(iv.seconds), bpm: bpm, round: round, intervalIndex: i, title: iv.title))
                t += Double(iv.seconds)
            }
        }
        total = t
    }

    /// Index of the segment playing at `time` (nil before 0 or after the end).
    func index(at time: Double) -> Int? {
        guard time >= 0, time < total else { return nil }
        var lo = 0, hi = segments.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if segments[mid].start <= time { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Tempo of the first play segment after `index`, for the count-in at the end of a rest.
    func nextPlayBPM(after index: Int) -> Double? {
        guard index + 1 < segments.count else { return nil }
        let next = segments[index + 1]
        return next.kind == .play ? next.bpm : nil
    }

    struct Status: Equatable {
        var index: Int
        var segment: Segment
        var timeLeft: Double
        var progress: Double
        var next: Segment?
        var totalLeft: Double
        var finished: Bool
    }

    func status(at time: Double) -> Status? {
        guard !segments.isEmpty else { return nil }
        if time >= total {
            let last = segments[segments.count - 1]
            return Status(index: segments.count - 1, segment: last, timeLeft: 0, progress: 1, next: nil, totalLeft: 0, finished: true)
        }
        let i = index(at: max(0, time)) ?? 0
        let s = segments[i]
        let left = max(0, s.end - max(0, time))
        return Status(index: i, segment: s, timeLeft: left, progress: s.duration > 0 ? 1 - left / s.duration : 1,
                      next: i + 1 < segments.count ? segments[i + 1] : nil, totalLeft: max(0, total - time), finished: false)
    }
}

func formatClock(_ seconds: Double) -> String {
    let s = Int(seconds.rounded(.up))
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Starter routines: Library/Resources/routines.json, from Joe's Perfect Picking Course page

extension Routine {
    static var starters: [Routine] { Library.loadStarterRoutines() }
}
