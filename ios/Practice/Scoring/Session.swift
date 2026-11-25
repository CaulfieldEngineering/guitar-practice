import Foundation

/// How a play-along run is shaped. Generic for every exercise; each exercise's data gives the starting values.
struct SessionSettings: Codable, Equatable, Hashable {
    /// `routine` is a drill made of timed blocks (Exercise.segments): `cycles` is then its number of rounds and
    /// `ladderStep` how much faster each round is.
    /// `challenge` (2026-11-24): the clock counts only while the accuracy holds at `targetPercent`; done when it has
    /// counted `seconds`, or after `capSeconds` in all (0 is no cap).
    enum Kind: String, Codable, CaseIterable { case cycles, duration, endurance, routine, challenge }
    /// The click's accent: on beat 1 of the bar, on each beat where the notes per beat change (the start of the
    /// triplets and of the sixteenths), or none.
    enum Accent: String, Codable, CaseIterable { case one, groups, off }
    /// The click's sound.
    enum ClickSound: String, Codable, CaseIterable { case click, wood, beep, rim }
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
    /// Ladder: this much faster after each passed cycle (0 is off). Before 0.3.0; still read, and still played when
    /// the tempo plan is off. New runs use `tempoPlan`.
    var ladderStep: Int = 0
    /// Ascending tempo (0.3.0): per loop, or by accuracy with up, down and break thresholds.
    var tempoPlan = TempoPlan()
    /// Challenge: no more than this many seconds in all (0 is no cap).
    var capSeconds: Int = 0
    /// Bars of count-in before the first note (0 to 4).
    var countInBars: Int = 1
    var accent: Accent = .one
    var clickSound: ClickSound = .click
    /// The click's level, 0 to 1.
    var clickLevel: Double = 1
    /// The gap trainer: the click is muted on every `gapEvery`th bar (0 is off); the notes go on and are scored.
    var gapEvery: Int = 0
    /// A tuning for this drill or block only; nil is the guitar's (Settings).
    var tuning: Tuning?

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
        tempoPlan = (try? c.decodeIfPresent(TempoPlan.self, forKey: .tempoPlan)) ?? TempoPlan()
        capSeconds = try c.decodeIfPresent(Int.self, forKey: .capSeconds) ?? 0
        countInBars = try c.decodeIfPresent(Int.self, forKey: .countInBars) ?? 1
        accent = (try? c.decodeIfPresent(Accent.self, forKey: .accent)) ?? .one
        clickSound = (try? c.decodeIfPresent(ClickSound.self, forKey: .clickSound)) ?? .click
        clickLevel = try c.decodeIfPresent(Double.self, forKey: .clickLevel) ?? 1
        gapEvery = try c.decodeIfPresent(Int.self, forKey: .gapEvery) ?? 0
        tuning = try? c.decodeIfPresent(Tuning.self, forKey: .tuning)
    }

    /// Whether the run's length is set by the player (loops or time) or ends by itself (hold, challenge).
    var endsItself: Bool { kind == .endurance || kind == .challenge }

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
    /// A note of the guide: its pitch (a MIDI note, from the drill's string and fret) and whether it is an up stroke.
    var pitch: Int = -1
    var up: Bool = false
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
    /// The click's options for a cycle: where it accents, and which bars it leaves out (the gap trainer).
    struct ClickOptions: Equatable {
        var accent: SessionSettings.Accent = .one
        var gapEvery: Int = 0
        /// A note's pitch from its string and fret (the tuning in use); nil for an X note.
        var tuning: Tuning = .standard
        var pitchFree = false
        init(accent: SessionSettings.Accent = .one, gapEvery: Int = 0, tuning: Tuning = .standard, pitchFree: Bool = false) {
            self.accent = accent; self.gapEvery = gapEvery; self.tuning = tuning; self.pitchFree = pitchFree
        }
        init(_ s: SessionSettings, tuning: Tuning, pitchFree: Bool) {
            self.init(accent: s.accent, gapEvery: s.gapEvery, tuning: tuning, pitchFree: pitchFree)
        }
    }

    /// Whether bar `bar` (counted from 0, from the first note) is a gap: every `every`th bar is muted.
    static func isGap(bar: Int, every: Int) -> Bool { every >= 2 && bar >= 0 && (bar + 1) % every == 0 }

    static func cycle(_ ex: Exercise, index: Int, start: Double, bpm: Double, guided: Bool, limit: Double? = nil,
                      subdivision: Int = 1, options: ClickOptions = ClickOptions()) -> CycleSlot {
        let beat = 60 / max(1, bpm)
        let duration = Double(ex.cycleBeats) * beat
        let cap = limit.map { $0 - start } ?? duration
        let seconds = min(duration, cap)
        var notes = ex.notes(bpm: bpm, start: start, seconds: seconds)
        for i in notes.indices {
            notes[i].beat += index * ex.cycleBeats
            notes[i].pitch = options.pitchFree || notes[i].x ? nil : options.tuning.pitch(string: notes[i].string, fret: notes[i].fret)
        }
        var events: [TimedEvent] = []
        let beatsInRun = Int((seconds / beat - 1e-9).rounded(.up))
        let sizes = groupSizes(ex)
        let perBar = max(1, ex.beatsPerBar)
        for b in 0..<max(0, beatsInRun) {
            let global = index * ex.cycleBeats + b
            let inBar = global % perBar
            if isGap(bar: global / perBar, every: options.gapEvery) { continue }
            let accented: Bool
            switch options.accent {
            case .one: accented = inBar == 0
            case .off: accented = false
            case .groups:
                let local = b % sizes.count
                accented = sizes[local] != sizes[(local - 1 + sizes.count) % sizes.count] || (sizes.count == 1 && inBar == 0)
            }
            events.append(TimedEvent(time: start + Double(b) * beat, kind: accented ? .accent : .beat, beat: inBar))
            if subdivision > 1 {
                for s in 1..<subdivision {
                    let t = (Double(b) + Double(s) / Double(subdivision)) * beat
                    if t < seconds - 1e-9 { events.append(TimedEvent(time: start + t, kind: .sub)) }
                }
            }
        }
        if guided {
            for n in notes {
                if isGap(bar: n.beat / perBar, every: options.gapEvery) { continue }
                let local = n.beat - index * ex.cycleBeats
                let prev = sizes[(local - 1 + sizes.count) % sizes.count]
                let first = n.time - start - Double(local) * beat < 1e-6
                let changed = first && sizes[local % sizes.count] != prev && prev > 0
                events.append(TimedEvent(time: n.time, kind: n.accent || changed ? .pluckAccent : .pluck,
                                         pitch: n.pitch ?? GuitarBank.pitch(string: n.string, fret: n.fret), up: n.pick == .up))
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
