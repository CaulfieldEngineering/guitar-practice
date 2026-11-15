import Foundation
import UIKit

/// Saved routines, as JSON in the app's Documents folder. The starters are put in on the first launch.
@MainActor
final class RoutineStore: ObservableObject {
    @Published var routines: [Routine] = [] { didSet { save() } }
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("routines.json")

    init() {
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Routine].self, from: data) {
            routines = list
        } else {
            routines = Routine.starters
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(routines) { try? data.write(to: url, options: .atomic) }
    }

    func upsert(_ r: Routine) {
        if let i = routines.firstIndex(where: { $0.id == r.id }) { routines[i] = r } else { routines.append(r) }
    }

    func duplicate(_ r: Routine) {
        var c = r
        c.id = UUID()
        c.name = r.name + " copy"
        c.intervals = r.intervals.map { var i = $0; i.id = UUID(); return i }
        upsert(c)
    }

    func delete(_ r: Routine) { routines.removeAll { $0.id == r.id } }

    /// Adds back any starter that is missing (by name).
    func restoreStarters() {
        for s in Routine.starters where !routines.contains(where: { $0.name == s.name }) { routines.append(s) }
    }
}

/// Reads the install page's version.json; a newer build shows an Update row that installs from the page.
@MainActor
final class Updater: ObservableObject {
    static let page = "https://caulfieldengineering.github.io/practice-install"
    @Published private(set) var available: String?

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    func check() async {
        guard let url = URL(string: Self.page + "/version.json?t=\(Int(Date().timeIntervalSince1970))") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let v = json["version"] as? String else { return }
        available = isNewer(v, than: current) ? v : nil
    }

    func install() {
        let manifest = Self.page + "/manifest.plist"
        if let url = URL(string: "itms-services://?action=download-manifest&url=\(manifest)") {
            UIApplication.shared.open(url)
        }
    }
}
