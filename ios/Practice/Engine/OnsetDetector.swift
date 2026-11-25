import Foundation

struct Onset: Equatable {
    var time: Double      // seconds, on the clock the samples were stamped with
    var strength: Float   // peak energy just after the attack, for accents
    /// The pitch heard (MIDI, fractional), when the drill asks for pitches and it could be told; nil otherwise.
    var pitch: Double? = nil
}

/// Finds pick attacks in a guitar signal. A gentle high-pass (the pick's click, not the string's hum), energy in
/// short hops, and an onset where a hop's energy jumps well above both the recent average and the noise floor.
/// Simple on purpose: one string, picked, is the whole job.
struct OnsetDetector {
    let sampleRate: Double
    let hop: Int
    var jumpRatio: Float = 2.5          // energy over the recent average
    var floorRatio: Float = 4           // energy over the noise floor (6 dB)
    var minEnergy: Float = 2e-7         // absolute floor, so silence never triggers
    var refractory: Double = 0.040      // no two onsets closer than this
    /// A new onset has to rise above this share of the last attack's energy, which fades with `envelopeTau` (0.2.2).
    /// A pick's own ring, a bump of the muting hand or the pick leaving the string sit under it; the next pick,
    /// even a soft one after an accent, comes well over it (Joe, 2026-11-17: 61% while "pretty locked in", from 923
    /// extra notes on 1574 that were played, which looked like one pick heard twice).
    var retriggerRatio: Float = 0.3
    var envelopeTau: Double = 0.040
    private var envelope: Float = 0
    private var envelopeCoef: Float = 1

    private var hpA: Float
    private var x1: Float = 0, y1: Float = 0
    private var avg: Float = 0
    private var avgCoef: Float
    // The noise floor: the quietest hop in each of the last ten 200 ms blocks.
    private var blockMins = [Float](repeating: 1e-6, count: 10)
    private var blockMin: Float = .greatestFiniteMagnitude
    private var blockHops = 0
    private var blockIndex = 0
    private var hopsPerBlock: Int
    private var noiseFloor: Float { max(blockMins.min() ?? 1e-6, 1e-9) }
    private var hopBuf: [Float]
    private var hopFill = 0
    private var hopStart: Double = 0
    private var samplesSeen: Int = 0
    private var lastOnset: Double = -1
    private var pending: Onset?
    private var pendingHops = 0
    private(set) var level: Float = 0   // latest hop's RMS, for a meter

    init(sampleRate: Double, highPassHz: Double = 800) {
        self.sampleRate = sampleRate
        hop = max(32, Int((sampleRate * 0.0025).rounded()))
        let rc = 1 / (2 * Double.pi * highPassHz), dt = 1 / sampleRate
        hpA = Float(rc / (rc + dt))
        avgCoef = Float(exp(-Double(hop) / (0.040 * sampleRate)))
        hopsPerBlock = max(1, Int(0.2 * sampleRate) / max(32, Int((sampleRate * 0.0025).rounded())))
        hopBuf = [Float](repeating: 0, count: hop)
        envelopeCoef = Float(exp(-Double(hop) / (envelopeTau * sampleRate)))
    }

    /// Feed samples whose first one was captured at `time` (seconds). Returns the onsets found.
    mutating func process(_ samples: UnsafeBufferPointer<Float>, time: Double) -> [Onset] {
        var out: [Onset] = []
        for (i, x) in samples.enumerated() {
            if hopFill == 0 { hopStart = time + Double(i) / sampleRate }
            let y = hpA * (y1 + x - x1)
            x1 = x; y1 = y
            hopBuf[hopFill] = y
            hopFill += 1
            if hopFill == hop {
                hopFill = 0
                if let o = endHop() { out.append(o) }
            }
        }
        samplesSeen += samples.count
        return out
    }

    mutating func process(_ samples: [Float], time: Double) -> [Onset] {
        samples.withUnsafeBufferPointer { process($0, time: time) }
    }

    private mutating func endHop() -> Onset? {
        var e: Float = 0, peak: Float = 0
        for v in hopBuf { e += v * v; peak = max(peak, abs(v)) }
        e /= Float(hop)
        level = e.squareRoot()
        var finished: Onset?
        if var p = pending {
            p.strength = max(p.strength, e)
            pendingHops += 1
            if pendingHops >= 4 { finished = p; pending = nil } else { pending = p }
        }
        let isOnset = e > minEnergy && e > avg * jumpRatio && e > noiseFloor * floorRatio
            && e > envelope * retriggerRatio
            && (lastOnset < 0 || hopStart - lastOnset >= refractory)
        if isOnset {
            // The attack inside the hop: the first sample at half the hop's peak.
            var k = 0
            while k < hop - 1 && abs(hopBuf[k]) < peak * 0.5 { k += 1 }
            let t = hopStart + Double(k) / sampleRate
            if let p = pending { finished = p }
            pending = Onset(time: t, strength: e)
            pendingHops = 0
            lastOnset = t
            envelope = e
        } else if pending != nil {
            // The attack is still building over the hops after it: the envelope holds its peak.
            envelope = max(envelope, e)
        }
        envelope *= envelopeCoef
        avg = avgCoef * avg + (1 - avgCoef) * e
        blockMin = min(blockMin, e)
        blockHops += 1
        if blockHops >= hopsPerBlock {
            blockMins[blockIndex] = blockMin
            blockIndex = (blockIndex + 1) % blockMins.count
            blockMin = .greatestFiniteMagnitude
            blockHops = 0
        }
        return finished
    }

    /// The onset still waiting for its strength, if any (call at the end of a run).
    mutating func flush() -> Onset? { defer { pending = nil }; return pending }
}
