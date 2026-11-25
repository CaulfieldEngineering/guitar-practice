import Foundation
import SwiftUI

/// The guitar's tuning, kept on the device and on the drill server; the newer one wins.
@MainActor
final class TuningStore: ObservableObject {
    static let shared = TuningStore()
    @Published private(set) var tuning: Tuning
    private(set) var updatedAt: Date

    private init() {
        let d = UserDefaults.standard
        tuning = d.data(forKey: "tuning").flatMap { try? JSONDecoder().decode(Tuning.self, from: $0) } ?? .standard
        updatedAt = Date(timeIntervalSince1970: d.double(forKey: "tuning.updatedAt"))
    }

    func set(_ t: Tuning) {
        guard t != tuning else { return }
        tuning = t
        updatedAt = Date()
        save()
        Task { await push() }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(tuning), forKey: "tuning")
        UserDefaults.standard.set(updatedAt.timeIntervalSince1970, forKey: "tuning.updatedAt")
    }

    private struct Remote: Codable { var tuning: Tuning?; var updatedAt: Date? }

    /// Sends this device's tuning; takes the server's when it is newer.
    func sync() async {
        await push()
    }

    private func push() async {
        var req = URLRequest(url: DrillServer.base.appendingPathComponent("api/settings"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = Remote(tuning: tuning, updatedAt: updatedAt.timeIntervalSince1970 > 0 ? updatedAt : Date(timeIntervalSince1970: 1))
        req.httpBody = try? History.encoder.encode(body)
        guard let (data, resp) = try? await DrillServer.session().data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let remote = try? History.decoder.decode(Remote.self, from: data),
              let t = remote.tuning, let at = remote.updatedAt, at > updatedAt else { return }
        tuning = t
        updatedAt = at
        save()
    }
}
