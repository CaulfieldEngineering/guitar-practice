import Foundation

// Ascending tempo and the Challenge clock, line for line the same as shared/tempo-plan.mjs (the reference, with the
// shared test vectors in shared/tempo-vectors.json) and the desktop app's desktop/src/core/TempoPlan.cpp.
//
// Joe, 2026-11-24: "perhaps we can have it ascend either per loop, or threshold average accuracy sustained per x
// duration"; "Similarly, a slow down BPM based on average sustained poor accuracy. And a paused break when dropping
// below even lower threshold accuracy"; and "some kind of 'Challenge' mode that counts duration but only counts
// towards the time when the accuracy is above a certain threshold".

/// How the tempo moves during a run. Off by default; set on the drill's screen before Start.
struct TempoPlan: Codable, Equatable, Hashable {
    enum Mode: String, Codable, CaseIterable { case off, perLoop, accuracy }
    enum Unit: String, Codable, CaseIterable { case loops, seconds }
    enum AtTop: String, Codable, CaseIterable { case hold, restart }

    var mode: Mode = .off
    /// The top; 0 is the drill's max tempo.
    var endBPM: Int = 0
    var step: Int = 4
    /// Per loop: a step every `every` loops (or seconds).
    var every: Int = 2
    var everyUnit: Unit = .loops
    var atTop: AtTop = .hold
    /// By accuracy: the windows are counted in loops or in seconds.
    var windowUnit: Unit = .loops
    var upPercent: Int = 90
    var upWindow: Int = 4
    var downOn = true
    var downPercent: Int = 75
    var downWindow: Int = 4
    var breakOn = false
    var breakPercent: Int = 50
    var breakWindow: Int = 4
    var breakSeconds: Int = 25
    var slowerAfterBreak = true
    var cooldownLoops: Int = 1
    /// The floor; 0 is the start tempo.
    var minBPM: Int = 0

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = TempoPlan()
        mode = (try? c.decodeIfPresent(Mode.self, forKey: .mode)) ?? def.mode
        endBPM = try c.decodeIfPresent(Int.self, forKey: .endBPM) ?? def.endBPM
        step = try c.decodeIfPresent(Int.self, forKey: .step) ?? def.step
        every = try c.decodeIfPresent(Int.self, forKey: .every) ?? def.every
        everyUnit = (try? c.decodeIfPresent(Unit.self, forKey: .everyUnit)) ?? def.everyUnit
        atTop = (try? c.decodeIfPresent(AtTop.self, forKey: .atTop)) ?? def.atTop
        windowUnit = (try? c.decodeIfPresent(Unit.self, forKey: .windowUnit)) ?? def.windowUnit
        upPercent = try c.decodeIfPresent(Int.self, forKey: .upPercent) ?? def.upPercent
        upWindow = try c.decodeIfPresent(Int.self, forKey: .upWindow) ?? def.upWindow
        downOn = try c.decodeIfPresent(Bool.self, forKey: .downOn) ?? def.downOn
        downPercent = try c.decodeIfPresent(Int.self, forKey: .downPercent) ?? def.downPercent
        downWindow = try c.decodeIfPresent(Int.self, forKey: .downWindow) ?? def.downWindow
        breakOn = try c.decodeIfPresent(Bool.self, forKey: .breakOn) ?? def.breakOn
        breakPercent = try c.decodeIfPresent(Int.self, forKey: .breakPercent) ?? def.breakPercent
        breakWindow = try c.decodeIfPresent(Int.self, forKey: .breakWindow) ?? def.breakWindow
        breakSeconds = try c.decodeIfPresent(Int.self, forKey: .breakSeconds) ?? def.breakSeconds
        slowerAfterBreak = try c.decodeIfPresent(Bool.self, forKey: .slowerAfterBreak) ?? def.slowerAfterBreak
        cooldownLoops = try c.decodeIfPresent(Int.self, forKey: .cooldownLoops) ?? def.cooldownLoops
        minBPM = try c.decodeIfPresent(Int.self, forKey: .minBPM) ?? def.minBPM
    }

    private static func clamp(_ x: Int, _ lo: Int, _ hi: Int) -> Int { min(max(x, lo), max(lo, hi)) }

    /// Every number in range and the thresholds kept apart (the hysteresis): down at least 5 under up, the break at
    /// least 5 under down.
    var normalized: TempoPlan {
        var n = self
        n.step = Self.clamp(step, 1, 40)
        n.every = Self.clamp(every, 1, 600)
        n.upPercent = Self.clamp(upPercent, 10, 100)
        n.downPercent = Self.clamp(downPercent, 5, n.upPercent - 5)
        n.breakPercent = Self.clamp(breakPercent, 0, n.downOn ? n.downPercent - 5 : n.upPercent - 10)
        n.upWindow = Self.clamp(upWindow, 1, 600)
        n.downWindow = Self.clamp(downWindow, 1, 600)
        n.breakWindow = Self.clamp(breakWindow, 1, 600)
        n.breakSeconds = Self.clamp(breakSeconds, 5, 300)
        n.cooldownLoops = Self.clamp(cooldownLoops, 0, 16)
        return n
    }

    /// The top and the floor of a run starting at `start` on a drill with this tempo rule.
    func bounds(start: Int, rule: TempoRule) -> (top: Int, floor: Int) {
        let top = endBPM > 0 ? min(endBPM, rule.max) : rule.max
        let floor = minBPM > 0 ? max(rule.min, min(minBPM, start)) : start
        return (max(top, start), floor)
    }

    /// Per loop: the tempo of loop `k` (from 0), which starts `elapsed` seconds into the run.
    func perLoopBPM(start: Int, top: Int, loop k: Int, elapsed: Double) -> Int {
        let steps = everyUnit == .seconds ? Int(((elapsed + 1e-9) / Double(every)).rounded(.down)) : k / max(1, every)
        if top <= start { return start }
        let levels = Int((Double(top - start) / Double(step)).rounded(.up)) + 1
        let i = atTop == .restart ? steps % levels : min(steps, levels - 1)
        return min(top, start + i * step)
    }

    enum Zone: String { case up, hold, down, rest = "break" }

    /// Where an accuracy (0 to 1) sits against the thresholds, for the meter.
    func zone(_ accuracy: Double) -> Zone {
        let pct = accuracy * 100
        if pct >= Double(upPercent) { return .up }
        if downOn && pct >= Double(downPercent) { return .hold }
        if !downOn && (!breakOn || pct >= Double(breakPercent)) { return .hold }
        if breakOn && pct < Double(breakPercent) { return .rest }
        return .down
    }
}

