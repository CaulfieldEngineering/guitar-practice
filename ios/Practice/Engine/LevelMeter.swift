import Foundation

// The input level: the maths behind the meter on the Audio screen, kept apart from AVFoundation so it is unit tested.
// Levels are in dBFS (0 is the loudest a sample can be). The meter shows -60 to 0.

/// Which of the interface's inputs the app listens to (Joe, 2026-11-16: "to define the input"). Both adds the first
/// two inputs into one, so a guitar on either is heard; it is the default, because a guitar on input 2 while the
/// app read only input 1 was silent (0.1.10 and before read the first channel only).
enum InputChannel: String, Codable, CaseIterable, Identifiable {
    case both, first, second
    var id: String { rawValue }

    /// The chosen channel (or the sum of the first two, clamped) into `out`. A missing second channel falls back to
    /// the first.
    static func mix(_ channels: [UnsafePointer<Float>], frames n: Int, pick: InputChannel, into out: UnsafeMutablePointer<Float>) {
        guard n > 0 else { return }
        guard let a = channels.first else { for i in 0..<n { out[i] = 0 }; return }
        let b = channels.count > 1 ? channels[1] : nil
        switch pick {
        case .first:
            for i in 0..<n { out[i] = a[i] }
        case .second:
            let c = b ?? a
            for i in 0..<n { out[i] = c[i] }
        case .both:
            if let b {
                for i in 0..<n { out[i] = min(1, max(-1, a[i] + b[i])) }
            } else {
                for i in 0..<n { out[i] = a[i] }
            }
        }
    }

    /// The same, on arrays (for the tests).
    static func mix(_ channels: [[Float]], pick: InputChannel) -> [Float] {
        let n = channels.map(\.count).min() ?? 0
        var out = [Float](repeating: 0, count: n)
        guard n > 0 else { return out }
        let copies = channels.map { c -> UnsafeMutablePointer<Float> in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
            c.withUnsafeBufferPointer { p.initialize(from: $0.baseAddress!, count: n) }
            return p
        }
        defer { copies.forEach { $0.deallocate() } }
        out.withUnsafeMutableBufferPointer { o in
            mix(copies.map { UnsafePointer($0) }, frames: n, pick: pick, into: o.baseAddress!)
        }
        return out
    }
}

/// What the input tap saw since the meter last looked: enough to give an RMS, a peak, each raw channel's peak (to
/// spot a guitar on the other input) and whether any raw sample reached the top.
struct MeterReading: Equatable {
    var sumSquares: Double = 0
    var frames = 0
    var peak: Float = 0
    var channelPeaks: [Float] = [0, 0]
    var clipped = false

    var rms: Float { frames > 0 ? Float((sumSquares / Double(frames)).squareRoot()) : 0 }

    /// Adds a block of the listened-to signal.
    mutating func add(_ s: UnsafeBufferPointer<Float>) {
        var sq: Double = 0
        var pk: Float = 0
        for x in s {
            sq += Double(x * x)
            pk = max(pk, abs(x))
        }
        sumSquares += sq
        frames += s.count
        peak = max(peak, pk)
        if pk >= Level.clipThreshold { clipped = true }
    }

    /// Adds a raw channel's peak (channel 0 or 1); a raw sample at the top counts as clipping.
    mutating func addChannelPeak(_ index: Int, _ s: UnsafeBufferPointer<Float>) {
        guard index < channelPeaks.count else { return }
        var pk: Float = 0
        for x in s { pk = max(pk, abs(x)) }
        channelPeaks[index] = max(channelPeaks[index], pk)
        if pk >= Level.clipThreshold { clipped = true }
    }

    mutating func add(_ samples: [Float]) { samples.withUnsafeBufferPointer { add($0) } }
}

enum Level {
    /// The bottom of the meter.
    static let floorDB = -60.0
    /// A sample this close to full scale is taken as clipping (about -0.2 dBFS): interfaces hold at just under 1.
    static let clipThreshold: Float = 0.977

    /// Linear (0 to 1) to dBFS; silence is -120.
    static func dB(_ x: Float) -> Double { x <= 0 ? -120 : max(-120, 20 * log10(Double(x))) }

    /// Where a level sits on the meter, 0 at the floor and 1 at full scale.
    static func fraction(_ db: Double) -> Double { min(1, max(0, (db - floorDB) / -floorDB)) }

    /// RMS and peak of a block, linear.
    static func measure(_ samples: [Float]) -> (rms: Float, peak: Float) {
        var r = MeterReading()
        r.add(samples)
        return (r.rms, r.peak)
    }
}

/// The plain readout under the meter.
enum LevelVerdict: Equatable {
    case noSignal, tooQuiet, good, clipping

    /// From the loudest peak of the last few seconds, and whether it clipped. A guitar played normally should peak
    /// between about -18 and -3 dBFS.
    static func from(recentPeakDB: Double, clipping: Bool) -> LevelVerdict {
        if clipping { return .clipping }
        if recentPeakDB < noSignalBelow { return .noSignal }
        if recentPeakDB < tooQuietBelow { return .tooQuiet }
        return .good
    }

    static let noSignalBelow = -50.0
    static let tooQuietBelow = -24.0
}

/// The meter's moving parts: the bar (fast up, slower down), a peak-hold tick that waits then falls, a clip light that
/// stays on for a moment, and the loudest peak of the last few seconds for the readout (so it does not flicker
/// between notes).
struct PeakMeter: Equatable {
    static let holdSeconds = 1.5
    static let fallDBPerSecond = 24.0
    static let clipSeconds = 2.0
    static let recentSeconds = 3.0

    private(set) var levelDB = -120.0
    private(set) var holdDB = -120.0
    private var holdAge = 0.0
    private var clipAge = Double.infinity
    /// The loudest peak of each of the last whole seconds, and of the one going on.
    private var buckets: [Double] = []
    private var bucket = -120.0
    private var bucketAge = 0.0

    /// The loudest peak of the last few seconds.
    var recentPeakDB: Double { max(bucket, buckets.max() ?? -120) }

    var clipping: Bool { clipAge < PeakMeter.clipSeconds }
    var verdict: LevelVerdict { .from(recentPeakDB: recentPeakDB, clipping: clipping) }

    /// One step of the meter, `dt` seconds after the last one.
    mutating func update(peak: Float, clipped: Bool, dt: Double) {
        let db = Level.dB(peak)
        // The bar: jumps up, falls at the release rate.
        levelDB = db >= levelDB ? db : max(db, levelDB - PeakMeter.fallDBPerSecond * 2 * dt)
        // The hold tick.
        if db >= holdDB {
            holdDB = db; holdAge = 0
        } else {
            holdAge += dt
            if holdAge > PeakMeter.holdSeconds { holdDB = max(db, holdDB - PeakMeter.fallDBPerSecond * dt) }
        }
        // The readout's memory: a window of whole seconds.
        bucket = max(bucket, db)
        bucketAge += dt
        if bucketAge >= 1 {
            buckets.append(bucket)
            if buckets.count > Int(PeakMeter.recentSeconds) - 1 { buckets.removeFirst(buckets.count - (Int(PeakMeter.recentSeconds) - 1)) }
            bucket = -120; bucketAge = 0
        }
        clipAge = clipped ? 0 : clipAge + dt
    }

    mutating func reset() { self = PeakMeter() }
}
