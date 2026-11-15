import AVFoundation
import SwiftUI

/// The play-along: the guitar comes in through a NoteInput (the audio input today), and every note is scored against
/// the one the exercise asks for. Guided plays the exercise as a muted pluck with the click; Solo is the click only.
/// A run is scheduled a cycle at a time, so endurance can stop when the accuracy drops and the ladder can speed up
/// after a passed cycle.
@MainActor
final class PlayAlong: ObservableObject {
    enum Phase: Equatable { case ready, intro, calibrating, running, result }
    enum NoteState { case waiting, tight, close, loose, missed }

    let player: Player
    let history: History
    let input: NoteInput

    @Published private(set) var exercises: [Exercise] = []
    @Published private(set) var catalogNote: String?
    @Published var exerciseID: String { didSet { UserDefaults.standard.set(exerciseID, forKey: "pa.exercise"); loadSettings() } }
    @Published var bpm: Int { didSet { let t = exercise.tempo; bpm = min(max(bpm, t.min), t.max); saveSettings() } }
    @Published var session: SessionSettings { didSet { saveSettings() } }
    @Published var guided: Bool { didSet { UserDefaults.standard.set(guided, forKey: "pa.guided") } }
    @Published var gridClicks: Bool { didSet { UserDefaults.standard.set(gridClicks, forKey: "pa.click") } }
    /// Seconds between when a note is played and when it is heard back here, measured by calibration.
    @Published var offset: Double? { didSet { UserDefaults.standard.set(offset, forKey: "pa.offset") } }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var now: Double = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var score: ScoreResult?
    @Published private(set) var saved: SessionResult?
    @Published private(set) var lastRunWasGuided = false
    @Published private(set) var newBest = false
    @Published private(set) var message: String?
    @Published private(set) var route = AudioEngine.routeDescription()
    @Published private(set) var rolling: Double?          // endurance: accuracy over the last cycles
    @Published private(set) var lastCycleAccuracy: Double?
    @Published private(set) var currentBPM: Double = 0
    @Published private(set) var sustained: Double = 0

    private(set) var notes: [Exercise.Note] = []
    private(set) var played: [Onset] = []       // plan time, calibration applied
    private(set) var states: [NoteState] = []
    private(set) var countInEnd: Double = 0
    private(set) var plannedEnd: Double?        // nil for endurance until it stops
    private var slots: [CycleSlot] = []
    private var noteStart: [Int] = []           // first note index of each slot
    private var accuracies: [Double] = []
    private var lastPassed: Bool?
    private var topBPM = 0
    private var scheduledUntil: Double = 0
    private var doneScheduling = false
    private var runGuided = false
    private var runSettings = SessionSettings()
    private var runExercise: Exercise = .fallback
    private var origin: Double = 0
    private var queue: EventQueue?
    private var calibrationClicks: [Double] = []
    private var errors: [Double?] = []

    var exercise: Exercise { exercises.first { $0.id == exerciseID } ?? exercises.first ?? .fallback }

