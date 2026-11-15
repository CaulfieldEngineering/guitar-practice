import Foundation

/// What a click is. The audio side turns each into a sound.
enum ClickKind: Int, Equatable {
    case accent, beat, sub, countIn, change, rest, done, pluck, pluckAccent
}

struct ClickEvent: Equatable {
    var frame: Int64
    var kind: ClickKind
    /// Beat within the bar for the beat display (-1 when the event is not on a beat).
    var beat: Int = -1
}

/// Ticks for one beat grid: which kind of click tick `k` (0-based, counted from a bar line) is.
@inline(__always)
func gridKind(tick k: Int, beatsPerBar: Int, subdivision: Int, accent: Bool) -> (ClickKind, Int) {
    let sub = max(1, subdivision)
    let perBar = max(1, beatsPerBar) * sub
    let pos = k % perBar
    if pos % sub != 0 { return (.sub, -1) }
    let beat = pos / sub
    return (beat == 0 && accent ? .accent : .beat, beat)
}

/// The free-running metronome. Times are audio frames; the next click is placed by adding the click spacing to
/// the last one in floating point, so the grid never drifts. A tempo change applies from the next click.
struct FreeSequencer {
    var sampleRate: Double
    var bpm: Double
    var beatsPerBar: Int
    var subdivision: Int
    var accent: Bool
    private(set) var nextTick: Double
    private(set) var tick: Int = 0

    init(sampleRate: Double, bpm: Double, beatsPerBar: Int, subdivision: Int, accent: Bool, startFrame: Double) {
        self.sampleRate = sampleRate; self.bpm = bpm; self.beatsPerBar = beatsPerBar
        self.subdivision = subdivision; self.accent = accent; self.nextTick = startFrame
    }

    var spacing: Double { sampleRate * 60 / max(1, bpm) / Double(max(1, subdivision)) }

    /// Calls `emit` for every click in [start, start + count).
    mutating func events(from start: Int64, count: Int, _ emit: (ClickEvent) -> Void) {
        let end = start + Int64(count)
        while true {
            let f = Int64(nextTick.rounded())
            if f >= end { break }
            let perBar = max(1, beatsPerBar) * max(1, subdivision)
            if tick >= perBar { tick %= perBar }
            let (kind, beat) = gridKind(tick: tick, beatsPerBar: beatsPerBar, subdivision: subdivision, accent: accent)
            if f >= start { emit(ClickEvent(frame: f, kind: kind, beat: beat)) }
            tick += 1
            nextTick += spacing
        }
    }
}

/// Plays a routine plan: a bell at each new play interval, a lower bell at each rest, a count-in in the last bar
/// of a rest, clicks on the grid in play intervals (the grid starts over at each interval), silence in motion
/// blocks, and a chime at the end.
struct RoutineSequencer {
    let plan: RoutinePlan
    let sampleRate: Double
    var beatsPerBar: Int
    var subdivision: Int
    var accent: Bool = true
    /// Frame at which plan time 0 happens.
    let origin: Double
    private(set) var index = 0
    private(set) var tick = 0
    private(set) var finished = false
    private var doneSent = false

    init(plan: RoutinePlan, sampleRate: Double, beatsPerBar: Int, subdivision: Int, origin: Double, seek: Double = 0) {
        self.plan = plan; self.sampleRate = sampleRate; self.beatsPerBar = beatsPerBar
        self.subdivision = subdivision; self.origin = origin
        if plan.segments.isEmpty { finished = true; doneSent = true; return }
        if seek > 0 {
            // Skip every click before `seek` (resume, skip ahead).
            let target = origin + seek * sampleRate - 0.5
            while !finished, let t = currentTime(), t < target { advance() }
        }
    }

    private func frame(_ seconds: Double) -> Double { origin + seconds * sampleRate }

    private func beatLength(_ s: Segment) -> Double { 60 / max(1, s.bpm) }

    private func restCountInBeats(_ i: Int) -> Int {
        let s = plan.segments[i]
        guard let next = plan.nextPlayBPM(after: i) else { return 0 }
        let n = max(1, beatsPerBar)
        return s.duration >= Double(n) * 60 / next + 1.0 ? n : 0
    }

