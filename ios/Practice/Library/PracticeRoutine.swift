import Foundation

// Routines (Joe, 2026-11-24: "let's build a Routines section where we can interval out warm ups, drills, breaks,
// etc."). A routine is blocks in order: a warm-up (a click at a tempo, or none), a drill (any drill with its own
// setup: tempo, ascending tempo, loops, time, hold or challenge, guide, audio input, options), a break, open practice,
// or a block of his own naming. Kept on the drill server (`/api/routines`) so the phone and the computer have the
// same ones; the newer edit of a routine wins. The shape is the same in desktop/src/app/Routines.cpp and
// server/routines.mjs.

/// How a drill block is set up: the same choices as the drill's own screen.
struct DrillSetup: Codable, Equatable, Hashable {
    var bpm: Int
    var guided = false
    var audioInput = true
    var session = SessionSettings()

    init(bpm: Int, guided: Bool = false, audioInput: Bool = true, session: SessionSettings = SessionSettings()) {
        self.bpm = bpm; self.guided = guided; self.audioInput = audioInput; self.session = session
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        bpm = try c.decodeIfPresent(Int.self, forKey: .bpm) ?? 100
        guided = try c.decodeIfPresent(Bool.self, forKey: .guided) ?? false
        audioInput = try c.decodeIfPresent(Bool.self, forKey: .audioInput) ?? true
        session = (try? c.decodeIfPresent(SessionSettings.self, forKey: .session)) ?? SessionSettings()
    }
}

struct RoutineBlock: Codable, Equatable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case warmup, drill, rest, free, custom }

    var id: String = UUID().uuidString.lowercased()
    var kind: Kind
    var name: String = ""
    /// Warm-up, break, open practice, custom: how long. A drill block runs as its drill's run does.
    var seconds: Int = 180
    /// A click while it runs, at `bpm` (warm-up, open practice, custom).
    var click: Bool = false
    var bpm: Int = 80
    var drillID: String?
    var drill: DrillSetup?

    init(kind: Kind, name: String = "", seconds: Int = 180, click: Bool = false, bpm: Int = 80,
         drillID: String? = nil, drill: DrillSetup? = nil) {
        self.kind = kind; self.name = name; self.seconds = seconds; self.click = click; self.bpm = bpm
        self.drillID = drillID; self.drill = drill
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .custom
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds) ?? 180
        click = try c.decodeIfPresent(Bool.self, forKey: .click) ?? false
        bpm = try c.decodeIfPresent(Int.self, forKey: .bpm) ?? 80
        drillID = try c.decodeIfPresent(String.self, forKey: .drillID)
        drill = try? c.decodeIfPresent(DrillSetup.self, forKey: .drill)
    }

    /// The name to show: his own, else the kind's.
    func title(drills: [Exercise] = []) -> String {
        if !name.isEmpty { return name }
        switch kind {
        case .warmup: return "Warm-up"
        case .rest: return "Break"
        case .free: return "Open practice"
        case .custom: return "Block"
        case .drill:
            let ex = drills.first { $0.id == drillID }
            return ex.map { $0.short.isEmpty ? $0.name : $0.short } ?? "Drill"
        }
    }

    /// Seconds, when the block is a set length (a drill by time counts); nil when it ends by itself.
    var fixedSeconds: Double? {
        if kind != .drill { return Double(max(1, seconds)) }
        return nil
    }

    /// About how long the block takes, for the routine's total.
    func estimate(drills: [Exercise]) -> Double {
        guard kind == .drill, let setup = drill else { return Double(seconds) }
        let s = setup.session
        switch s.kind {
        case .duration: return Double(s.seconds)
        case .challenge: return Double(s.capSeconds > 0 ? min(s.capSeconds, s.seconds * 3 / 2) : s.seconds * 3 / 2)
        case .endurance: return 300
        case .cycles, .routine:
            let beats = Double(drills.first { $0.id == drillID }?.cycleBeats ?? 8)
            return Double(max(1, s.cycles)) * beats * 60 / Double(max(1, setup.bpm))
        }
    }

    static func newDrill(_ ex: Exercise) -> RoutineBlock {
        var s = SessionSettings()
        s.kind = .duration
        s.seconds = 300
        return RoutineBlock(kind: .drill, drillID: ex.id, drill: DrillSetup(bpm: ex.tempo.start, session: s))
    }

    static func new(_ kind: Kind, drills: [Exercise]) -> RoutineBlock {
        switch kind {
        case .warmup: return RoutineBlock(kind: .warmup, seconds: 180, click: true, bpm: 80)
        case .rest: return RoutineBlock(kind: .rest, seconds: 60)
        case .free: return RoutineBlock(kind: .free, seconds: 300, click: false, bpm: 90)
        case .custom: return RoutineBlock(kind: .custom, seconds: 120)
        case .drill: return drills.first.map(newDrill) ?? RoutineBlock(kind: .drill)
        }
    }
}

