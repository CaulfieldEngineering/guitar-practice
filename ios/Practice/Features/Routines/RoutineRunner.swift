import QuartzCore
import SwiftUI

/// Runs a routine as a guided session (Joe, 2026-11-24): each block in turn, a 3, 2, 1 with a tick before it and a
/// chime as it starts, then auto-advance. A warm-up or open practice plays the click at its tempo (or none); a break
/// is quiet; a drill block runs the drill with the block's own setup, scored when its audio input is on, and ends
/// when its run does. Pause, Skip and Back work on the whole routine. When it ends (or is ended) it is kept as one
/// session in Progress, with each drill block's run. The timing rules are RoutineClock's.
@MainActor
final class RoutineRunner: ObservableObject {
    let player: Player
    let pa: PlayAlong
    let log: RoutineRunLog

    @Published private(set) var routine: PracticeRoutine?
    @Published private(set) var clock = RoutineClock(blocks: [])
    @Published private(set) var now: Double = 0
    @Published private(set) var record: RoutineRunRecord?
    /// The drill block's run that just ended, by block.
    @Published private(set) var results: [Int: SessionResult] = [:]

    private(set) var drills: [Exercise] = []
    private var base: Double = 0
    private var timer: Timer?
    private var lastTick: Int?
    private var runID = UUID()
    private var started = Date()
    /// A drill block being ended by Skip, Back or End: its run's end is not the block finishing.
    private var ending = false

    init(player: Player, pa: PlayAlong, log: RoutineRunLog) {
        self.player = player
        self.pa = pa
        self.log = log
    }

    var active: Bool { routine != nil && record == nil }
    var state: RoutineClock.State { clock.state(now) }
    var block: RoutineBlock? {
        guard let r = routine, clock.index < r.blocks.count else { return nil }
        return r.blocks[clock.index]
    }
    var nextBlock: RoutineBlock? {
        guard let r = routine, clock.index + 1 < r.blocks.count else { return nil }
        return r.blocks[clock.index + 1]
    }
    var estimates: [Double] { routine?.blocks.map { $0.estimate(drills: drills) } ?? [] }
    var remaining: Double { clock.remaining(now, estimates: estimates) }

    /// How far through each block (0 to 1), for the segmented line along the top.
    func fraction(of i: Int) -> Double {
        if i < clock.index || clock.phase == .done { return 1 }
        if i > clock.index { return 0 }
        let ran = clock.ranInBlock(now)
        guard ran > 0 else { return 0 }
        let est = estimates.indices.contains(i) ? estimates[i] : 1
        return min(1, ran / max(1, est))
    }

