import AVFoundation

/// The routine's sounds between blocks (2026-11-24): a tick on each of 3, 2, 1, and a two-note chime as a block
/// starts or ends. Played on their own player, so they sound whether or not the click is running, and mixed with
/// whatever else is playing. Made in code from the click sounds, as WAV in memory.
@MainActor
final class Chime {
    static let shared = Chime()
    private var players: [AVAudioPlayer] = []
    /// Settings, Sound: the chime and the countdown ticks can each be switched off.
    var chimeOn: Bool { UserDefaults.standard.object(forKey: "sound.chime") as? Bool ?? true }
    var ticksOn: Bool { UserDefaults.standard.object(forKey: "sound.ticks") as? Bool ?? true }

    private lazy var chimeData = Chime.wav(ClickSounds.make(.chime, sampleRate: 44100))
    private lazy var tickData = Chime.wav(ClickSounds.make(.countIn, sampleRate: 44100).map { $0 * 0.6 })
    private lazy var lastTickData = Chime.wav(ClickSounds.make(.accent, sampleRate: 44100).map { $0 * 0.6 })

    func chime() { if chimeOn { play(chimeData) } }
    func tick(last: Bool) { if ticksOn { play(last ? lastTickData : tickData) } }

    private func play(_ data: Data) {
        players.removeAll { !$0.isPlaying }
        guard let p = try? AVAudioPlayer(data: data) else { return }
        p.volume = 1
        p.play()
        players.append(p)
    }

    /// 16-bit mono WAV.
    static func wav(_ samples: [Float], rate: Int = 44100) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32000))) }
        return d
    }
}