struct PracticeRoutine: Codable, Equatable, Hashable, Identifiable {
    var id: String = UUID().uuidString.lowercased()
    var name: String
    var blocks: [RoutineBlock]
    var updatedAt: Date = Date()
    var deleted = false
    /// From the catalog, not yet saved over.
    var starter = false

    private enum CodingKeys: String, CodingKey { case id, name, blocks, updatedAt, deleted, starter }

    init(id: String = UUID().uuidString.lowercased(), name: String, blocks: [RoutineBlock], updatedAt: Date = Date()) {
        self.id = id; self.name = name; self.blocks = blocks; self.updatedAt = updatedAt
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id).lowercased()
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        blocks = try c.decodeIfPresent([RoutineBlock].self, forKey: .blocks) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        starter = try c.decodeIfPresent(Bool.self, forKey: .starter) ?? false
    }

    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(updatedAt, forKey: .updatedAt)
        if deleted { try c.encode(true, forKey: .deleted); return }
        try c.encode(name, forKey: .name)
        try c.encode(blocks, forKey: .blocks)
    }

    func estimate(drills: [Exercise]) -> Double {
        blocks.map { $0.estimate(drills: drills) }.reduce(0, +) + Double(blocks.count) * RoutineClock.countdownSeconds
    }

    /// A copy with new ids, named "… copy".
    func duplicate() -> PracticeRoutine {
        var r = self
        r.id = UUID().uuidString.lowercased()
        r.name = name + " copy"
        r.starter = false
        r.updatedAt = Date()
        r.blocks = blocks.map { var b = $0; b.id = UUID().uuidString.lowercased(); return b }
        return r
    }

    /// Merges two lists by id; the newer edit of each wins (a deleted one too, so a delete reaches every device).
    static func merge(_ a: [PracticeRoutine], _ b: [PracticeRoutine]) -> [PracticeRoutine] {
        var byID: [String: PracticeRoutine] = [:]
        var order: [String] = []
        for r in a + b {
            if let have = byID[r.id] {
                if r.updatedAt > have.updatedAt || (r.updatedAt == have.updatedAt && have.starter && !r.starter) { byID[r.id] = r }
            } else {
                byID[r.id] = r
                order.append(r.id)
            }
        }
        return order.compactMap { byID[$0] }
    }
}

/// A routine as it was run: one session in Progress, with each block and, for a drill block, its run.
struct RoutineRunRecord: Codable, Equatable, Hashable, Identifiable {
    struct Block: Codable, Equatable, Hashable {
        var kind: String
        var name: String
        var seconds: Double
        var skipped: Bool = false
        /// A scored drill block's run (SessionResult.id).
        var sessionID: UUID?
        var accuracy: Int?
        var startBPM: Int?
        var topBPM: Int?
    }
    var schema = 1
    var id: UUID
    var date: Date
    var routineID: String
    var routineName: String
    var seconds: Double
    var completed: Bool
    var blocks: [Block]
    var device: String?
    var appVersion: String?
}