    func start(_ r: PracticeRoutine, drills: [Exercise]) {
        stopAll()
        self.drills = drills
        routine = r
        record = nil
        results = [:]
        runID = UUID()
        started = Date()
        clock = RoutineClock(blocks: r.blocks.map(\.fixedSeconds))
        base = CACurrentMediaTime()
        now = 0
        lastTick = nil
        pa.routineRunID = runID
        handle(clock.start(0))
        startTimer()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var t: Double { CACurrentMediaTime() - base }

    private func tick() {
        let at = t
        now = at
        handle(clock.tick(at))
        let s = clock.state(at)
        if let n = s.countdownTick, !s.paused, n != lastTick, n > 0 {
            lastTick = n
            Chime.shared.tick(last: n == 1)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
        if s.countdownTick == nil { lastTick = nil }
    }

    private func handle(_ events: [RoutineClock.Event]) {
        for e in events {
            switch e {
            case .start(let i): begin(i)
            case .end(let i): end(i)
            case .done: finish(completed: true)
            }
        }
    }

    private func begin(_ i: Int) {
        guard let r = routine, i < r.blocks.count else { return }
        let b = r.blocks[i]
        Chime.shared.chime()
        switch b.kind {
        case .drill:
            guard let id = b.drillID, let setup = b.drill, drills.contains(where: { $0.id == id }) else {
                handle(clock.skip(t)); return
            }
            ending = false
            pa.onRunEnded = { [weak self] result in
                guard let self else { return }
                if let result { self.results[i] = result }
                if self.ending { return }
                self.handle(self.clock.blockDone(self.t))
            }
            pa.startBlock(PlayAlong.RunSetup(exerciseID: id, bpm: setup.bpm, guided: setup.guided,
                                             audioInput: setup.audioInput, session: setup.session))
            // A drill block that could not start (no interface, say) waits paused with the reason on screen.
            if pa.phase == .ready { clock.pause(t) }
        case .warmup, .free, .custom:
            if b.click { player.startBlockClick(bpm: b.bpm, sound: player.clickSound, level: player.clickLevel) }
        case .rest:
            break
        }
    }

    private func end(_ i: Int) {
        guard let r = routine, i < r.blocks.count else { return }
        if r.blocks[i].kind == .drill {
            stopDrill()
        } else if player.blockClickBPM != nil {
            player.stop()
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func stopDrill() {
        ending = true
        if pa.phase == .running || pa.phase == .paused || pa.phase == .resting || pa.phase == .intro { pa.stop() }
        pa.onRunEnded = nil
        if pa.phase == .result { pa.clearResult() }
        ending = false
    }

    // MARK: Controls

    func pause() {
        guard active, !clock.state(t).paused else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        clock.pause(t)
        now = t
        if block?.kind == .drill {
            if pa.phase == .running { pa.pause() }
        } else if player.blockClickBPM != nil {
            player.stop()
        }
    }

    func resume() {
        guard active, clock.state(t).paused else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let wasBlock = clock.state(t).countdownTick == nil
        handle(clock.resume(t))
        now = t
        guard wasBlock, let b = block else { return }
        switch b.kind {
        case .drill:
            if pa.phase == .paused { pa.resumeRun() }
            else if pa.phase == .ready { begin(clock.index) }
        case .warmup, .free, .custom:
            if b.click { player.startBlockClick(bpm: b.bpm, sound: player.clickSound, level: player.clickLevel) }
        case .rest: break
        }
    }

    func skip() {
        guard active else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if block?.kind == .drill && clock.state(t).countdownTick == nil { stopDrill() }
        handle(clock.skip(t))
        now = t
    }

    func back() {
        guard routine != nil else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if block?.kind == .drill { stopDrill() } else if player.blockClickBPM != nil { player.stop() }
        clock.back(t)
        if record != nil { record = nil; startTimer() }
        now = t
    }

    /// Ends the routine now; what was played is kept.
    func endNow() {
        guard active else { return }
        if block?.kind == .drill { stopDrill() }
        finish(completed: false)
    }

    private func finish(completed: Bool) {
        timer?.invalidate()
        timer = nil
        if player.blockClickBPM != nil { player.stop() }
        if pa.phase != .ready && pa.phase != .result { stopDrill() }
        if pa.phase == .result { pa.clearResult() }
        pa.endBlockSetup()
        UIApplication.shared.isIdleTimerDisabled = false
        guard let r = routine else { return }
        var blocks: [RoutineRunRecord.Block] = []
        var total = 0.0
        for (i, b) in r.blocks.enumerated() {
            let l = i < clock.log.count ? clock.log[i] : RoutineClock.Log()
            let res = results[i]
            let played = l.seconds > 0 || l.done
            blocks.append(RoutineRunRecord.Block(kind: b.kind.rawValue, name: b.title(drills: drills), seconds: l.seconds,
                                                 skipped: l.skipped || !played, sessionID: res?.id,
                                                 accuracy: res?.accuracyPercent, startBPM: res?.startBPM, topBPM: res?.topBPM))
            total += l.seconds
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let rec = RoutineRunRecord(id: runID, date: started, routineID: r.id, routineName: r.name, seconds: total,
                                   completed: completed, blocks: blocks, device: UIDevice.current.name, appVersion: version)
        record = rec
        if total >= 1 { log.add(rec) }
        if completed {
            Chime.shared.chime()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Leaves the finished screen.
    func close() {
        stopAll()
        routine = nil
        record = nil
    }

    private func stopAll() {
        timer?.invalidate()
        timer = nil
        if player.blockClickBPM != nil { player.stop() }
        if pa.runSetup != nil {
            if pa.phase != .ready && pa.phase != .result { stopDrill() }
            if pa.phase == .result { pa.clearResult() }
            pa.endBlockSetup()
        }
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
