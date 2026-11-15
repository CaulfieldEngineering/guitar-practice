import Foundation

// The drill catalog. The same folder layout everywhere:
//   index.json                 {"schema": 1, "version": 7, "files": [{"path": "exercises/right-hand.json", "kind": "exercises"}, ...]}
//   exercises/<name>.json      {"schema": 1, "exercises": [...]}
//   routines/<name>.json       {"schema": 1, "routines": [...]}
// It ships inside the app (the repo's catalog/ folder, the starter set), is served by the drill server on the mini PC
// (server/, http://DRILL_SERVER_HOST:4700/catalog/), and the newest one the phone has pulled is cached in Application
// Support/catalog, so the app works away from Tailscale. Loading order: bundled, then cached, then the user folder
// (Documents/Exercises); the same id later replaces the earlier one.

struct CatalogIndex: Codable, Equatable {
    struct File: Codable, Equatable { var path: String; var kind: String }
    var schema: Int
    var version: Int
    var files: [File]
}

enum LibraryError: Error, Equatable { case newerSchema(Int), badPath(String) }

/// One entry that may not decode (a newer drill, a typo): kept as nil instead of failing the whole file.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from d: Decoder) throws { value = try? T(from: d) }
}

private struct ExercisesFile: Decodable { var schema: Int; var exercises: [Lossy<Exercise>] }
private struct RoutinesFile: Decodable { var schema: Int; var routines: [Lossy<Routine>] }

enum Library {
    static let supportedSchema = 1

    /// The exercises in a file this app understands. A file with a newer schema is refused; an exercise inside it
    /// that asks for a newer schema (`"schema": 2`) or does not decode is skipped.
    static func decodeExercises(_ data: Data) throws -> [Exercise] {
        let f = try JSONDecoder().decode(ExercisesFile.self, from: data)
        guard f.schema <= supportedSchema else { throw LibraryError.newerSchema(f.schema) }
        return f.exercises.compactMap(\.value).filter { $0.schema <= supportedSchema }
    }

    static func decodeRoutines(_ data: Data) throws -> [Routine] {
        let f = try JSONDecoder().decode(RoutinesFile.self, from: data)
        guard f.schema <= supportedSchema else { throw LibraryError.newerSchema(f.schema) }
        return f.routines.compactMap(\.value)
    }

    static func decodeIndex(_ data: Data) throws -> CatalogIndex {
        let i = try JSONDecoder().decode(CatalogIndex.self, from: data)
        guard i.schema <= supportedSchema else { throw LibraryError.newerSchema(i.schema) }
        for f in i.files where f.path.contains("..") || f.path.hasPrefix("/") { throw LibraryError.badPath(f.path) }
        return i
    }

    /// Merges lists by id, later lists winning, keeping first-seen order.
    static func merge<T>(_ lists: [[T]], id: (T) -> String) -> [T] {
        var order: [String] = []
        var byID: [String: T] = [:]
        for list in lists { for e in list { let k = id(e); if byID[k] == nil { order.append(k) }; byID[k] = e } }
        return order.compactMap { byID[$0] }
    }

    struct Contents { var exercises: [Exercise]; var routines: [Routine] }

    /// Reads one catalog folder (index.json and the files it names).
    static func read(folder: URL) -> Contents? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("index.json")),
              let index = try? decodeIndex(data) else { return nil }
        var ex: [Exercise] = [], ro: [Routine] = []
        for f in index.files {
            guard let d = try? Data(contentsOf: folder.appendingPathComponent(f.path)) else { continue }
            if f.kind == "exercises", let list = try? decodeExercises(d) { ex += list }
            if f.kind == "routines", let list = try? decodeRoutines(d) { ro += list }
        }
        return Contents(exercises: ex, routines: ro)
    }

    static var bundledFolder: URL? { Bundle.main.url(forResource: "catalog", withExtension: nil) }

    static var cacheFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("catalog", isDirectory: true)
    }

    static var userFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Exercises", isDirectory: true)
    }

    static func load() -> Contents {
        var exLists: [[Exercise]] = [], roLists: [[Routine]] = []
        for folder in [bundledFolder, cacheFolder].compactMap({ $0 }) {
            if let c = read(folder: folder) { exLists.append(c.exercises); roLists.append(c.routines) }
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: userFolder, includingPropertiesForKeys: nil)) ?? []
        for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where f.pathExtension == "json" {
            if let d = try? Data(contentsOf: f), let list = try? decodeExercises(d) { exLists.append(list) }
        }
        let ex = merge(exLists, id: \.id)
        let ro = merge(roLists, id: \.name)
        return Contents(exercises: ex.isEmpty ? [Exercise.fallback] : ex, routines: ro)
    }

    static func loadStarterRoutines() -> [Routine] { load().routines }
}

