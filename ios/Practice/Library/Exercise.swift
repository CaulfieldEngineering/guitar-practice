import Foundation

// The exercise schema, version 1. Exercises are data: Library/Resources/exercises.json in the app, plus any
// *.json files in the app's Documents/Exercises folder (same shape; one with the same id replaces the bundled one).
// README.md, "How to add an exercise", has the full description.

/// Where a note falls: `beat` whole beats into the cycle, plus `step` of `of` (so triplets are exact).
struct GridPosition: Codable, Equatable, Hashable {
    var beat: Int
    var step: Int = 0
    var of: Int = 1
    var beats: Double { Double(beat) + Double(step) / Double(max(1, of)) }

    init(beat: Int, step: Int = 0, of: Int = 1) { self.beat = beat; self.step = step; self.of = of }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        beat = try c.decode(Int.self, forKey: .beat)
        step = try c.decodeIfPresent(Int.self, forKey: .step) ?? 0
        of = try c.decodeIfPresent(Int.self, forKey: .of) ?? 1
    }
}

enum PickDirection: String, Codable { case down, up }

/// One note of the pattern. String and fret are there for left-hand exercises and riffs later; the right-hand
/// exercises leave them out (any string, muted or open).
struct NoteSpec: Codable, Equatable, Hashable {
    var at: GridPosition
    var string: Int?      // 1 is high E
    var fret: Int?
    var pick: PickDirection?
    var accent: Bool = false

    init(at: GridPosition, string: Int? = nil, fret: Int? = nil, pick: PickDirection? = nil, accent: Bool = false) {
        self.at = at; self.string = string; self.fret = fret; self.pick = pick; self.accent = accent
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        at = try c.decode(GridPosition.self, forKey: .at)
        string = try c.decodeIfPresent(Int.self, forKey: .string)
        fret = try c.decodeIfPresent(Int.self, forKey: .fret)
        pick = try c.decodeIfPresent(PickDirection.self, forKey: .pick)
        accent = try c.decodeIfPresent(Bool.self, forKey: .accent) ?? false
    }
}

struct TempoRule: Codable, Equatable, Hashable {
    var start: Int
    var min: Int = 30
    var max: Int = 300
    /// The tempo goes up this much after a passing solo run when "Up after a pass" is on.
    var stepOnPass: Int = 4

    init(start: Int, min: Int = 30, max: Int = 300, stepOnPass: Int = 4) {
        self.start = start; self.min = min; self.max = max; self.stepOnPass = stepOnPass
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        start = try c.decode(Int.self, forKey: .start)
        min = try c.decodeIfPresent(Int.self, forKey: .min) ?? 30
        max = try c.decodeIfPresent(Int.self, forKey: .max) ?? 300
        stepOnPass = try c.decodeIfPresent(Int.self, forKey: .stepOnPass) ?? 4
    }
}

struct ScoringRule: Codable, Equatable, Hashable {
    var passMark: Int = 85
    var tightMs: Double = 20
    var closeMs: Double = 40
    /// The matching window; nil means 100 ms, or less when notes are close together.
    var windowMs: Double?

    init(passMark: Int = 85, tightMs: Double = 20, closeMs: Double = 40, windowMs: Double? = nil) {
        self.passMark = passMark; self.tightMs = tightMs; self.closeMs = closeMs; self.windowMs = windowMs
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        passMark = try c.decodeIfPresent(Int.self, forKey: .passMark) ?? 85
        tightMs = try c.decodeIfPresent(Double.self, forKey: .tightMs) ?? 20
        closeMs = try c.decodeIfPresent(Double.self, forKey: .closeMs) ?? 40
        windowMs = try c.decodeIfPresent(Double.self, forKey: .windowMs)
    }
    static let standard = ScoringRule()
}

/// A named step of an exercise: a tempo and, if it says so, how the run is set up ("Level 3: 110 bpm, endurance at 85%").
struct Level: Codable, Equatable, Hashable {
    var name: String
    var bpm: Int
    var session: SessionSettings?
}

/// A play-along exercise: a cycle of notes on the beat grid, repeated for the length of a run.
struct Exercise: Codable, Identifiable, Equatable, Hashable {
    /// The schema the exercise needs; an app that knows less skips it.
    var schema: Int = 1
    /// Bumped when the exercise itself changes, so results can tell versions apart.
    var version: Int = 1
    var id: String
    var name: String
    var detail: String = ""
    /// What the voice says before the count-in (the tempo and the goal are added to it).
    var intro: String = ""
    var category: String = "Right hand"
    var beatsPerBar: Int = 4
    /// Length of one cycle of the pattern, in beats.
    var cycleBeats: Int
    var notes: [NoteSpec]
    var tempo: TempoRule
    var scoring: ScoringRule = .standard
    /// How a run starts out (cycles, duration or endurance); the player can change it.
    var session: SessionSettings = SessionSettings()
    var levels: [Level] = []

    private enum CodingKeys: String, CodingKey {
        case schema, version, id, name, detail, intro, category, beatsPerBar, cycleBeats, notes, groups, accent, tempo, scoring, session, levels
    }

