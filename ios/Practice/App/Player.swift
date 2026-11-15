import AVFoundation
import SwiftUI
import UIKit

/// The app's one player: the metronome, a running routine, or a play-along run. Starting one stops the others.
@MainActor
final class Player: ObservableObject {
    enum Mode: Equatable { case idle, metronome, routine, playAlong }

    let audio = AudioEngine()
    let voice = Voice()
    @Published private(set) var introPlaying = false
    private var lastCueIndex = -1
    @Published private(set) var mode: Mode = .idle
    @Published var errorText: String?

    // The metronome's settings, kept between launches.
    /// The metronome's tempo. Set it with setBPM, which keeps it in range (assigning a property inside its own
    /// didSet recursed until the stack ran out on the iPhone, 0.1.4).
    @Published private(set) var bpm: Int
    @Published var beatsPerBar: Int { didSet { pushParams(); save() } }
    @Published var subdivision: Int { didSet { pushParams(); save() } }
    @Published var accent: Bool { didSet { pushParams(); save() } }
    @Published var volume: Double { didSet { audio.engine?.mainMixerNode.outputVolume = Float(volume); save() } }
    @Published var keepScreenOn: Bool { didSet { save(); updateIdleTimer() } }
    @Published private(set) var currentBeat = -1

    // A running routine.
    @Published private(set) var routine: Routine?
    @Published private(set) var status: RoutinePlan.Status?
    @Published private(set) var paused = false
    private var plan: RoutinePlan?
    private var resumeAt: Double = 0
    private var origin: Double = 0

    private var tapper = TapTempo()
    private var timer: Timer?
    /// Called on every UI frame while running (the play-along reads its input here).
    var onFrame: (() -> Void)?
    var onStopped: (() -> Void)?

    init() {
        let d = UserDefaults.standard
        bpm = d.object(forKey: "bpm") as? Int ?? 100
        beatsPerBar = d.object(forKey: "beatsPerBar") as? Int ?? 4
        subdivision = d.object(forKey: "subdivision") as? Int ?? 1
        accent = d.object(forKey: "accent") as? Bool ?? true
        volume = d.object(forKey: "volume") as? Double ?? 1
        keepScreenOn = d.object(forKey: "keepScreenOn") as? Bool ?? true
        audio.onInterrupted = { [weak self] in self?.interrupted() }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(bpm, forKey: "bpm"); d.set(beatsPerBar, forKey: "beatsPerBar"); d.set(subdivision, forKey: "subdivision")
        d.set(accent, forKey: "accent"); d.set(volume, forKey: "volume"); d.set(keepScreenOn, forKey: "keepScreenOn")
    }

    private func pushParams() {
        guard mode == .metronome || mode == .idle else { return }
        let p = EngineParams(bpm: Double(bpm), beatsPerBar: beatsPerBar, subdivision: subdivision, accent: accent, gridClicks: true)
        audio.params.with { $0 = p }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && mode != .idle && !paused
    }

    // MARK: Metronome

    func toggleMetronome() { mode == .metronome ? stop() : startMetronome() }

    func startMetronome() {
        stop()
        pushParams()
        do {
            try audio.start(record: false) { st, lead in
                st.free = FreeSequencer(sampleRate: st.sampleRate, bpm: Double(bpm), beatsPerBar: beatsPerBar,
                                        subdivision: subdivision, accent: accent, startFrame: lead)
            }
            audio.engine?.mainMixerNode.outputVolume = Float(volume)
            mode = .metronome
            startTimer()
        } catch { fail(error) }
    }

    func tap() {
        if let t = tapper.tap(at: CACurrentMediaTime()) { setBPM(Int(t.rounded())) }
    }

    func setBPM(_ value: Int) {
        let v = min(max(value, Routine.bpmRange.lowerBound), Routine.bpmRange.upperBound)
        guard v != bpm else { return }
        bpm = v
        pushParams()
        save()
    }

    // MARK: Routines

    func load(_ r: Routine) {
        if mode == .routine { stop() }
        routine = r
        plan = r.plan
        resumeAt = 0
        paused = false
        status = plan?.status(at: 0)
    }

    /// Starts (or resumes) the routine; from the top, the voice says what it is first.
    func startRoutine() {
        guard let routine else { return }
        if status?.finished == true { resumeAt = 0 }
        if resumeAt == 0 && voice.introOn && !introPlaying {
            if mode != .idle { stop(keepRoutine: true) }
            introPlaying = true
            voice.speak(IntroText.routine(routine)) { [weak self] in
                guard let self, self.introPlaying else { return }
                self.introPlaying = false
                self.runRoutine()
            }
            return
        }
        runRoutine()
    }

