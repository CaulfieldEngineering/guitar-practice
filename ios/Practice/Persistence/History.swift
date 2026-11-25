import Foundation
import SwiftData

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