    init(player: Player, history: History, input: NoteInput = AudioOnsetInput()) {
        self.player = player
        self.history = history
        self.input = input
        let d = UserDefaults.standard
        let lib = Library.load().exercises
        exercises = lib
        let id = d.string(forKey: "pa.exercise").flatMap { s in lib.contains { $0.id == s } ? s : nil } ?? lib[0].id
        exerciseID = id
        let ex = lib.first { $0.id == id } ?? lib[0]
        bpm = d.object(forKey: "pa.bpm.\(id)") as? Int ?? ex.tempo.start
        session = PlayAlong.storedSession(id) ?? ex.session
        guided = d.object(forKey: "pa.guided") as? Bool ?? true
        gridClicks = d.object(forKey: "pa.click") as? Bool ?? true
        offset = d.object(forKey: "pa.offset") as? Double
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.route = AudioEngine.routeDescription() }
        }
    }

    // MARK: Settings per exercise

    private static func storedSession(_ id: String) -> SessionSettings? {
        UserDefaults.standard.data(forKey: "pa.session.\(id)").flatMap { try? JSONDecoder().decode(SessionSettings.self, from: $0) }
    }

    private var loading = false
    private func loadSettings() {
        loading = true
        bpm = UserDefaults.standard.object(forKey: "pa.bpm.\(exerciseID)") as? Int ?? exercise.tempo.start
        session = PlayAlong.storedSession(exerciseID) ?? exercise.session
        loading = false
    }

    private func saveSettings() {
        guard !loading else { return }
        UserDefaults.standard.set(bpm, forKey: "pa.bpm.\(exerciseID)")
        if let d = try? JSONEncoder().encode(session) { UserDefaults.standard.set(d, forKey: "pa.session.\(exerciseID)") }
    }

    func apply(_ level: Level) {
        bpm = level.bpm
        if let s = level.session { session = s }
    }

    // MARK: Catalog

    /// Pulls the drill catalog from the mini PC (when reachable), reloads, and sends any unsent results.
    func refresh() async {
        let r = await DrillServer.pullCatalog()
        switch r {
        case .updated(let v): catalogNote = "Drills updated (catalog \(v))."
        case .upToDate: catalogNote = nil
        case .unreachable: catalogNote = "The mini PC is out of reach; using the drills on the phone."
        case .invalid: catalogNote = "The mini PC's drills could not be read; using the ones on the phone."
        }
        exercises = Library.load().exercises
        if !exercises.contains(where: { $0.id == exerciseID }) { exerciseID = exercises[0].id }
        await history.sync()
    }

    // MARK: Bests

    func best(mode: SessionSettings.Kind? = nil) -> Double? {
        Stats.best(history.results, exerciseID: exerciseID, mode: (mode ?? session.kind).rawValue, bpm: bpm)
    }

    func fastestPass(_ id: String) -> Int? { Stats.fastestPass(history.results, exerciseID: id) }

    // MARK: Runs

    func start() { begin(calibrating: false) }
    func calibrate() { begin(calibrating: true) }
    func nowSolo() { guided = false; start() }
    func clearResult() { score = nil; saved = nil; phase = .ready }

    func stop() {
        if phase == .intro { player.voice.stop(); phase = .ready; return }
        guard phase == .running || phase == .calibrating else { return }
        if phase == .running && !accuracies.isEmpty { finish(stoppedEarly: true) } else { player.stop(); phase = .ready }
    }

    private func begin(calibrating: Bool) {
        message = nil
        switch AVAudioApplication.shared.recordPermission {
        case .granted: break
        case .undetermined:
            AVAudioApplication.requestRecordPermission { ok in
                Task { @MainActor in
                    if ok { self.begin(calibrating: calibrating) } else { self.message = "Allow the microphone in Settings to be scored." }
                }
            }
            return
        default:
            message = "Allow the microphone in Settings, Practice, to be scored."
            return
        }
        if !calibrating && player.voice.introOn {
            phase = .intro
            player.voice.speak(IntroText.exercise(exercise, bpm: bpm, session: session, guided: guided)) { [weak self] in
                guard let self, self.phase == .intro else { return }
                self.launch(calibrating: false)
            }
            return
        }
        launch(calibrating: calibrating)
    }

    func skipIntro() { player.voice.skip() }

    func repeatIntro() { player.voice.speak(IntroText.exercise(exercise, bpm: bpm, session: session, guided: guided), always: true) }

    private var lastCueBeat = -1
    private var lastCueBPM: Double = 0

    /// Spoken cues in a run: the next beat's change of notes per beat, and a new tempo on the ladder. Not on the
    /// phone's speaker and microphone, where the phone would hear itself.
    private func speakCues() {
        guard player.voice.cuesOn, !route.phoneSpeakerAndMic, phase == .running, let s = currentSlot else { return }
        if s.bpm != lastCueBPM {
            if lastCueBPM > 0 { player.voice.speak("\(Int(s.bpm))", cue: true) }
            lastCueBPM = s.bpm
            return
        }
        guard let cue = groupCue, cue.beatsUntil == 1 else { return }
        let beatIndex = Int((now - countInEnd) / (60 / s.bpm))
        guard beatIndex != lastCueBeat else { return }
        lastCueBeat = beatIndex
        let word = cue.next == 3 ? "Triplets" : (cue.next == 4 ? "Sixteenths" : (cue.next == 2 ? "Eighths" : (cue.next == 0 ? "Rest" : "\(cue.next)")))
        player.voice.speak(word, cue: true)
    }

    private func launch(calibrating: Bool) {
        lastCueBeat = -1
        lastCueBPM = 0
        runExercise = exercise
        runSettings = session
        runGuided = guided && !calibrating
        lastRunWasGuided = runGuided
        let startBPM = Double(calibrating ? 80 : bpm)
        currentBPM = startBPM
        topBPM = Int(startBPM)
        slots = []; noteStart = []; notes = []; states = []; played = []; errors = []
        accuracies = []; lastPassed = nil; rolling = nil; lastCycleAccuracy = nil; sustained = 0
        score = nil; saved = nil; newBest = false
        doneScheduling = false
        plannedEnd = nil
        let beats = runExercise.beatsPerBar
        let (countEvents, cEnd) = RunBuilder.countIn(beats: beats, bpm: startBPM)
        countInEnd = cEnd
        scheduledUntil = cEnd
        if calibrating {
            calibrationClicks = (0..<8).map { cEnd + Double($0) * 60 / startBPM }
            notes = calibrationClicks.map { Exercise.Note(time: $0, accent: false, beat: 0) }
            states = Array(repeating: .waiting, count: 8)
            plannedEnd = cEnd + 8 * 60 / startBPM
        } else {
            switch runSettings.kind {
            case .cycles: plannedEnd = nil
            case .duration: plannedEnd = cEnd + Double(runSettings.seconds)
            case .endurance: plannedEnd = nil
            }
        }

        let q = EventQueue()
        queue = q
        input.attach(to: player.audio)
        let params = EngineParams(bpm: startBPM, beatsPerBar: beats, subdivision: 1, accent: true,
                                  gridClicks: calibrating || gridClicks)
        do {
            try player.startPlayAlong(setup: { st, lead in
                origin = lead
                st.track = q
                var first = countEvents
                if calibrating {
                    first += calibrationClicks.enumerated().map { TimedEvent(time: $1, kind: $0 % beats == 0 ? .accent : .beat, beat: $0 % beats) }
                    first.append(TimedEvent(time: plannedEnd! + 0.05, kind: .done))
                    doneScheduling = true
                }
                q.append(first.map { frameEvent($0, sampleRate: st.sampleRate) })
            }, params: params)
        } catch {
            message = error.localizedDescription
            return
        }
        if !calibrating { scheduleAhead() }
        route = AudioEngine.routeDescription()
        phase = calibrating ? .calibrating : .running
        player.onFrame = { [weak self] in self?.frame() }
        player.onStopped = { [weak self] in
            guard let self, self.phase == .running || self.phase == .calibrating else { return }
            self.phase = self.score == nil ? .ready : .result
        }
    }

    private func frameEvent(_ e: TimedEvent, sampleRate: Double) -> ClickEvent {
        ClickEvent(frame: Int64((origin + e.time * sampleRate).rounded()), kind: e.kind, beat: e.beat)
    }

    /// Keeps at least 1.5 seconds of the run queued.
    private func scheduleAhead() {
        guard let q = queue else { return }
        let sr = player.audio.sampleRate
        while !doneScheduling && scheduledUntil < now + 1.5 {
            let k = slots.count
            let ex = runExercise
            var stop = false
            switch runSettings.kind {
            case .cycles: stop = k >= max(1, runSettings.cycles)
            case .duration: stop = scheduledUntil >= (plannedEnd ?? 0) - 1e-6
            case .endurance: stop = scheduledUntil - countInEnd >= SessionSettings.enduranceCap
            }
            if stop {
                doneScheduling = true
                plannedEnd = scheduledUntil
                q.append([frameEvent(TimedEvent(time: scheduledUntil + 0.05, kind: .done), sampleRate: sr)])
                break
            }
            let bpmNow = k == 0 ? currentBPM : RunBuilder.nextBPM(current: slots[k - 1].bpm, lastPassed: lastPassed,
                                                                  step: runSettings.ladderStep, maxBPM: ex.tempo.max)
            let limit = runSettings.kind == .duration ? plannedEnd : nil
            let slot = RunBuilder.cycle(ex, index: k, start: scheduledUntil, bpm: bpmNow, guided: runGuided, limit: limit)
            slots.append(slot)
            noteStart.append(notes.count)
            notes += slot.notes
            states += Array(repeating: .waiting, count: slot.notes.count)
            scheduledUntil = slot.end
            if slot.duration <= 1e-6 { doneScheduling = true; plannedEnd = scheduledUntil; break }
            q.append(slot.events.map { frameEvent($0, sampleRate: sr) })
        }
    }

    /// Host time (seconds) to plan time, before calibration.
    private func planTime(host: Double) -> Double {
        let a = player.audio
        let r = a.report.current
        let f = Double(r.anchorFrame) + (host - r.anchorHost) * a.sampleRate
        return (f - origin) / a.sampleRate
    }

    private var shift: Double { phase == .calibrating ? 0 : (offset ?? AudioEngine.reportedLatency) }

    private var window: Double {
        phase == .calibrating ? 0.25 : runExercise.window(bpm: slots.map(\.bpm).max() ?? currentBPM)
    }

    /// The slot playing now, if any.
    var currentSlot: CycleSlot? { slots.last { $0.start <= now } }

    /// The notes-per-beat cue: how many notes this beat has, and how many beats until that changes.
    var groupCue: (now: Int, next: Int, beatsUntil: Int)? {
        guard phase == .running, let s = currentSlot, now < s.end else { return nil }
        let sizes = RunBuilder.groupSizes(runExercise)
        guard sizes.count > 1, Set(sizes).count > 1 else { return nil }
        let beat = 60 / s.bpm
        let local = min(sizes.count - 1, max(0, Int((now - s.start) / beat)))
        var k = 1
        while k < sizes.count && sizes[(local + k) % sizes.count] == sizes[local] { k += 1 }
        return (sizes[local], sizes[(local + k) % sizes.count], k)
    }

    private func frame() {
        guard phase == .running || phase == .calibrating else { return }
        now = player.audio.planTime(origin: origin)
        level = input.level
        for o in input.drain() where o.time > 0 {
            played.append(Onset(time: planTime(host: o.time) - shift, strength: o.strength))
        }
        if phase == .running { scheduleAhead() }
        if let s = currentSlot { currentBPM = s.bpm }
        updateStates()
        if phase == .running { evaluateCycles(); speakCues() }
        guard phase == .running || phase == .calibrating else { return }
        if doneScheduling, let end = plannedEnd, now > end + 0.4 { finish(stoppedEarly: false) }
    }

    private func updateStates() {
        let w = window
        let m = Scoring.match(expected: notes.map(\.time), played: played.map(\.time), window: w)
        errors = m.enumerated().map { i, j in j.map { (played[$0].time - notes[i].time) * 1000 } }
        for i in notes.indices {
            if let e = errors[i] {
                let a = abs(e)
                states[i] = a <= runExercise.scoring.tightMs ? .tight : (a <= runExercise.scoring.closeMs ? .close : .loose)
            } else {
                states[i] = notes[i].time + w < now ? .missed : .waiting
            }
        }
    }

    private func evaluateCycles() {
        let w = window
        while accuracies.count < slots.count {
            let k = accuracies.count
            let s = slots[k]
            guard now > s.end + w + 0.05 else { break }
            let lo = noteStart[k], hi = k + 1 < noteStart.count ? noteStart[k + 1] : notes.count
            let acc = RunBuilder.accuracy(errors: errors[lo..<hi], toleranceMs: runSettings.toleranceMs)
            accuracies.append(acc)
            lastCycleAccuracy = acc
            let passed = acc * 100 >= Double(runSettings.targetPercent)
            lastPassed = passed
            if passed { topBPM = max(topBPM, Int(s.bpm)) }
            let counts = (0..<accuracies.count).map { i in (i + 1 < noteStart.count ? noteStart[i + 1] : notes.count) - noteStart[i] }
            let r = RunBuilder.rolling(accuracies, noteCounts: counts, window: runSettings.windowCycles)
            rolling = r ?? accuracies.last
            if runSettings.kind == .endurance {
                if let r {
                    if r * 100 >= Double(runSettings.targetPercent) { sustained = s.end - countInEnd } else { finish(stoppedEarly: false); return }
                } else if passed {
                    sustained = s.end - countInEnd
                }
            }
        }
    }

    private func finish(stoppedEarly: Bool) {
        let wasCalibrating = phase == .calibrating
        player.onFrame = nil
        player.stop()
        for o in input.finish() where o.time > 0 {
            played.append(Onset(time: planTime(host: o.time) - shift, strength: o.strength))
        }
        if wasCalibrating {
            if let o = Scoring.calibrate(clicks: calibrationClicks, played: played.map(\.time)) {
                offset = o
                message = "Calibrated: \(Int((o * 1000).rounded())) ms."
            } else {
                message = "Not enough notes heard. Play one note on each of the eight clicks."
            }
            phase = .ready
            return
        }
        // The notes that count: every cycle that was judged (endurance, or a run stopped early), or all of them.
        let judged = runSettings.kind == .endurance || stoppedEarly ? accuracies.count : slots.count
        let upto = judged < noteStart.count ? noteStart[judged] : notes.count
        let counted = Array(notes.prefix(upto))
        let r = Scoring.score(notes: counted, played: played, window: window, rule: runExercise.scoring)
        score = r
        let tol = runSettings.toleranceMs
        let within = r.errors.filter { e in e.map { abs($0) <= tol } ?? false }.count
        let playedSeconds = judged > 0 ? slots[min(judged, slots.count) - 1].end - countInEnd : 0
        let result = SessionResult(
            id: UUID(), date: Date(), exerciseID: runExercise.id, exerciseVersion: runExercise.version,
            exerciseName: runExercise.name, mode: runSettings.kind.rawValue, ladderStep: runSettings.ladderStep,
            guided: runGuided, startBPM: slots.first.map { Int($0.bpm) } ?? bpm, topBPM: topBPM,
            seconds: playedSeconds, cycles: judged, notes: r.expected, hits: r.hits, missed: r.missed, extra: r.extra,
            pct20: r.pct20, pct40: r.pct40, tightMs: runExercise.scoring.tightMs, closeMs: runExercise.scoring.closeMs,
            meanErrorMs: r.meanError, spreadMs: r.spread, toleranceMs: tol, targetPercent: runSettings.targetPercent,
            accuracyPercent: r.expected > 0 ? Int((100 * Double(within) / Double(r.expected)).rounded()) : 0,
            sustainedSeconds: runSettings.kind == .endurance ? sustained : nil, score: r.score,
            passed: runSettings.kind == .endurance ? sustained > 0 : r.passed,
            accentsPercent: r.accentBeats.flatMap { b in b > 0 ? Int((100 * Double(r.accentsLanded ?? 0) / Double(b)).rounded()) : nil },
            offsetMs: offset.map { $0 * 1000 },
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
        let previous = runGuided ? nil : Stats.best(history.results, exerciseID: result.exerciseID, mode: result.mode, bpm: result.startBPM)
        newBest = !runGuided && previous != nil && result.bestValue > previous!
        if r.expected > 0 { history.add(result) }
        saved = result
        phase = .result
    }
}
