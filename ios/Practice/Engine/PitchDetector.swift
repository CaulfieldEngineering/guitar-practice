import Foundation

/// The pitch of a picked note (2026-11-24, for drills whose notes ask for a pitch; an X note never needs it). YIN
/// (de Cheveigné and Kawahara, 2002) over a short stretch of the note just after its attack: the difference
/// function, its cumulative mean normalised form, the first dip under the threshold, and a parabola through it for
/// a fractional period. Range: 50 Hz (under a drop A's low A at 55 Hz) to 1400 Hz. A stretch with no clear period (a
/// muted chug, noise) gives nil, which the scoring never holds against him.
struct PitchDetector {
    let sampleRate: Double
    var minHz: Double = 50
    var maxHz: Double = 1400
    var threshold: Double = 0.15
    /// How much of the note is looked at: long enough for two periods of the lowest note.
    var window: Int { Int((sampleRate * 0.046).rounded()) }
    /// How long after the attack to start: the pick's click is not the string's pitch.
    var skip: Int { Int((sampleRate * 0.008).rounded()) }
    /// How many samples after the attack are needed before a pitch can be worked out.
    var needed: Int { skip + window + Int(sampleRate / minHz) + 2 }

    /// The pitch as a MIDI note (fractional), or nil.
    func midi(_ x: [Float]) -> Double? { hz(x).map { 69 + 12 * log2($0 / 440) } }

    func hz(_ x: [Float]) -> Double? {
        let maxLag = Int(sampleRate / minHz)
        let minLag = max(2, Int(sampleRate / maxHz))
        let w = window
        guard x.count >= w + maxLag + 1 else { return nil }
        var energy: Float = 0
        for i in 0..<w { energy += x[i] * x[i] }
        guard energy / Float(w) > 1e-7 else { return nil }
        var d = [Double](repeating: 0, count: maxLag + 1)
        for tau in 1...maxLag {
            var s = 0.0
            for i in 0..<w {
                let v = Double(x[i] - x[i + tau])
                s += v * v
            }
            d[tau] = s
        }
        // Cumulative mean normalised difference.
        var cmnd = [Double](repeating: 1, count: maxLag + 1)
        var running = 0.0
        for tau in 1...maxLag {
            running += d[tau]
            cmnd[tau] = running > 0 ? d[tau] * Double(tau) / running : 1
        }
        var tau = minLag
        var found: Int?
        while tau <= maxLag {
            if cmnd[tau] < threshold {
                while tau + 1 <= maxLag && cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                found = tau
                break
            }
            tau += 1
        }
        guard let t = found else { return nil }
        var period = Double(t)
        if t > 1 && t < maxLag {
            let a = cmnd[t - 1], b = cmnd[t], c = cmnd[t + 1]
            let den = a - 2 * b + c
            if abs(den) > 1e-12 { period += 0.5 * (a - c) / den }
        }
        let f = sampleRate / period
        return f >= minHz && f <= maxHz ? f : nil
    }
}

/// Collects the samples after each onset until there are enough to tell its pitch, then lets the onset go with its
/// pitch on it. Runs on the input thread, inside AudioOnsetInput, only when the drill has pitched notes.
struct PitchTracker {
    let detector: PitchDetector
    private var pending: [(onset: Onset, samples: [Float])] = []

    init(sampleRate: Double) { detector = PitchDetector(sampleRate: sampleRate) }

    /// One block of input from `host` (seconds), and the onsets found in it. Returns the onsets now complete.
    mutating func process(_ block: UnsafeBufferPointer<Float>, host: Double, onsets: [Onset]) -> [Onset] {
        let rate = detector.sampleRate
        // Samples from the block go to every onset waiting for more.
        for k in pending.indices { pending[k].samples.append(contentsOf: block) }
        for o in onsets {
            let start = max(0, min(block.count, Int(((o.time - host) * rate).rounded())))
            pending.append((o, Array(block[start...])))
        }
        var done: [Onset] = []
        let need = detector.needed
        pending.removeAll { p in
            guard p.samples.count >= need else { return false }
            var o = p.onset
            o.pitch = detector.midi(Array(p.samples[detector.skip...]))
            done.append(o)
            return true
        }
        return done
    }

    /// At the end of a run: whatever is still waiting goes with whatever can be told.
    mutating func flush() -> [Onset] {
        let out = pending.map { p -> Onset in
            var o = p.onset
            if p.samples.count > detector.skip { o.pitch = detector.midi(Array(p.samples[detector.skip...])) }
            return o
        }
        pending.removeAll()
        return out
    }
}
