import Foundation
import SwiftData

/// One play-along run, as kept on the phone and sent to the drill server. Version 1 of the results schema.
struct SessionResult: Codable, Identifiable, Equatable, Hashable {
    var schema = 1
    var id: UUID
    var date: Date
    var exerciseID: String
    var exerciseVersion: Int
    var exerciseName: String
    var mode: String              // cycles, duration, endurance
    var ladderStep: Int
    var guided: Bool
    var startBPM: Int
    var topBPM: Int
    var seconds: Double           // time played (count-in not counted)
    var cycles: Int
    var notes: Int
    var hits: Int
    var missed: Int
    var extra: Int
    var pct20: Int                // within the tight window (the exercise's tightMs, 20 unless it says)
    var pct40: Int                // within the close window
    var tightMs: Double
    var closeMs: Double
    var meanErrorMs: Double       // positive is behind the click
    var spreadMs: Double
    var toleranceMs: Double
    var targetPercent: Int
    var accuracyPercent: Int      // within the tolerance
    var sustainedSeconds: Double? // endurance: how long the accuracy held
    var score: Int
    var passed: Bool
    var accentsPercent: Int?
    var offsetMs: Double?
    var appVersion: String

    /// What "best" means for this run: time held for endurance, the score otherwise.
    var bestValue: Double { mode == "endurance" ? (sustainedSeconds ?? 0) : Double(score) }
}

@Model
final class SessionRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var exerciseID: String
    var mode: String
    var startBPM: Int
    var guided: Bool
    var payload: Data
    var uploaded: Bool

    init(_ r: SessionResult) {
        id = r.id; date = r.date; exerciseID = r.exerciseID; mode = r.mode; startBPM = r.startBPM; guided = r.guided
        payload = (try? History.encoder.encode(r)) ?? Data()
        uploaded = false
    }

    var result: SessionResult? { try? History.decoder.decode(SessionResult.self, from: payload) }
}

/// Bests and progress, from any list of results (the phone's or the server's).
enum Stats {
    struct Best: Equatable, Hashable { var exerciseID: String; var mode: String; var bpm: Int; var value: Double; var runs: Int; var last: Date }

    /// The best solo run for each exercise, mode and tempo. Guided runs are kept but not counted as bests.
    static func bests(_ results: [SessionResult]) -> [Best] {
        var map: [String: Best] = [:]
        for r in results where !r.guided {
            let key = "\(r.exerciseID)|\(r.mode)|\(r.startBPM)"
            if var b = map[key] {
                b.value = max(b.value, r.bestValue); b.runs += 1; b.last = max(b.last, r.date); map[key] = b
            } else {
                map[key] = Best(exerciseID: r.exerciseID, mode: r.mode, bpm: r.startBPM, value: r.bestValue, runs: 1, last: r.date)
            }
        }
        return map.values.sorted { ($0.exerciseID, $0.mode, $0.bpm) < ($1.exerciseID, $1.mode, $1.bpm) }
    }

    static func best(_ results: [SessionResult], exerciseID: String, mode: String, bpm: Int) -> Double? {
        bests(results).first { $0.exerciseID == exerciseID && $0.mode == mode && $0.bpm == bpm }?.value
    }

    /// His level on a drill: the tempo he can be trusted to resume at. Rule 1 (the server's learnedTempo is the same,
    /// and the server's answer wins when it can be reached, so the rule can be tuned there): take his last 10 solo runs
    /// of the drill; the ones that passed (at the drill's target, e.g. 85% within 30 ms) give the tempo they reached;
    /// the level is the second highest of those, so one lucky run does not count. With a single pass, that tempo less
    /// one ladder step. None: no level yet.
    static func learnedTempo(_ results: [SessionResult], exerciseID: String, recent: Int = 10, step: Int = 4) -> Int? {
        let solo = results.filter { $0.exerciseID == exerciseID && !$0.guided }.sorted { $0.date > $1.date }.prefix(recent)
        let passed = solo.filter(\.passed).map(\.topBPM).sorted(by: >)
        if passed.count >= 2 { return passed[1] }
        if let one = passed.first { return max(20, one - step) }
        return nil
    }

    /// The fastest starting tempo with a passing solo run.
    static func fastestPass(_ results: [SessionResult], exerciseID: String) -> Int? {
        results.filter { $0.exerciseID == exerciseID && !$0.guided && $0.passed }.map(\.topBPM).max()
    }
}

/// The phone's copy of every run (SwiftData), and the queue of runs not yet acknowledged by the drill server.
@MainActor
final class History: ObservableObject {
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    @Published private(set) var results: [SessionResult] = []
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastSync: Date?
    @Published private(set) var serverReachable: Bool?
    private var syncing = false

    init(inMemory: Bool = false) {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = (try? ModelContainer(for: SessionRecord.self, configurations: config))
            ?? (try! ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        reload()
    }

    func reload() {
        let all = (try? context.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        results = all.compactMap(\.result)
        pendingCount = all.filter { !$0.uploaded }.count
    }

    func add(_ r: SessionResult) {
        context.insert(SessionRecord(r))
        try? context.save()
        reload()
        Task { await sync() }
    }

    func pending() -> [SessionResult] {
        let d = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.uploaded == false })
        return ((try? context.fetch(d)) ?? []).compactMap(\.result)
    }

    func markUploaded(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<SessionRecord>())) ?? []
        for rec in all where ids.contains(rec.id) { rec.uploaded = true }
        try? context.save()
        reload()
    }

    /// Sends every run the server has not acknowledged. Safe to call often: the server keeps each id once, and a run
    /// stays queued until the server says it has it.
    func sync() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        let list = pending()
        guard !list.isEmpty else { return }
        for chunk in stride(from: 0, to: list.count, by: 50).map({ Array(list[$0..<min($0 + 50, list.count)]) }) {
            let stored = await DrillServer.post(chunk)
            serverReachable = !stored.isEmpty
            if stored.isEmpty { return }
            markUploaded(stored)
            lastSync = Date()
        }
    }
}
