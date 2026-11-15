import Foundation

/// The guide guitar: short muted notes of a real Strat (the FreePats Strat, public domain; cut by
/// scripts/make-guitar.py into Resources/Guitar), instead of a plucked tone made in code. Thirteen pitches across the
/// neck, each as a hard and a soft recording, two takes of each. A note is played from the nearest pitch, tuned to
/// the note asked for by playing it a little faster or slower; an accent is the hard recording, anything else the
/// soft one; a down stroke and an up stroke are different takes, so a line of alternate picking does not sound like
/// one note repeated. The pitch comes from the drill's string and fret, so left-hand drills play their notes; a
/// right-hand drill, which names no string, plays the open G.
///
/// The samples are read once and never freed (the audio thread plays straight from them).
final class GuitarBank {
    static let pitches = [40, 45, 48, 50, 52, 55, 59, 61, 64, 67, 71, 74, 77]
    /// The open strings, 1 (high E) to 6 (low E), as MIDI notes.
    static let openStrings = [64, 59, 55, 50, 45, 40]
    /// What a drill with no string plays: the open G.
    static let defaultPitch = 55

    /// Read from the app once; nil if the notes are not there (then the made-up pluck is used).
    static let shared: GuitarBank? = GuitarBank(bundle: .main)

    let sampleRate: Double
    /// Four to a pitch: soft take 1, soft take 2, hard take 1, hard take 2.
    let ptrs: [UnsafeMutablePointer<Float>]
    let lengths: [Int]

    init?(bundle: Bundle) {
        var ptrs: [UnsafeMutablePointer<Float>] = []
        var lengths: [Int] = []
        var rate = 0.0
        for pitch in GuitarBank.pitches {
            for name in ["s1", "s2", "h1", "h2"] {
                guard let url = bundle.url(forResource: "g\(pitch)_\(name)", withExtension: "wav"),
                      let data = try? Data(contentsOf: url),
                      let wav = GuitarBank.readWAV(data), !wav.samples.isEmpty else {
                    for p in ptrs { p.deallocate() }
                    return nil
                }
                rate = wav.sampleRate
                let p = UnsafeMutablePointer<Float>.allocate(capacity: wav.samples.count)
                wav.samples.withUnsafeBufferPointer { p.initialize(from: $0.baseAddress!, count: wav.samples.count) }
                ptrs.append(p)
                lengths.append(wav.samples.count)
            }
        }
        guard rate > 0 else { return nil }
        self.ptrs = ptrs
        self.lengths = lengths
        sampleRate = rate
    }

    /// The MIDI note of a string and fret (string 1 is the high E). No string: the open G.
    static func pitch(string: Int?, fret: Int?) -> Int {
        guard let string, string >= 1, string <= openStrings.count else { return defaultPitch }
        return openStrings[string - 1] + max(0, fret ?? 0)
    }

    /// Which recording plays a note, and how much faster (above 1) or slower it runs to be in tune.
    func lookup(pitch: Int, accent: Bool, up: Bool) -> (sample: Int, step: Double) {
        var best = 0
        for (i, p) in GuitarBank.pitches.enumerated() where abs(p - pitch) < abs(GuitarBank.pitches[best] - pitch) { best = i }
        let sample = best * 4 + (accent ? 2 : 0) + (up ? 1 : 0)
        let step = pow(2.0, Double(pitch - GuitarBank.pitches[best]) / 12)
        return (sample, step)
    }

    /// A plain WAV file: 16-bit, the first channel, as numbers from -1 to 1.
    static func readWAV(_ data: Data) -> (samples: [Float], sampleRate: Double)? {
        let bytes = [UInt8](data)
        guard bytes.count > 12, bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46 else { return nil }   // "RIFF"
        func u32(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24 }
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        var i = 12
        var channels = 1, rate = 0, bits = 16
        while i + 8 <= bytes.count {
            let id = String(bytes: bytes[i..<i + 4], encoding: .ascii) ?? ""
            let size = u32(i + 4)
            let body = i + 8
            if id == "fmt ", body + 16 <= bytes.count {
                channels = max(1, u16(body + 2))
                rate = u32(body + 4)
                bits = u16(body + 14)
            } else if id == "data" {
                guard bits == 16, rate > 0 else { return nil }
                let end = min(bytes.count, body + size)
                let frame = 2 * channels
                var out: [Float] = []
                out.reserveCapacity((end - body) / frame)
                var j = body
                while j + 1 < end {
                    let v = Int16(bitPattern: UInt16(bytes[j]) | UInt16(bytes[j + 1]) << 8)
                    out.append(Float(v) / 32768)
                    j += frame
                }
                return (out, Double(rate))
            }
            i = body + size + (size % 2)
        }
        return nil
    }
}