/// A change of tempo in a run, kept with the result (the tempo curve): when (seconds into the run), from and to, and
/// why: up, down, a break, or a step of the per-loop plan.
struct TempoChange: Codable, Equatable, Hashable {
    enum Kind: String, Codable { case up, down, rest = "break", loop }
    var at: Double
    var from: Int
    var to: Int
    var kind: Kind
}

/// By accuracy: judges each loop as it is scored and says when to step up, step down, or stop for a break.
struct TempoGovernor: Equatable {
    struct Change: Equatable { var kind: TempoChange.Kind; var from: Int; var to: Int }
    private struct Loop: Equatable { var accuracy: Double; var seconds: Double }

    let plan: TempoPlan
    let top: Int
    let floor: Int
    private(set) var target: Int
    private var loops: [Loop] = []
    private(set) var cooldown = 0

    init(plan: TempoPlan, start: Int, top: Int, floor: Int) {
        self.plan = plan.normalized
        self.target = start
        self.top = top
        self.floor = floor
    }

    /// Whether the governor is waiting out its cooldown after a change, or has nothing yet at the new tempo.
    var settling: Bool { cooldown > 0 }

    /// The average over the latest loops covering `n` loops (or seconds); nil until they do.
    func average(_ n: Int) -> Double? {
        var covered = 0.0, credit = 0.0, weight = 0.0
        for l in loops.reversed() {
            covered += plan.windowUnit == .seconds ? l.seconds : 1
            credit += l.accuracy * l.seconds
            weight += l.seconds
            if covered >= Double(n) - 1e-9 { return weight > 0 ? credit / weight : 0 }
        }
        return nil
    }