/// Talks to the drill server on the mini PC: pulls the catalog, posts session results, reads stats.
enum DrillServer {
    static let base = URL(string: "http://DRILL_SERVER_HOST:4700")!

    static func session(timeout: Double = 5) -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout * 3
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }

    static var cachedVersion: Int {
        get { UserDefaults.standard.integer(forKey: "catalog.version") }
        set { UserDefaults.standard.set(newValue, forKey: "catalog.version") }
    }

    enum PullResult: Equatable { case updated(Int), upToDate(Int), unreachable, invalid }

    /// Fetches the index; when its version is newer than the cached one, fetches every file, checks each decodes,
    /// and swaps the cache in whole. Nothing changes on any failure.
    static func pullCatalog() async -> PullResult {
        let s = session()
        guard let (data, resp) = try? await s.data(from: base.appendingPathComponent("catalog/index.json")),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return .unreachable }
        guard let index = try? Library.decodeIndex(data) else { return .invalid }
        let bundled = Library.bundledFolder.flatMap { try? Data(contentsOf: $0.appendingPathComponent("index.json")) }
            .flatMap { try? Library.decodeIndex($0) }?.version ?? 0
        let cached = FileManager.default.fileExists(atPath: Library.cacheFolder.path) ? cachedVersion : 0
        let have = max(cached, bundled)
        if index.version <= have { return .upToDate(have) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            try data.write(to: tmp.appendingPathComponent("index.json"))
            for f in index.files {
                let (d, r) = try await s.data(from: base.appendingPathComponent("catalog/" + f.path))
                guard (r as? HTTPURLResponse)?.statusCode == 200 else { return .unreachable }
                if f.kind == "exercises" { _ = try Library.decodeExercises(d) }
                if f.kind == "routines" { _ = try Library.decodeRoutines(d) }
                let dest = tmp.appendingPathComponent(f.path)
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try d.write(to: dest)
            }
            let cache = Library.cacheFolder
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: cache.path) { try FileManager.default.removeItem(at: cache) }
            try FileManager.default.moveItem(at: tmp, to: cache)
            cachedVersion = index.version
            return .updated(index.version)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return .invalid
        }
    }

    /// Posts results; the server answers with the ids it now holds (it ignores ids it already has).
    static func post(_ results: [SessionResult]) async -> Set<UUID> {
        guard !results.isEmpty else { return [] }
        var req = URLRequest(url: base.appendingPathComponent("api/sessions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let body = try? enc.encode(["sessions": results]) else { return [] }
        req.httpBody = body
        guard let (data, resp) = try? await session().data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ids = json["stored"] as? [String] else { return [] }
        return Set(ids.compactMap(UUID.init(uuidString:)))
    }

    /// Every session the server holds, newest first (nil when it cannot be reached).
    static func fetchSessions(exerciseID: String? = nil) async -> [SessionResult]? {
        var c = URLComponents(url: base.appendingPathComponent("api/sessions"), resolvingAgainstBaseURL: false)!
        if let exerciseID { c.queryItems = [URLQueryItem(name: "exercise", value: exerciseID)] }
        guard let url = c.url, let (data, resp) = try? await session().data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        struct Wrap: Decodable { var sessions: [Lossy<SessionResult>] }
        return (try? dec.decode(Wrap.self, from: data))?.sessions.compactMap(\.value)
    }
}