    init(id: String, name: String, detail: String = "", category: String = "Right hand", beatsPerBar: Int = 4,
         cycleBeats: Int, notes: [NoteSpec], tempo: TempoRule, scoring: ScoringRule = .standard) {
        self.id = id; self.name = name; self.detail = detail; self.category = category; self.beatsPerBar = beatsPerBar
        self.cycleBeats = cycleBeats; self.notes = notes; self.tempo = tempo; self.scoring = scoring
    }

    /// Either `notes` in full, or the shorthand `groups`: notes per beat ([3, 4] is a beat of triplets then a beat
    /// of sixteenths; 0 is a beat of rest), alternate picking starting down, with `accent: "first"` to accent the
    /// first note of each beat.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        session = try c.decodeIfPresent(SessionSettings.self, forKey: .session) ?? SessionSettings()
        levels = try c.decodeIfPresent([Level].self, forKey: .levels) ?? []
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        intro = try c.decodeIfPresent(String.self, forKey: .intro) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "Right hand"
        beatsPerBar = try c.decodeIfPresent(Int.self, forKey: .beatsPerBar) ?? 4
        tempo = try c.decode(TempoRule.self, forKey: .tempo)
        scoring = try c.decodeIfPresent(ScoringRule.self, forKey: .scoring) ?? .standard
        if let list = try c.decodeIfPresent([NoteSpec].self, forKey: .notes) {
            notes = list.sorted { $0.at.beats < $1.at.beats }
            let last = notes.last.map { Int($0.at.beats.rounded(.down)) + 1 } ?? 1
            cycleBeats = try c.decodeIfPresent(Int.self, forKey: .cycleBeats) ?? last
        } else if let groups = try c.decodeIfPresent([Int].self, forKey: .groups) {
            let accent = (try c.decodeIfPresent(String.self, forKey: .accent)) == "first"
            notes = Exercise.expand(groups: groups, accentFirst: accent)
            cycleBeats = groups.count
        } else {
            throw DecodingError.dataCorruptedError(forKey: .notes, in: c, debugDescription: "An exercise needs notes or groups.")
        }
        guard cycleBeats > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .cycleBeats, in: c, debugDescription: "cycleBeats must be at least 1.")
        }
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(detail, forKey: .detail); try c.encode(intro, forKey: .intro)
        try c.encode(category, forKey: .category); try c.encode(beatsPerBar, forKey: .beatsPerBar)
        try c.encode(cycleBeats, forKey: .cycleBeats); try c.encode(notes, forKey: .notes)
        try c.encode(tempo, forKey: .tempo); try c.encode(scoring, forKey: .scoring)
        try c.encode(schema, forKey: .schema); try c.encode(version, forKey: .version)
        try c.encode(session, forKey: .session); try c.encode(levels, forKey: .levels)
    }

    static func expand(groups: [Int], accentFirst: Bool) -> [NoteSpec] {
        var out: [NoteSpec] = []
        var down = true
        for (b, n) in groups.enumerated() where n > 0 {
            for k in 0..<n {
                out.append(NoteSpec(at: GridPosition(beat: b, step: k, of: n), pick: down ? .down : .up, accent: accentFirst && k == 0))
                down.toggle()
            }
        }
        return out
    }

    /// A note to play in a run, in seconds of plan time.
    struct Note: Equatable {
        var time: Double
        var accent: Bool
        var beat: Int           // whole beat of the run, for grouping accents
        var pick: PickDirection? = nil
        var string: Int? = nil
        var fret: Int? = nil
    }

    /// Every note of a run of `seconds` from `start` (seconds) at `bpm`; whole cycles and a partial last one,
    /// nothing at or past the end.
    func notes(bpm: Double, start: Double, seconds: Double) -> [Note] {
        let beat = 60 / max(1, bpm)
        let totalBeats = seconds / beat
        var out: [Note] = []
        guard !notes.isEmpty else { return out }
        var cycle = 0
        while Double(cycle * cycleBeats) < totalBeats - 1e-9 {
            for n in notes {
                let b = Double(cycle * cycleBeats) + n.at.beats
                if b >= totalBeats - 1e-9 { break }
                out.append(Note(time: start + b * beat, accent: n.accent, beat: cycle * cycleBeats + n.at.beat,
                                pick: n.pick, string: n.string, fret: n.fret))
            }
            cycle += 1
        }
        return out
    }

    /// The closest gap between two notes, in seconds at `bpm` (across the cycle's wrap too).
    func shortestGap(bpm: Double) -> Double {
        let beat = 60 / max(1, bpm)
        let pos = notes.map(\.at.beats)
        guard pos.count > 1 else { return beat * Double(cycleBeats) }
        var gap = Double(cycleBeats) - pos.last! + pos.first!
        for i in 1..<pos.count { gap = min(gap, pos[i] - pos[i - 1]) }
        return max(1e-3, gap) * beat
    }

    func window(bpm: Double) -> Double {
        if let w = scoring.windowMs { return w / 1000 }
        return Scoring.window(shortestGap: shortestGap(bpm: bpm))
    }
}

extension Exercise {
    /// Used only if no exercise file could be read.
    static let fallback = Exercise(id: "alt8", name: "Alternate picking, eighths", detail: "Two notes a beat, down up.",
                                   cycleBeats: 1, notes: expand(groups: [2], accentFirst: false), tempo: TempoRule(start: 120))
}