    /// How far toward the next step up, 0 to 1.
    func progress() -> Double {
        let n = Double(plan.upWindow)
        if target >= top { return 0 }
        var covered = 0.0, credit = 0.0, weight = 0.0
        for l in loops.reversed() {
            if covered >= n - 1e-9 { break }
            covered += plan.windowUnit == .seconds ? l.seconds : 1
            credit += l.accuracy * l.seconds
            weight += l.seconds
        }
        if weight <= 0 || credit / weight * 100 < Double(plan.upPercent) { return 0 }
        return min(1, covered / n)
    }

    /// How far toward a step down (or a break), 0 to 1, the same way: the share of the window already under it.
    func progressDown(break isBreak: Bool) -> Double {
        let n = Double(isBreak ? plan.breakWindow : plan.downWindow)
        let line = Double(isBreak ? plan.breakPercent : plan.downPercent)
        var covered = 0.0, credit = 0.0, weight = 0.0
        for l in loops.reversed() {
            if covered >= n - 1e-9 { break }
            covered += plan.windowUnit == .seconds ? l.seconds : 1
            credit += l.accuracy * l.seconds
            weight += l.seconds
        }
        if weight <= 0 || credit / weight * 100 >= line { return 0 }
        return min(1, covered / n)
    }

    mutating func judge(accuracy: Double, seconds: Double, bpm: Int) -> Change? {
        if bpm != target { return nil }
        if cooldown > 0 { cooldown -= 1; return nil }
        loops.append(Loop(accuracy: accuracy, seconds: seconds))
        let p = plan
        let from = target
        var change: Change?
        let b = p.breakOn ? average(p.breakWindow) : nil
        let d = p.downOn ? average(p.downWindow) : nil
        let u = average(p.upWindow)
        if let b, b * 100 < Double(p.breakPercent) {
            change = Change(kind: .rest, from: from, to: p.slowerAfterBreak ? max(floor, from - p.step) : from)
        } else if let d, d * 100 < Double(p.downPercent), from > floor {
            change = Change(kind: .down, from: from, to: max(floor, from - p.step))
        } else if let u, u * 100 >= Double(p.upPercent), from < top {
            change = Change(kind: .up, from: from, to: min(top, from + p.step))
        }
        if let c = change {
            target = c.to
            loops = []
            cooldown = p.cooldownLoops
        }
        return change
    }
}

/// Challenge: the earned time runs only while the rolling accuracy holds at or above the threshold.
struct ChallengeClock: Equatable {
    enum Result: String { case earned, held, done }
    private struct Loop: Equatable { var accuracy: Double; var seconds: Double }

    var target: Double
    var percent: Int
    var window: Int
    /// 0 is no cap.
    var cap: Double
    private(set) var earned: Double = 0
    private(set) var elapsed: Double = 0
    private(set) var streak: Double = 0
    private(set) var bestStreak: Double = 0
    private(set) var inZone = false
    private var loops: [Loop] = []

    init(targetSeconds: Double = 300, percent: Int = 90, window: Int = 2, capSeconds: Double = 0) {
        target = targetSeconds; self.percent = percent; self.window = max(1, window); cap = capSeconds
    }

    private static func round6(_ x: Double) -> Double { (x * 1e6).rounded() / 1e6 }

    var done: Bool { earned >= target - 1e-9 || (cap > 0 && elapsed >= cap - 1e-9) }
    /// The share of the elapsed time that was earned, 0 to 1.
    var share: Double { elapsed > 0 ? earned / elapsed : 0 }

    @discardableResult
    mutating func judge(accuracy: Double, seconds: Double) -> Result {
        if done { return .done }
        loops.append(Loop(accuracy: accuracy, seconds: seconds))
        var credit = 0.0, weight = 0.0
        for l in loops.suffix(window) { credit += l.accuracy * l.seconds; weight += l.seconds }
        let rolling = weight > 0 ? credit / weight : 0
        elapsed = Self.round6(elapsed + seconds)
        inZone = rolling * 100 >= Double(percent) - 1e-9
        if inZone {
            earned = Self.round6(min(target, earned + seconds))
            streak = Self.round6(streak + seconds)
            bestStreak = max(bestStreak, streak)
        } else {
            streak = 0
        }
        return done ? .done : (inZone ? .earned : .held)
    }
}
