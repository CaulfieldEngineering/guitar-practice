import Foundation

/// The sounds, made in code at the engine's sample rate (no audio files). Mono Float buffers.
enum ClickSounds {
    static func make(_ kind: ClickKind, sampleRate sr: Double) -> [Float] {
        switch kind {
        case .accent: return click(sr, freqs: [(2000, 1), (4100, 0.3)], decay: 70, length: 0.06, gain: 0.95)
        case .beat: return click(sr, freqs: [(1400, 1), (2900, 0.25)], decay: 80, length: 0.05, gain: 0.7)
        case .sub: return click(sr, freqs: [(1000, 1)], decay: 110, length: 0.035, gain: 0.35)
        case .countIn: return click(sr, freqs: [(1700, 1), (2950, 0.5)], decay: 90, length: 0.05, gain: 0.8)
        case .change: return click(sr, freqs: [(880, 1), (2210, 0.45), (3520, 0.2)], decay: 3.5, length: 1.0, gain: 0.55)
        case .rest: return click(sr, freqs: [(587, 1), (1470, 0.35)], decay: 4.5, length: 0.8, gain: 0.5)
        case .done:
            var out = [Float](repeating: 0, count: Int(1.6 * sr))
            for (i, f) in [880.0, 1108.7, 1318.5].enumerated() {
                let note = click(sr, freqs: [(f, 1), (f * 2.5, 0.3)], decay: 3.5, length: 1.1, gain: 0.4)
                let at = Int(Double(i) * 0.16 * sr)
                for k in 0..<note.count where at + k < out.count { out[at + k] += note[k] }
            }
            return out
        case .pluck: return pluck(sr, gain: 0.45)
        case .pluckAccent: return pluck(sr, gain: 0.8)
        }
    }

    /// A short tone: a 1 ms rise and an exponential decay.
    static func click(_ sr: Double, freqs: [(Double, Double)], decay: Double, length: Double, gain: Double) -> [Float] {
        let n = Int(length * sr)
        var out = [Float](repeating: 0, count: n)
        let rise = max(1, Int(0.001 * sr))
        var peak: Float = 0
        for i in 0..<n {
            let t = Double(i) / sr
            var s = 0.0
            for (f, a) in freqs { s += a * sin(2 * .pi * f * t) }
            let env = exp(-decay * t) * min(1, Double(i) / Double(rise))
            out[i] = Float(s * env)
            peak = max(peak, abs(out[i]))
        }
        if peak > 0 { for i in 0..<n { out[i] *= Float(gain) / peak } }
        // A short fade at the end so nothing clicks off.
        let fade = min(n, Int(0.004 * sr))
        for k in 0..<fade { out[n - 1 - k] *= Float(k) / Float(fade) }
        return out
    }

    /// A palm-muted guitar note on the low E's B (Karplus-Strong), for the guided play-along.
    static func pluck(_ sr: Double, gain: Double, freq: Double = 123.47) -> [Float] {
        let n = Int(0.22 * sr)
        let period = max(2, Int((sr / freq).rounded()))
        var line = [Float](repeating: 0, count: period)
        var seed: UInt32 = 12345
        for i in 0..<period {
            seed = seed &* 1664525 &+ 1013904223
            line[i] = Float(Int32(bitPattern: seed)) / Float(Int32.max)
        }
        var out = [Float](repeating: 0, count: n)
        var idx = 0
        var peak: Float = 0
        for i in 0..<n {
            let next = (idx + 1) % period
            let v = line[idx]
            line[idx] = 0.5 * (v + line[next]) * 0.985   // the damping of a palm mute
            out[i] = v * Float(exp(-Double(i) / sr * 14))
            peak = max(peak, abs(out[i]))
            idx = next
        }
        if peak > 0 { for i in 0..<n { out[i] *= Float(gain) / peak } }
        let fade = min(n, Int(0.01 * sr))
        for k in 0..<fade { out[n - 1 - k] *= Float(k) / Float(fade) }
        return out
    }
}
