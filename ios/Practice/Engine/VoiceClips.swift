import Foundation

/// The recorded voice: short clips of one calm, natural voice for each drill's spoken line, every tempo, the goals
/// and the few cue words (Joe, 2026-11-14: "can we do a better voice?"). They are made on the mini PC
/// (scripts/make-voice.mjs) into two files, voice/index.json and voice/pack.bin (every clip end to end, each an
/// MP3), which the app carries and which the drill server also serves, so a new drill's line reaches the phone with
/// the catalog and no app update. A clip is used only while its words are still the words to be said; anything
/// without one is spoken by the phone's own voice instead.
@MainActor
final class VoiceClips {
    static let shared = VoiceClips()

    struct Index: Decodable {
        struct Clip: Decodable {
            var o: Int        // where the clip starts in the pack
            var n: Int        // how many bytes it is
            var text: String  // the words it says
        }
        var schema: Int
        var version: Int
        var clips: [String: Clip]
    }

    private(set) var index: Index?
    private var pack: Data?

    var version: Int { index?.version ?? 0 }

    static var bundledFolder: URL? { Bundle.main.url(forResource: "voice", withExtension: nil) }

    static var cacheFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("voice", isDirectory: true)
    }

    init() { load() }

    /// Takes the newer of the app's own clips and the ones pulled from the mini PC.
    func load() {
        var best: (Index, Data)?
        for folder in [VoiceClips.bundledFolder, VoiceClips.cacheFolder].compactMap({ $0 }) {
            guard let found = VoiceClips.read(folder: folder) else { continue }
            if best == nil || found.0.version > best!.0.version { best = found }
        }
        index = best?.0
        pack = best?.1
    }

    /// The index and the pack of a folder, if they are whole.
    static func read(folder: URL) -> (Index, Data)? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("index.json")),
              let index = try? JSONDecoder().decode(Index.self, from: data), index.schema <= 1,
              let pack = try? Data(contentsOf: folder.appendingPathComponent("pack.bin"), options: .mappedIfSafe) else { return nil }
        let needed = index.clips.values.map { $0.o + $0.n }.max() ?? 0
        guard pack.count >= needed else { return nil }
        return (index, pack)
    }

    /// The clip for a key, as long as it says exactly these words.
    func clip(_ key: String, text: String) -> Data? {
        guard let c = index?.clips[key], c.text == text, let pack, c.o >= 0, c.n > 0, c.o + c.n <= pack.count else { return nil }
        return pack.subdata(in: c.o..<(c.o + c.n))
    }

    /// Pulls a newer voice from the mini PC, if it has one. Nothing changes on any failure.
    func refresh() async {
        let s = DrillServer.session(timeout: 20)
        guard let (data, resp) = try? await s.data(from: DrillServer.base.appendingPathComponent("voice/index.json")),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let remote = try? JSONDecoder().decode(Index.self, from: data), remote.schema <= 1,
              remote.version > version else { return }
        guard let (bytes, resp2) = try? await s.data(from: DrillServer.base.appendingPathComponent("voice/pack.bin")),
              (resp2 as? HTTPURLResponse)?.statusCode == 200 else { return }
        let needed = remote.clips.values.map { $0.o + $0.n }.max() ?? 0
        guard bytes.count >= needed else { return }
        let folder = VoiceClips.cacheFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try bytes.write(to: folder.appendingPathComponent("pack.bin"), options: .atomic)
            try data.write(to: folder.appendingPathComponent("index.json"), options: .atomic)
        } catch {
            return
        }
        load()
    }
}
