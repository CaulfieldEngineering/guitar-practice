import Foundation
import SwiftUI

/// Dates to the millisecond, so two edits a second apart are told apart (the newer edit of a routine wins).
enum RoutineCoding {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let plain = ISO8601DateFormatter()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { d, enc in var c = enc.singleValueContainer(); try c.encode(withFraction.string(from: d)) }
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let x = withFraction.date(from: s) ?? plain.date(from: s) { return x }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "not a date: \(s)"))
        }
        return d
    }()
}

/// His routines: kept on the phone (Application Support/practice-routines.json) and on the drill server, merged by
/// id with the newer edit winning, so the phone and the computer see the same ones. The catalog's starter routine
/// is there until he saves over it or deletes it.
@MainActor
final class PracticeRoutineStore: ObservableObject {
    /// Every routine he has, deleted ones left out.
    @Published private(set) var routines: [PracticeRoutine] = []
    @Published private(set) var synced: Date?
    private var all: [PracticeRoutine] = []
    private var dirty = Set<String>()

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("practice-routines.json")
    }

    private struct Saved: Codable { var routines: [PracticeRoutine]; var dirty: [String] }
    private struct Wrap: Codable { var routines: [PracticeRoutine] }

    init(load: Bool = true) {
        guard load else { return }
        if let d = try? Data(contentsOf: Self.file), let s = try? RoutineCoding.decoder.decode(Saved.self, from: d) {
            all = s.routines
            dirty = Set(s.dirty)
        }
        all = PracticeRoutine.merge(Self.starters(), all)
        publish()
    }

    /// The catalog's starter routines (catalog/starter-routines.json in the app).
    static func starters() -> [PracticeRoutine] {
        guard let folder = Library.bundledFolder,
              let d = try? Data(contentsOf: folder.appendingPathComponent("starter-routines.json")),
              let w = try? RoutineCoding.decoder.decode(Wrap.self, from: d) else { return [] }
        return w.routines.map { var r = $0; r.starter = true; return r }
    }

    private func publish() {
        routines = all.filter { !$0.deleted }
    }

    private func persist() {
        let s = Saved(routines: all.filter { !$0.starter }, dirty: Array(dirty))
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? RoutineCoding.encoder.encode(s) { try? d.write(to: Self.file, options: .atomic) }
    }

    func routine(_ id: String) -> PracticeRoutine? { routines.first { $0.id == id } }

    /// Saves a routine as he left it (each change, as it is made).
    func save(_ r: PracticeRoutine) {
        var r = r
        r.updatedAt = Date()
        r.starter = false
        if let i = all.firstIndex(where: { $0.id == r.id }) { all[i] = r } else { all.append(r) }
        dirty.insert(r.id)
        persist()
        publish()
        scheduleSync()
    }

    func delete(_ id: String) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].deleted = true
        all[i].starter = false
        all[i].updatedAt = Date()
        dirty.insert(id)
        persist()
        publish()
        scheduleSync()
    }

    @discardableResult
    func duplicate(_ id: String) -> PracticeRoutine? {
        guard let r = routine(id) else { return nil }
        let copy = r.duplicate()
        save(copy)
        return copy
    }

    func newRoutine(drills: [Exercise]) -> PracticeRoutine {
        let r = PracticeRoutine(name: "New routine", blocks: [RoutineBlock.new(.warmup, drills: drills), RoutineBlock.new(.drill, drills: drills)])
        save(r)
        return r
    }

    private var pending: Task<Void, Never>?

    /// Edits come quickly (a stepper held down): the send waits a moment for them to settle.
    private func scheduleSync() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Sends what changed here and takes what changed elsewhere.
    func sync() async {
        let changed = all.filter { dirty.contains($0.id) }
        var req = URLRequest(url: DrillServer.base.appendingPathComponent("api/routines"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? RoutineCoding.encoder.encode(Wrap(routines: changed))
        guard let (data, resp) = try? await DrillServer.session().data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let w = try? RoutineCoding.decoder.decode(Wrap.self, from: data) else { return }
        let sent = Set(changed.map(\.id))
        all = PracticeRoutine.merge(all, w.routines)
        dirty.subtract(sent)
        synced = Date()
        persist()
        publish()
    }
}

/// The routines he has run, kept on the phone until the drill server has them (POST /api/routine-runs).
@MainActor
final class RoutineRunLog: ObservableObject {
    @Published private(set) var runs: [RoutineRunRecord] = []
    private var sent = Set<UUID>()

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("routine-runs.json")
    }
    private struct Saved: Codable { var runs: [RoutineRunRecord]; var sent: [UUID] }
    private struct Wrap: Codable { var runs: [RoutineRunRecord] }

    init() {
        if let d = try? Data(contentsOf: Self.file), let s = try? RoutineCoding.decoder.decode(Saved.self, from: d) {
            runs = s.runs
            sent = Set(s.sent)
        }
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? History.encoder.encode(Saved(runs: runs, sent: Array(sent))) { try? d.write(to: Self.file, options: .atomic) }
    }

    func add(_ r: RoutineRunRecord) {
        runs.insert(r, at: 0)
        persist()
        Task { await sync() }
    }

    /// Sends the runs not yet held; takes every device's runs back for Progress.
    func sync() async {
        let unsent = runs.filter { !sent.contains($0.id) }
        if !unsent.isEmpty {
            var req = URLRequest(url: DrillServer.base.appendingPathComponent("api/routine-runs"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? History.encoder.encode(Wrap(runs: unsent))
            if let (data, resp) = try? await DrillServer.session().data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let ids = json["stored"] as? [String] {
                for s in ids { if let u = UUID(uuidString: s) { sent.insert(u) } }
            }
        }
        if let (data, resp) = try? await DrillServer.session().data(from: DrillServer.base.appendingPathComponent("api/routine-runs")),
           (resp as? HTTPURLResponse)?.statusCode == 200, let w = try? RoutineCoding.decoder.decode(Wrap.self, from: data) {
            var byID = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })
            for r in w.runs { byID[r.id] = r; sent.insert(r.id) }
            runs = byID.values.sorted { $0.date > $1.date }
        }
        persist()
    }
}