    private func tickCount(_ i: Int) -> Int {
        let s = plan.segments[i]
        switch s.kind {
        case .countIn: return Int((s.duration / beatLength(s)).rounded())
        case .play:
            let spacing = beatLength(s) / Double(max(1, subdivision))
            return max(1, Int((s.duration / spacing - 1e-6).rounded(.up)))
        case .rest: return 1 + restCountInBeats(i)
        case .motion: return 1
        }
    }

    /// Frame of the current tick (nil once everything has been sent).
    private func currentTime() -> Double? {
        if index >= plan.segments.count { return doneSent ? nil : frame(plan.total) }
        let s = plan.segments[index]
        switch s.kind {
        case .countIn: return frame(s.start + Double(tick) * beatLength(s))
        case .play: return frame(s.start + Double(tick) * beatLength(s) / Double(max(1, subdivision)))
        case .motion: return frame(s.start)
        case .rest:
            if tick == 0 { return frame(s.start) }
            let n = restCountInBeats(index)
            let next = plan.nextPlayBPM(after: index) ?? s.bpm
            return frame(s.end - Double(n - (tick - 1)) * 60 / next)
        }
    }

    private func currentEvent(at f: Int64) -> ClickEvent {
        if index >= plan.segments.count { return ClickEvent(frame: f, kind: .done) }
        let s = plan.segments[index]
        switch s.kind {
        case .countIn: return ClickEvent(frame: f, kind: .countIn, beat: tick % max(1, beatsPerBar))
        case .motion: return ClickEvent(frame: f, kind: .rest)
        case .rest: return ClickEvent(frame: f, kind: tick == 0 ? .rest : .countIn, beat: tick == 0 ? -1 : (tick - 1))
        case .play:
            if tick == 0 { return ClickEvent(frame: f, kind: .change, beat: 0) }
            let (kind, beat) = gridKind(tick: tick, beatsPerBar: beatsPerBar, subdivision: subdivision, accent: accent)
            return ClickEvent(frame: f, kind: kind, beat: beat)
        }
    }

    private mutating func advance() {
        if index >= plan.segments.count { doneSent = true; finished = true; return }
        tick += 1
        if tick >= tickCount(index) { index += 1; tick = 0 }
    }

    mutating func events(from start: Int64, count: Int, _ emit: (ClickEvent) -> Void) {
        let end = start + Int64(count)
        while !finished, let t = currentTime() {
            let f = Int64(t.rounded())
            if f >= end { break }
            if f >= start { emit(currentEvent(at: f)) }
            advance()
        }
    }
}

/// Events the app schedules while the engine runs (the play-along, a cycle at a time, so the next cycle's tempo can
/// depend on the last). The app appends to `shared`; the audio thread moves them into its own buffer with a
/// try-lock and plays them at their exact frames. The app keeps at least a second queued, so a missed try-lock
/// never makes anything late.
final class EventQueue {
    let shared = Locked<[ClickEvent]>([])
    private var local: [ClickEvent]
    private var head = 0
    private let capacity = 8192

    init() {
        local = []
        local.reserveCapacity(capacity)
        shared.with { $0.reserveCapacity(1024) }
    }

    /// App side: add events, in time order, after the ones already queued.
    func append(_ events: [ClickEvent]) { shared.with { $0.append(contentsOf: events) } }

    /// Audio side.
    func events(from start: Int64, count: Int, _ emit: (ClickEvent) -> Void) {
        if head > capacity / 2 { local.removeFirst(head); head = 0 }
        shared.tryWith { list in
            var taken = 0
            for e in list where local.count < capacity { local.append(e); taken += 1 }
            if taken == list.count { list.removeAll(keepingCapacity: true) } else { list.removeFirst(taken) }
        }
        let end = start + Int64(count)
        while head < local.count && local[head].frame < end {
            if local[head].frame >= start { emit(local[head]) }
            head += 1
        }
    }
}