    func skipIntro() { voice.skip() }

    func repeatIntro() {
        guard let routine else { return }
        voice.speak(IntroText.routine(routine), always: true)
    }

    private func runRoutine() {
        guard let routine, let plan else { return }
        let seek = resumeAt
        lastCueIndex = plan.index(at: seek) ?? -1
        if mode != .routine { stop(keepRoutine: true) }
        audio.params.with { $0 = EngineParams(bpm: 100, beatsPerBar: routine.beatsPerBar, subdivision: routine.subdivision, accent: true, gridClicks: true) }
        do {
            try audio.start(record: false) { st, lead in
                origin = lead - seek * st.sampleRate
                st.routine = RoutineSequencer(plan: plan, sampleRate: st.sampleRate, beatsPerBar: routine.beatsPerBar,
                                              subdivision: routine.subdivision, origin: origin, seek: seek)
            }
            audio.engine?.mainMixerNode.outputVolume = Float(volume)
            mode = .routine
            paused = false
            startTimer()
        } catch { fail(error) }
    }

    func pauseRoutine() {
        guard mode == .routine else { return }
        resumeAt = max(0, audio.planTime(origin: origin))
        audio.stop()
        stopTimer()
        paused = true
        updateIdleTimer()
    }

    func toggleRoutine() {
        if introPlaying { introPlaying = false; voice.stop(); return }
        if mode == .routine && !paused { pauseRoutine() } else { startRoutine() }
    }

    func restartRoutine() {
        let wasRunning = mode == .routine && !paused
        stop(keepRoutine: true)
        resumeAt = 0
        status = plan?.status(at: 0)
        if wasRunning { startRoutine() }
    }

    /// Jump to the start of the next interval (or back to the start of this one, or the previous one).
    func skip(forward: Bool) {
        guard let plan, let s = status else { return }
        let i = forward ? s.index + 1 : (s.segment.duration - s.timeLeft > 2 || s.index == 0 ? s.index : s.index - 1)
        guard i < plan.segments.count else { return }
        let wasRunning = mode == .routine && !paused
        if mode == .routine { audio.stop(); stopTimer(); mode = .idle }
        resumeAt = plan.segments[i].start
        status = plan.status(at: resumeAt)
        if wasRunning { startRoutine() } else { paused = resumeAt > 0 }
    }

    // MARK: Play-along

    func startPlayAlong(setup: (RenderState, Double) -> Void, params: EngineParams) throws {
        stop()
        audio.params.with { $0 = params }
        try audio.start(record: true, setup: setup)
        audio.engine?.mainMixerNode.outputVolume = Float(volume)
        mode = .playAlong
        startTimer()
    }

    // MARK: Common

    func stop(keepRoutine: Bool = false) {
        let was = mode
        if introPlaying { introPlaying = false; voice.stop() }
        audio.stop()
        stopTimer()
        mode = .idle
        currentBeat = -1
        if was == .routine && !keepRoutine { resumeAt = 0; paused = false; status = plan?.status(at: 0) }
        updateIdleTimer()
        if was == .playAlong { onStopped?() }
    }

    private func interrupted() {
        switch mode {
        case .routine: pauseRoutine()
        case .idle: break
        default: stop()
        }
    }

    private func fail(_ error: Error) {
        stop()
        errorText = error.localizedDescription
    }

    private func startTimer() {
        stopTimer()
        updateIdleTimer()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.frame() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    private func frame() {
        let r = audio.report.current
        if mode == .metronome || mode == .playAlong {
            let nowFrame = Double(r.frame) - AVAudioSession.sharedInstance().outputLatency * audio.sampleRate
            let beat = Double(r.lastBeatFrame) <= nowFrame ? r.lastBeat : currentBeat
            if beat != currentBeat { currentBeat = beat }
        }
        if mode == .routine, let plan {
            let t = audio.planTime(origin: origin)
            let s = plan.status(at: max(0, t))
            if s != status { status = s }
            if let s, !s.finished, s.index != lastCueIndex {
                lastCueIndex = s.index
                if s.segment.kind != .countIn { voice.speak(IntroText.cue(s.segment, next: s.next), cue: true) }
            }
            let beat = Double(r.lastBeatFrame) <= Double(r.frame) - AVAudioSession.sharedInstance().outputLatency * audio.sampleRate ? r.lastBeat : currentBeat
            if beat != currentBeat { currentBeat = beat }
            // Let the closing chime ring, then stop.
            if r.finished && t > plan.total + 1.8 {
                stop(keepRoutine: true)
                resumeAt = 0
                status = plan.status(at: plan.total)
            }
        }
        onFrame?()
    }
}
