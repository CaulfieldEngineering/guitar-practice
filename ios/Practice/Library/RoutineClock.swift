import Foundation

/// The routine runner's clock, line for line the same as shared/routine-clock.mjs (the reference, with the shared
/// test vectors in shared/routine-vectors.json) and desktop/src/core/RoutineClock.cpp.
///
/// A routine is blocks in order. Before each block a short countdown (3 seconds, a tick each second, a chime as the
/// block starts). A block with seconds ends by itself when they have run; one without (a drill, which ends when its
/// run does) ends when the app says so. Pause holds the clock, in a countdown too; Skip ends the block now and moves
/// on (in a countdown, it starts the block at once); Back starts the block again, or in its first 3 seconds or in a
/// countdown, goes to the block before. Time is passed in, so the rules are tested without waiting.
struct RoutineClock: Equatable {
    enum Phase: String, Equatable { case idle, countdown, block, paused, done }
    enum Event: Equatable { case start(Int), end(Int), done }
    struct Log: Equatable { var seconds: Double = 0; var skipped = false; var done = false }
    struct State: Equatable {
        var phase: Phase
        var index: Int
        var left: Double?
        var paused: Bool
        var countdownTick: Int?
    }

    static let countdownSeconds: Double = 3
    static let backGrace: Double = 3

    let blocks: [Double?]
    let countdown: Double
    private(set) var phase: Phase = .idle
    private(set) var index = 0
    private var since: Double = 0
    private var used: Double = 0
    private var held: Phase?
    private(set) var log: [Log]

    init(blocks: [Double?], countdown: Double = RoutineClock.countdownSeconds) {
        self.blocks = blocks
        self.countdown = countdown
        log = Array(repeating: Log(), count: blocks.count)
    }

    private static func round6(_ x: Double) -> Double { (x * 1e6).rounded() / 1e6 }

    @discardableResult
    mutating func start(_ t: Double) -> [Event] {
        if phase == .idle { enterCountdown(0, t) }
        return tick(t)
    }

    private mutating func enterCountdown(_ i: Int, _ t: Double) {
        if i >= blocks.count { phase = .done; index = blocks.count; return }
        phase = .countdown; index = i; since = t; used = 0
    }

    private func run(_ t: Double) -> Double { used + max(0, t - since) }

    @discardableResult
    mutating func tick(_ t: Double) -> [Event] {
        var events: [Event] = []
        for _ in 0..<64 {
            if phase == .countdown && run(t) >= countdown - 1e-9 {
                let at = since + (countdown - used)
                phase = .block; since = at; used = 0
                events.append(.start(index))
                continue
            }
            if phase == .block, let s = blocks[index], run(t) >= s - 1e-9 {
                let at = since + (s - used)
                log[index].seconds = Self.round6(log[index].seconds + s)
                log[index].done = true
                events.append(.end(index))
                enterCountdown(index + 1, at)
                if phase == .done { events.append(.done) }
                continue
            }
            break
        }
        return events
    }

    mutating func pause(_ t: Double) {
        tick(t)
        guard phase == .countdown || phase == .block else { return }
        used = run(t); held = phase; phase = .paused
    }

    @discardableResult
    mutating func resume(_ t: Double) -> [Event] {
        guard phase == .paused, let h = held else { return [] }
        phase = h; held = nil; since = t
        return tick(t)
    }

    @discardableResult
    mutating func skip(_ t: Double) -> [Event] {
        tick(t)
        let p = phase == .paused ? held : phase
        if p == .countdown { phase = .block; since = t; used = 0; held = nil; return [.start(index)] }
        guard p == .block else { return [] }
        return finishBlock(t, skipped: true)
    }

    /// A block that ends itself (a drill) has finished.
    @discardableResult
    mutating func blockDone(_ t: Double) -> [Event] {
        tick(t)
        guard phase == .block || (phase == .paused && held == .block) else { return [] }
        return finishBlock(t, skipped: false)
    }

    private mutating func finishBlock(_ t: Double, skipped: Bool) -> [Event] {
        let ran = phase == .paused ? used : run(t)
        let i = index
        log[i].seconds = Self.round6(log[i].seconds + ran)
        log[i].skipped = skipped
        log[i].done = !skipped
        held = nil
        var events: [Event] = [.end(i)]
        enterCountdown(i + 1, t)
        if phase == .done { events.append(.done) }
        return events
    }

    mutating func back(_ t: Double) {
        tick(t)
        let p = phase == .paused ? held : phase
        guard p == .countdown || p == .block || phase == .done else { return }
        let ran = phase == .paused ? used : (phase == .done ? 0 : run(t))
        var i = index
        if phase == .done { i = blocks.count - 1 }
        else if p == .countdown || ran < Self.backGrace { i = max(0, i - 1) }
        if p == .block && phase != .done { log[index].seconds = Self.round6(log[index].seconds + ran) }
        held = nil
        enterCountdown(i, t)
    }

    func state(_ t: Double) -> State {
        let p = phase == .paused ? held : phase
        let ran = phase == .paused ? used : run(t)
        var left: Double?
        if p == .countdown { left = max(0, countdown - ran) }
        else if p == .block, index < blocks.count, let s = blocks[index] { left = max(0, s - ran) }
        return State(phase: phase, index: index, left: left.map(Self.round6), paused: phase == .paused,
                     countdownTick: p == .countdown ? Int((max(0, countdown - ran) - 1e-9).rounded(.up)) : nil)
    }

    /// Seconds into the block now (0 in a countdown).
    func ranInBlock(_ t: Double) -> Double {
        let p = phase == .paused ? held : phase
        return p == .block ? (phase == .paused ? used : run(t)) : 0
    }

    /// Seconds left in the whole routine, counting blocks that end themselves at their estimate.
    func remaining(_ t: Double, estimates: [Double] = []) -> Double {
        if phase == .done { return 0 }
        let s = state(t)
        func est(_ i: Int) -> Double { i < estimates.count ? estimates[i] : 0 }
        var total = s.left ?? est(index)
        let p = phase == .paused ? held : phase
        if p == .countdown { total += blocks[index] ?? est(index) }
        for i in (index + 1)..<max(index + 1, blocks.count) { total += countdown + (blocks[i] ?? est(i)) }
        return Self.round6(total)
    }
}
