import Foundation

/// Tap tempo: the average of the last few gaps between taps. A pause of more than two seconds starts over.
struct TapTempo {
    private(set) var taps: [Double] = []
    var maxTaps = 5
    var resetAfter = 2.0

    /// Returns the tempo once there are two taps or more.
    mutating func tap(at time: Double) -> Double? {
        if let last = taps.last, time - last > resetAfter || time <= last { taps.removeAll() }
        taps.append(time)
        if taps.count > maxTaps { taps.removeFirst(taps.count - maxTaps) }
        guard taps.count >= 2 else { return nil }
        let gap = (taps[taps.count - 1] - taps[0]) / Double(taps.count - 1)
        guard gap > 0 else { return nil }
        let bpm = 60 / gap
        return min(max(bpm, Double(Routine.bpmRange.lowerBound)), Double(Routine.bpmRange.upperBound))
    }
}

/// Version numbers "0.1.12" compared part by part.
func isNewer(_ a: String, than b: String) -> Bool {
    let pa = a.split(separator: ".").map { Int($0) ?? 0 }
    let pb = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
        if x != y { return x > y }
    }
    return false
}
