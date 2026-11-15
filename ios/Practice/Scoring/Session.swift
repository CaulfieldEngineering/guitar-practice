import Foundation

/// How a play-along run is shaped. Generic for every exercise; each exercise's data gives the starting values.
struct SessionSettings: Codable, Equatable, Hashable {
    /// `routine` is a drill made of timed blocks (Exercise.segments): `cycles` is then its number of rounds and
    /// `ladderStep` how much faster each round is.
    enum Kind: String, Codable, CaseIterable { case cycles, duration, endurance, routine }
    var kind: Kind = .cycles
    /// Cycles mode: how many times through the pattern.
    var cycles: Int = 4
    /// Duration mode: total length in seconds.
    var seconds: Int = 60
    /// Endurance (and the ladder): a cycle passes at this accuracy (Scoring.accuracy, as a percentage).
    var targetPercent: Int = 85
    /// Not used since 0.1.6: the timing windows belong to the scoring algorithm (ScoringConfig), not to a setting.
    /// Kept so catalogs and stored settings that carry it still read, and 0.1.5 still finds it.
    var toleranceMs: Double = 30
    /// Endurance: the accuracy is taken over this many cycles in a row.
    var windowCycles: Int = 2
    /// Ladder: this much faster after each passed cycle (0 is off).
    var ladderStep: Int = 0

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .cycles
        cycles = try c.decodeIfPresent(Int.self, forKey: .cycles) ?? 4
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds) ?? 60
        targetPercent = try c.decodeIfPresent(Int.self, forKey: .targetPercent) ?? 85
        toleranceMs = try c.decodeIfPresent(Double.self, forKey: .toleranceMs) ?? 30
        windowCycles = try c.decodeIfPresent(Int.self, forKey: .windowCycles) ?? 2
        ladderStep = try c.decodeIfPresent(Int.self, forKey: .ladderStep) ?? 0
    }

    /// How a drill of timed blocks starts out: its rounds, and how much faster each round is.
    static func routine(rounds: Int, step: Int) -> SessionSettings {
        var s = SessionSettings()
        s.kind = .routine
        s.cycles = max(1, rounds)
        s.ladderStep = step
        return s
    }

    /// Endurance stops on its own; this is the cap so it cannot run forever.
    static let enduranceCap: Double = 20 * 60
}

/// An event of a run in plan seconds (0 is the start of the count-in).
struct TimedEvent: Equatable {
    var time: Double
    var kind: ClickKind
    var beat: Int = -1
}

/// One pass through an exercise's pattern within a run.
struct CycleSlot: Equatable {
    var index: Int
    var start: Double
    var duration: Double
    var bpm: Double
    var notes: [Exercise.Note]
    var events: [TimedEvent]      // clicks and the guide notes, sorted
    var end: Double { start + duration }
}

/// Builds a run one cycle at a time, so the tempo of each cycle can depend on how the last ones went.
enum RunBuilder {
    /// A bar of count-in clicks from time 0.
    static func countIn(beats: Int, bpm: Double) -> (events: [TimedEvent], end: Double) {
        let b = 60 / max(1, bpm)
        let ev = (0..<max(0, beats)).map { TimedEvent(time: Double($0) * b, kind: .countIn, beat: $0) }
        return (ev, Double(max(0, beats)) * b)
    }

    /// Cycle `index` of `exercise` starting at `start`, at `bpm`. Notes at or past `limit` are left out (the end of a
    /// timed run). `guided` adds a pluck for every note, louder on accents and on the first note after the number of
    /// notes in a beat changes (the switch from triplets to sixteenths is heard).
    /// `subdivision` above 1 adds quiet clicks between the beats (a block of a timed routine played solo).
    static func cycle(_ ex: Exercise, index: Int, start: Double, bpm: Double, guided: Bool, limit: Double? = nil,
                      subdivision: Int = 1) -> CycleSlot {
        let beat = 60 / max(1, bpm)
        let duration = Double(ex.cycleBeats) * beat
        let cap = limit.map { $0 - start } ?? duration
        let seconds = min(duration, cap)
        var notes = ex.notes(bpm: bpm, start: start, seconds: seconds)
        for i in notes.indices { notes[i].beat += index * ex.cycleBeats }
        var events: [TimedEvent] = []
        let beatsInRun = Int((seconds / beat - 1e-9).rounded(.up))
        for b in 0..<max(0, beatsInRun) {
            let global = index * ex.cycleBeats + b
            let inBar = global % max(1, ex.beatsPerBar)
            events.append(TimedEvent(time: start + Double(b) * beat, kind: inBar == 0 ? .accent : .beat, beat: inBar))
            if subdivision > 1 {
                for s in 1..<subdivision {
                    let t = (Double(b) + Double(s) / Double(subdivision)) * beat
                    if t < seconds - 1e-9 { events.append(TimedEvent(time: start + t, kind: .sub)) }
                }
            }
        }
        if guided {
            let sizes = groupSizes(ex)
            for n in notes {
                let local = n.beat - index * ex.cycleBeats
                let prev = sizes[(local - 1 + sizes.count) % sizes.count]
                let first = n.time - start - Double(local) * beat < 1e-6
                let changed = first && sizes[local % sizes.count] != prev && prev > 0
                events.append(TimedEvent(time: n.time, kind: n.accent || changed ? .pluckAccent : .pluck))
            }
        }
        events.sort { $0.time < $1.time }
        return CycleSlot(index: index, start: start, duration: seconds, bpm: bpm, notes: notes, events: events)
    }

    /// Notes in each beat of the cycle ([3,3,3,3,4,4,4,4] for triplets then sixteenths).
    static func groupSizes(_ ex: Exercise) -> [Int] {
        var sizes = [Int](repeating: 0, count: max(1, ex.cycleBeats))
        for n in ex.notes where n.at.beat < sizes.count { sizes[n.at.beat] += 1 }
        return sizes
    }

    /// The rolling accuracy over the last `window` cycles (nil until there are that many).
    static func rolling(_ perCycle: [Double], noteCounts: [Int], window: Int) -> Double? {
        let w = max(1, window)
        guard perCycle.count >= w, perCycle.count == noteCounts.count else { return nil }
        let a = perCycle.suffix(w), n = noteCounts.suffix(w)
        let total = n.reduce(0, +)
        guard total > 0 else { return 1 }
        return zip(a, n).map { $0 * Double($1) }.reduce(0, +) / Double(total)
    }

    /// The next cycle's tempo for the ladder: up a step after a pass, the same after a miss.
    static func nextBPM(current: Double, lastPassed: Bool?, step: Int, maxBPM: Int) -> Double {
        guard step > 0, lastPassed == true else { return current }
        return min(Double(maxBPM), current + Double(step))
    }
}
