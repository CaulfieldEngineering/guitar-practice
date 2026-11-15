import AVFoundation
import SwiftUI

/// The play-along: the guitar comes in through a NoteInput (the audio input today), and every note is scored against
/// the one the exercise asks for. Guided plays the exercise as a muted pluck with the click; Solo is the click only.
/// A run is scheduled a cycle at a time, so endurance can stop when the accuracy drops and the ladder can speed up
/// after a passed cycle.
///
/// Audio input (Joe, 2026-11-14: "Just some kind of toggle for 'audio input', if it's selected, it'll be scored"):
/// on, the interface is opened, the run is analysed, saved and counted. Off, the input is never opened (no
/// permission asked, Bluetooth headphones stay in their listening mode), nothing is scored or counted, and only the
/// minutes played are kept (UnscoredLog).
@MainActor
final class PlayAlong: ObservableObject {
    /// `syncing` and `calibrating` are the two steps of the calibration: sight against sound, then the guitar.
    /// `paused` is a run held still: the sound is off and the clock stopped, until it is resumed or ended.
    enum Phase: Equatable { case ready, intro, syncing, calibrating, running, paused, result }
    enum NoteState { case waiting, tight, close, loose, missed }

    /// A run with the audio input off: how long, and at what tempo. Never part of the scores or his max.
    struct UnscoredRun: Equatable {
        var seconds: Double
        var startBPM: Int
        var topBPM: Int
        var cycles: Int
    }

    let player: Player
    let history: History
    let input: NoteInput

    @Published private(set) var exercises: [Exercise] = []
    @Published private(set) var catalogNote: String?
    @Published var exerciseID: String { didSet { UserDefaults.standard.set(exerciseID, forKey: "pa.exercise"); loadSettings(); message = nil } }
    /// Set with setBPM (kept in the drill's range); never assigned inside its own didSet (that recursed, 0.1.4).
    @Published private(set) var bpm: Int
    @Published var session: SessionSettings { didSet { saveSettings() } }
    /// Guided or solo, and the spoken intro: remembered per drill.
    @Published var guided: Bool { didSet { saveSettings() } }
    @Published var intro: Bool { didSet { saveSettings() } }
    /// Tempo by zone of his max (default once there is a max) or by hand; per drill.
    @Published var resume: Bool { didSet { saveSettings() } }
    /// The zone picked on this drill, or "" for the one the kind of run suggests.
    @Published var zoneChoice: String { didSet { saveSettings() } }
    /// Audio input on: the run is scored. Off: the input stays closed and nothing is scored. Per drill.
    @Published var audioInput: Bool { didSet { saveSettings(); if !loading { message = nil } } }
    @Published private(set) var zones: TempoZones = .standard
    /// How timing becomes accuracy: the catalog's numbers, or the local default.
    @Published private(set) var scoring: ScoringConfig = .standard
    /// The zone and max of the run going on, for the run screen.
    @Published private(set) var runZoneMax: Int?
    /// Levels from the server, kept for when it is out of reach.
    @Published private(set) var serverLevels: [String: Int] = [:]
    /// After a run: the level before and after, when it went up.
    @Published private(set) var levelUp: (from: Int, to: Int)?
    @Published var gridClicks: Bool { didSet { UserDefaults.standard.set(gridClicks, forKey: "pa.click") } }
    /// Testing only, off unless switched on in Settings: the phone's microphone instead of the interface.
    @Published var allowPhoneMic: Bool { didSet { UserDefaults.standard.set(allowPhoneMic, forKey: "pa.allowMic"); player.audio.allowPhoneMic = allowPhoneMic; routeChanged() } }
    /// Whether an interface is plugged in (its input is available).
    @Published private(set) var interfacePresent = false
    /// This route's calibration (Engine/Latency.swift), if it has one.
    @Published private(set) var calibration: Calibration?
    /// The route changed during a run, or this route has never been calibrated.
    @Published private(set) var routeNote: String?
    /// One line when iOS has sent the sound to the interface that was plugged in (it takes the output along with the
    /// input unless another output is picked): where the sound went, and what to do about it.
    @Published private(set) var outputNote: String?
    /// Sight against sound on this output, in seconds: the lane is drawn this much later (DisplayOffsetStore).
    @Published private(set) var displayOffset: Double = 0

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var now: Double = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var score: ScoreResult?
    @Published private(set) var saved: SessionResult?
    @Published private(set) var lastRunWasGuided = false
    /// Whether the run going on (or just ended) had the audio input on.
    @Published private(set) var lastRunWasScored = true
    /// After a run with the audio input off.
    @Published private(set) var unscored: UnscoredRun?
    /// Seconds played with the audio input off, per drill. Kept apart from the scores.
    @Published private(set) var unscoredSeconds: [String: Double] = [:]
    @Published private(set) var newBest = false
    @Published private(set) var message: String?
    @Published private(set) var route = Latency.currentRoute()
    @Published private(set) var rolling: Double?          // endurance: accuracy over the last cycles
    @Published private(set) var lastCycleAccuracy: Double?
    @Published private(set) var currentBPM: Double = 0
    @Published private(set) var sustained: Double = 0

    private(set) var notes: [Exercise.Note] = []
    private(set) var played: [Onset] = []       // plan time, calibration applied
    private(set) var states: [NoteState] = []
    private(set) var countInEnd: Double = 0
    private(set) var plannedEnd: Double?        // nil for endurance until it stops
    /// Each note's timing error in ms (positive is late); nil while it has not been played.
    private(set) var errors: [Double?] = []
    private var gaps: [Double] = []             // each note's gap to its nearest neighbour, seconds
    private var usedPlayed = Set<Int>()         // played notes matched to a note of the drill
    private var slots: [CycleSlot] = []
    private var noteStart: [Int] = []           // first note index of each slot
    private var accuracies: [Double] = []
    private var lastPassed: Bool?
    private var topBPM = 0
    private var scheduledUntil: Double = 0
    private var doneScheduling = false
    private var runGuided = false
    private var runScored = true
    private var runSettings = SessionSettings()
    private var runExercise: Exercise = .fallback
    private var origin: Double = 0
    private var queue: EventQueue?
    private var calibrationClicks: [Double] = []
    /// A drill of timed blocks: its blocks on a timeline that starts at the end of the count-in, the one being
    /// scheduled, and the block each slot belongs to.
    private var blocks: [Segment] = []
    private var blockIndex = 0
    private var slotBlock: [Int] = []
    private var barCounter = 0
    /// The count-in's clicks, kept for a resume before the first note; and when the count-in in force ends (the
    /// first one, or the bar played again after a pause).
    private var introEvents: [TimedEvent] = []
    private(set) var countInUntil: Double = 0
    private var pausedAt: Double = 0
    /// The catalog's drills, the catalog's starter routines, and the routines saved on the phone.
    private var catalogExercises: [Exercise] = []
    private var starterRoutines: [Routine] = []
    private var ownRoutines: [Routine] = []

    var exercise: Exercise { exercises.first { $0.id == exerciseID } ?? exercises.first ?? .fallback }

    init(player: Player, history: History, input: NoteInput = AudioOnsetInput()) {
        self.player = player
        self.history = history
        self.input = input
        let d = UserDefaults.standard
        let loaded = Library.load()
        let lib = loaded.exercises
        exercises = lib
        catalogExercises = lib
        starterRoutines = loaded.routines
        let id = d.string(forKey: "pa.exercise").flatMap { s in lib.contains { $0.id == s } ? s : nil } ?? lib[0].id
        exerciseID = id
        let ex = lib.first { $0.id == id } ?? lib[0]
        bpm = d.object(forKey: "pa.bpm.\(id)") as? Int ?? ex.tempo.start
        session = PlayAlong.storedSession(id) ?? ex.session
        // A drill of timed blocks starts out as the routine it was: the click only, and nothing scored.
        guided = d.object(forKey: "pa.guided.\(id)") as? Bool ?? !ex.isRoutine
        intro = d.object(forKey: "pa.intro.\(id)") as? Bool ?? true
        resume = d.object(forKey: "pa.resume.\(id)") as? Bool ?? !ex.isRoutine
        zoneChoice = d.string(forKey: "pa.zone.\(id)") ?? ""
        audioInput = d.object(forKey: "pa.input.\(id)") as? Bool ?? !ex.isRoutine
        zones = loaded.zones ?? .standard
        scoring = loaded.scoring ?? .standard
        serverLevels = d.dictionary(forKey: "pa.levels") as? [String: Int] ?? [:]
        unscoredSeconds = UnscoredLog.all()
        gridClicks = d.object(forKey: "pa.click") as? Bool ?? true
        allowPhoneMic = d.object(forKey: "pa.allowMic") as? Bool ?? false
        player.audio.allowPhoneMic = allowPhoneMic
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.routeChanged() }
        }
        routeChanged()
    }

    // MARK: Settings per exercise

    private static func storedSession(_ id: String) -> SessionSettings? {
        UserDefaults.standard.data(forKey: "pa.session.\(id)").flatMap { try? JSONDecoder().decode(SessionSettings.self, from: $0) }
    }

    private var loading = false
    private func loadSettings() {
        loading = true
        let d = UserDefaults.standard
        bpm = d.object(forKey: "pa.bpm.\(exerciseID)") as? Int ?? exercise.tempo.start
        session = PlayAlong.storedSession(exerciseID) ?? exercise.session
        let plain = !exercise.isRoutine
        guided = d.object(forKey: "pa.guided.\(exerciseID)") as? Bool ?? plain
        intro = d.object(forKey: "pa.intro.\(exerciseID)") as? Bool ?? true
        resume = d.object(forKey: "pa.resume.\(exerciseID)") as? Bool ?? plain
        zoneChoice = d.string(forKey: "pa.zone.\(exerciseID)") ?? ""
        audioInput = d.object(forKey: "pa.input.\(exerciseID)") as? Bool ?? plain
        loading = false
    }

    private func saveSettings() {
        guard !loading else { return }
        UserDefaults.standard.set(bpm, forKey: "pa.bpm.\(exerciseID)")
        UserDefaults.standard.set(guided, forKey: "pa.guided.\(exerciseID)")
        UserDefaults.standard.set(intro, forKey: "pa.intro.\(exerciseID)")
        UserDefaults.standard.set(resume, forKey: "pa.resume.\(exerciseID)")
        UserDefaults.standard.set(zoneChoice, forKey: "pa.zone.\(exerciseID)")
        UserDefaults.standard.set(audioInput, forKey: "pa.input.\(exerciseID)")
        if let d = try? JSONEncoder().encode(session) { UserDefaults.standard.set(d, forKey: "pa.session.\(exerciseID)") }
    }

    /// The zone in use: the one picked, else the one this kind of run suggests.
    var activeZone: TempoZones.Zone? {
        (zoneChoice.isEmpty ? nil : zones.zone(zoneChoice)) ?? zones.suggested(for: session)
    }

    /// "Z3 Tempo · 80–90% of max 150 → 120–135 bpm"
    var zoneLine: String? {
        guard let max = level(), let z = activeZone else { return nil }
        let r = TempoZones.range(z, max: max)
        return "\(z.name) \(z.title) · \(Int(z.low))–\(Int(z.high))% of max \(max) → \(r.lowerBound)–\(r.upperBound) bpm"
    }

    /// His max on a drill: the server's when it has been reached, else worked out from the phone's own runs.
    func level(_ id: String? = nil) -> Int? {
        let key = id ?? exerciseID
        let local = Stats.learnedTempo(history.results, exerciseID: key, step: exercise.tempo.stepOnPass)
        return serverLevels[key] ?? local
    }

    /// The tempo a run starts at: his level when resuming and there is one, else the tempo set by hand.
    var startTempo: Int {
        if resume, let m = level(), let z = activeZone {
            return min(max(zones.start(z, max: m), exercise.tempo.min), exercise.tempo.max)
        }
        return bpm
    }

    func refreshLevels() async {
        if let l = await DrillServer.fetchLevels() {
            serverLevels = l
            UserDefaults.standard.set(l, forKey: "pa.levels")
        }
    }

    func setBPM(_ value: Int) {
        let t = exercise.tempo
        let v = min(max(value, t.min), t.max)
        guard v != bpm else { return }
        bpm = v
        saveSettings()
    }

    /// The tempo by hand, starting from wherever the tempo is now (a zone's, or the one set before).
    func nudgeTempo(to value: Int) {
        if resume { resume = false }
        setBPM(value)
    }

    /// Picks a zone of his max; the tempo follows it.
    func chooseZone(_ id: String) {
        if zoneChoice != id { zoneChoice = id }
        if !resume { resume = true }
    }

    /// Opens a drill: its remembered tempo, run, guide and intro.
    func select(_ id: String) {
        guard id != exerciseID else { return }
        exerciseID = id
    }

    /// A level of the drill: its tempo (by hand, so it is the one that plays) and, if it says so, its kind of run.
    func apply(_ level: Level) {
        if resume { resume = false }
        setBPM(level.bpm)
        if let s = level.session { session = s }
    }

    // MARK: Catalog

    /// Pulls the drill catalog from the mini PC (when reachable), reloads, and sends any unsent results.
    func refresh() async {
        let r = await DrillServer.pullCatalog()
        switch r {
        case .updated: catalogNote = L.drillsUpdated
        case .upToDate: catalogNote = nil
        case .unreachable: catalogNote = L.drillsOffline
        case .invalid: catalogNote = L.drillsUnreadable
        }
        let lib = Library.load()
        catalogExercises = lib.exercises
        starterRoutines = lib.routines
        zones = lib.zones ?? .standard
        scoring = lib.scoring ?? .standard
        rebuildExercises()
        await history.sync()
        await refreshLevels()
    }

    // MARK: Routines as drills

    /// Dormant in 0.1.7 (Joe, 2026-11-14: "Let's omit the timed routines for now and just focus on the drills
    /// themselves. We'll build in routines later"): nothing calls this, no drill in the catalog has timed blocks, and
    /// the Drills list leaves any that did out. Kept, untried on a phone, as the groundwork for bringing them back.
    /// The routines saved on the phone (RoutineStore), shown as drills of timed blocks. One that is still exactly a
    /// starter is not shown twice: the catalog's drill of that name stands for it. One he changed is shown as his,
    /// and the catalog's drill of that name steps aside. Nothing in the store is ever changed from here.
    func setOwnRoutines(_ list: [Routine]) {
        guard list != ownRoutines else { return }
        ownRoutines = list
        rebuildExercises()
    }

    private func rebuildExercises() {
        let catalogNames = Set(catalogExercises.filter(\.isRoutine).map(\.name))
        let own = ownRoutines.filter { r in
            !(catalogNames.contains(r.name) && starterRoutines.contains { $0.sameContent(as: r) })
        }
        let ownNames = Set(own.map(\.name))
        var list = catalogExercises.filter { !($0.isRoutine && ownNames.contains($0.name)) }
        list += own.map { Exercise(routine: $0) }
        if list.isEmpty { list = [.fallback] }
        if list != exercises { exercises = list }
        if phase == .ready, !exercises.contains(where: { $0.id == exerciseID }) { exerciseID = exercises[0].id }
    }

    /// The routine on the phone behind a drill, if it is one of his own.
    func ownRoutine(_ exerciseID: String) -> Routine? {
        ownRoutines.first { Exercise.routineID($0.id) == exerciseID }
    }

    /// After one of his routines is edited: its rounds and step are the edited ones again.
    func forgetRun(for exerciseID: String) {
        UserDefaults.standard.removeObject(forKey: "pa.session.\(exerciseID)")
        UserDefaults.standard.removeObject(forKey: "pa.bpm.\(exerciseID)")
        if exerciseID == self.exerciseID, phase == .ready { loadSettings() }
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
    func clearResult() { score = nil; saved = nil; unscored = nil; phase = .ready }

    func stop() {
        if phase == .intro { player.voice.stop(); phase = .ready; return }
        if phase == .syncing { endSync(); return }
        if phase == .running || phase == .paused { endRun(); return }
        guard phase == .calibrating else { return }
        player.stop()
        phase = .ready
    }

    // MARK: Pause, resume, end

    /// Holds the run still: the sound stops and so does the clock. Cycles already judged are kept.
    func pause() {
        guard phase == .running else { return }
        pausedAt = now
        player.onFrame = nil
        player.onStopped = nil
        player.stop()
        if runScored { _ = input.finish() }
        level = 0
        phase = .paused
    }

    /// Picks the run up again. In the middle of a pattern it goes back to the start of that cycle, behind a bar of
    /// count-in, and the notes of that cycle are played again from clean; in a rest or a block with no click it
    /// carries on from the moment it was paused. The plan's clock is the same one, so everything already judged
    /// stands and the rest of the run is as it was going to be.
    func resumeRun() {
        guard phase == .paused else { return }
        message = nil
        if runScored && !inputReady(calibrating: false) { return }
        let beats = max(1, runExercise.beatsPerBar)
        var from = pausedAt
        var floor = pausedAt
        var lead: [TimedEvent] = []
        if pausedAt < countInEnd {
            from = 0
            floor = 0
            lead = introEvents
            countInUntil = countInEnd
        } else if let s = slots.last(where: { $0.start <= pausedAt }), pausedAt < s.end, !s.notes.isEmpty {
            let beat = 60 / max(1, s.bpm)
            from = s.start - Double(beats) * beat
            floor = s.start
            lead = (0..<beats).map { TimedEvent(time: from + Double($0) * beat, kind: .countIn, beat: $0) }
            played.removeAll { $0.time >= s.start - 0.02 }
            countInUntil = s.start
        }
        var events = lead
        for s in slots { events += s.events.filter { $0.time >= floor - 1e-6 } }
        if doneScheduling { events.append(TimedEvent(time: (plannedEnd ?? scheduledUntil) + 0.05, kind: .done)) }
        let q = EventQueue()
        queue = q
        if runScored { input.attach(to: player.audio) }
        let params = EngineParams(bpm: currentBPM, beatsPerBar: beats, subdivision: 1, accent: true, gridClicks: gridClicks)
        do {
            try player.startPlayAlong(record: runScored, setup: { st, leadIn in
                origin = leadIn - from * st.sampleRate
                st.track = q
                q.append(events.map { frameEvent($0, sampleRate: st.sampleRate) })
            }, params: params)
        } catch {
            message = error.localizedDescription
            return
        }
        now = from
        routeChanged()
        runRouteKey = route.key
        phase = .running
        watchPlayer()
    }

    /// Ends the run where it is: a scored one keeps the cycles already judged; one with the input off keeps its minutes.
    func endRun() {
        guard phase == .running || phase == .paused else { return }
        if !runScored { finishUnscored(); return }
        if !accuracies.isEmpty { finish(stoppedEarly: true); return }
        player.onFrame = nil
        player.onStopped = nil
        player.stop()
        phase = .ready
    }

    private func watchPlayer() {
        player.onFrame = { [weak self] in self?.frame() }
        player.onStopped = { [weak self] in
            guard let self, self.phase == .running || self.phase == .calibrating else { return }
            let route = Latency.currentRoute()
            if route.key != self.runRouteKey { self.message = L.routeChanged(route.name) }
            if self.phase == .running {
                // The sound was taken away under a run (headphones or an interface plugged in or picked, a call,
                // the metronome): the run is held, not lost. Resume picks it up on the new route.
                self.pausedAt = self.now
                self.player.onFrame = nil
                self.player.onStopped = nil
                if self.runScored { _ = self.input.finish() }
                self.level = 0
                self.phase = .paused
            } else {
                self.phase = .ready
            }
            self.routeChanged()
        }
    }

    /// Opens the way for the guitar: the record session, an interface, the permission. False (with a message, or
    /// after asking for the permission) when the run cannot start yet. Never called with the audio input off.
    private func inputReady(calibrating: Bool) -> Bool {
        AudioEngine.prepareRecordSession()
        routeChanged()
        if !interfacePresent && !allowPhoneMic {
            message = L.connectInterface
            return false
        }
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            AVAudioApplication.requestRecordPermission { ok in
                Task { @MainActor in
                    if ok { self.begin(calibrating: calibrating) } else { self.message = L.allowMicrophone }
                }
            }
            return false
        default:
            message = L.allowMicrophone
            return false
        }
    }

    private func begin(calibrating: Bool) {
        message = nil
        let scored = audioInput || calibrating
        if scored && !inputReady(calibrating: calibrating) { return }
        if !calibrating && intro {
            phase = .intro
            let words = IntroText.exercise(exercise, bpm: startTempo, session: session, guided: guided, scored: scored)
            player.voice.speak(words, always: true) { [weak self] in
                guard let self, self.phase == .intro else { return }
                self.launch(calibrating: false)
            }
            return
        }
        launch(calibrating: calibrating)
    }

    func skipIntro() { player.voice.skip() }

    // MARK: Calibration, step 1: sight against sound

    /// How many marks the second step plays: one note on each.
    static let calibrationCount = 12

    /// Moves the lane against the sound on this output (kept per output; the picture only, never the scoring).
    func setDisplayOffset(_ seconds: Double) {
        let r = DisplayOffsetStore.range
        let v = min(r.upperBound, max(r.lowerBound, seconds))
        guard v != displayOffset else { return }
        displayOffset = v
        DisplayOffsetStore.set(v, for: Latency.outputKey(route.key))
    }

    /// The lane's clock: plan time, moved by the display offset, so a note crosses the line when it is heard.
    var laneNow: Double { now - displayOffset }

    /// Starts the calibration at its first step: a steady click, and marks that cross a line in the middle of the
    /// screen. The audio input stays closed; the slider on the screen moves the marks against the sound.
    func startCalibration() {
        guard phase == .ready else { return }
        message = nil
        runExercise = exercise
        runSettings = session
        runGuided = false
        runScored = false
        lastRunWasGuided = false
        lastRunWasScored = false
        runZoneMax = nil
        let tempo = 80.0
        currentBPM = tempo
        slots = []; noteStart = []; played = []; errors = []; gaps = []; usedPlayed = []
        accuracies = []; lastPassed = nil; rolling = nil; lastCycleAccuracy = nil; sustained = 0
        score = nil; saved = nil; unscored = nil; newBest = false
        level = 0
        countInEnd = 0
        let beat = 60 / tempo
        let times = (0..<400).map { 0.6 + Double($0) * beat }       // five minutes of clicks
        notes = times.map { Exercise.Note(time: $0, accent: false, beat: 0) }
        states = Array(repeating: .waiting, count: times.count)
        let end = (times.last ?? 0) + beat
        plannedEnd = end
        doneScheduling = true
        let q = EventQueue()
        queue = q
        let params = EngineParams(bpm: tempo, beatsPerBar: 4, subdivision: 1, accent: true, gridClicks: true)
        do {
            try player.startPlayAlong(record: false, setup: { st, lead in
                origin = lead
                st.track = q
                var events = times.enumerated().map { TimedEvent(time: $1, kind: $0 % 4 == 0 ? .accent : .beat, beat: $0 % 4) }
                events.append(TimedEvent(time: end + 0.05, kind: .done))
                q.append(events.map { frameEvent($0, sampleRate: st.sampleRate) })
            }, params: params)
        } catch {
            message = error.localizedDescription
            return
        }
        routeChanged()
        runRouteKey = route.key
        now = 0
        phase = .syncing
        player.onFrame = { [weak self] in self?.frame() }
        player.onStopped = { [weak self] in
            guard let self, self.phase == .syncing else { return }
            self.phase = .ready
        }
    }

    private func endSync() {
        player.onFrame = nil
        player.onStopped = nil
        player.stop()
        phase = .ready
    }

    /// On to the second step: the guitar, with the audio input open.
    func calibrateInput() {
        if phase == .syncing { endSync() }
        calibrate()
    }

    func repeatIntro() {
        player.voice.speak(IntroText.exercise(exercise, bpm: startTempo, session: session, guided: guided, scored: audioInput), always: true)
    }

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
        runScored = audioInput || calibrating
        lastRunWasGuided = runGuided
        lastRunWasScored = runScored
        var startBPM = Double(calibrating ? 80 : startTempo)
        levelUp = nil
        runZoneMax = calibrating ? nil : level()
        // A drill of timed blocks: its blocks on a timeline, every play block moved by as much as the tempo was.
        blocks = []; blockIndex = 0; slotBlock = []; barCounter = 0
        if !calibrating && runSettings.kind == .routine {
            var r = runExercise.routine
            r.rounds = max(1, runSettings.cycles)
            r.stepBPM = runSettings.ladderStep
            r.countInBeats = 0
            let shift = Int(startBPM) - runExercise.tempo.start
            for i in r.intervals.indices where r.intervals[i].kind == .play { r.intervals[i].bpm += shift }
            blocks = RoutinePlan(r).segments
            if let first = blocks.first(where: { $0.kind == .play }) { startBPM = first.bpm }
        }
        // No count-in before a block with no click.
        let countsIn = blocks.first.map { $0.kind == .play } ?? true
        now = 0
        currentBPM = startBPM
        topBPM = Int(startBPM)
        slots = []; noteStart = []; notes = []; states = []; played = []; errors = []; gaps = []; usedPlayed = []
        // With the audio input off nothing is judged, so the ladder climbs after every cycle.
        accuracies = []; lastPassed = runScored ? nil : true; rolling = nil; lastCycleAccuracy = nil; sustained = 0
        score = nil; saved = nil; unscored = nil; newBest = false
        level = 0
        doneScheduling = false
        plannedEnd = nil
        let beats = runExercise.beatsPerBar
        let counted = RunBuilder.countIn(beats: countsIn ? beats : 0, bpm: startBPM)
        let countEvents = counted.events
        let cEnd = counted.end
        countInEnd = cEnd
        countInUntil = cEnd
        introEvents = countEvents
        scheduledUntil = cEnd
        if calibrating {
            let count = PlayAlong.calibrationCount
            calibrationClicks = (0..<count).map { cEnd + Double($0) * 60 / startBPM }
            notes = calibrationClicks.map { Exercise.Note(time: $0, accent: false, beat: 0) }
            states = Array(repeating: .waiting, count: count)
            gaps = Scoring.gaps(calibrationClicks)
            plannedEnd = cEnd + Double(count) * 60 / startBPM
        } else {
            switch runSettings.kind {
            case .cycles: plannedEnd = nil
            case .duration: plannedEnd = cEnd + Double(runSettings.seconds)
            case .endurance: plannedEnd = nil
            case .routine: plannedEnd = cEnd + (blocks.last?.end ?? 0)
            }
        }

        let q = EventQueue()
        queue = q
        if runScored { input.attach(to: player.audio) }
        let params = EngineParams(bpm: startBPM, beatsPerBar: beats, subdivision: 1, accent: true,
                                  gridClicks: calibrating || gridClicks)
        do {
            try player.startPlayAlong(record: runScored, setup: { st, lead in
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
            phase = .ready
            return
        }
        if !calibrating { scheduleAhead() }
        routeChanged()
        runRouteKey = route.key
        phase = calibrating ? .calibrating : .running
        watchPlayer()
    }

    private func frameEvent(_ e: TimedEvent, sampleRate: Double) -> ClickEvent {
        ClickEvent(frame: Int64((origin + e.time * sampleRate).rounded()), kind: e.kind, beat: e.beat)
    }

    /// Keeps at least 1.5 seconds of the run queued.
    private func scheduleAhead() {
        guard let q = queue else { return }
        let sr = player.audio.sampleRate
        var added = false
        while !doneScheduling && scheduledUntil < now + 1.5 {
            let k = slots.count
            let ex = runExercise
            var stop = false
            switch runSettings.kind {
            case .cycles: stop = k >= max(1, runSettings.cycles)
            case .duration: stop = scheduledUntil >= (plannedEnd ?? 0) - 1e-6
            case .endurance: stop = scheduledUntil - countInEnd >= SessionSettings.enduranceCap
            case .routine: stop = blockIndex >= blocks.count
            }
            if stop {
                doneScheduling = true
                plannedEnd = scheduledUntil
                q.append([frameEvent(TimedEvent(time: scheduledUntil + 0.05, kind: .done), sampleRate: sr)])
                break
            }
            let slot: CycleSlot
            if runSettings.kind == .routine {
                guard let made = nextBlockSlot(k) else { continue }
                slot = made
            } else {
                let bpmNow = k == 0 ? currentBPM : RunBuilder.nextBPM(current: slots[k - 1].bpm, lastPassed: lastPassed,
                                                                      step: runSettings.ladderStep, maxBPM: ex.tempo.max)
                let limit = runSettings.kind == .duration ? plannedEnd : nil
                slot = RunBuilder.cycle(ex, index: k, start: scheduledUntil, bpm: bpmNow, guided: runGuided, limit: limit)
            }
            slots.append(slot)
            noteStart.append(notes.count)
            notes += slot.notes
            states += Array(repeating: .waiting, count: slot.notes.count)
            added = true
            scheduledUntil = slot.end
            if slot.duration <= 1e-6 { doneScheduling = true; plannedEnd = scheduledUntil; break }
            q.append(slot.events.map { frameEvent($0, sampleRate: sr) })
        }
        if added { gaps = Scoring.gaps(notes.map(\.time)) }
    }

    /// The next slot of a drill of timed blocks, as slot `k`: one cycle of the pattern in a play block (a bell on
    /// the block's first beat), or a whole rest or block with no click (a lower bell, and before a play block the
    /// last bar counted in at its tempo). Nil when the block had nothing left to schedule; the next one is up.
    private func nextBlockSlot(_ k: Int) -> CycleSlot? {
        let ex = runExercise
        let b = blocks[blockIndex]
        let bStart = countInEnd + b.start
        let bEnd = countInEnd + b.end
        if b.kind == .play {
            let first = scheduledUntil <= bStart + 1e-6
            if first { barCounter = 0 }
            if bEnd - scheduledUntil <= 1e-6 { blockIndex += 1; return nil }
            let block = blockIndex
            var s = RunBuilder.cycle(ex, index: barCounter, start: max(scheduledUntil, bStart), bpm: b.bpm, guided: runGuided, limit: bEnd,
                                     subdivision: runGuided ? 1 : ex.subdivision)
            barCounter += 1
            s.index = k
            if first, let i = s.events.firstIndex(where: { ($0.kind == .accent || $0.kind == .beat) && $0.time <= bStart + 1e-6 }) {
                s.events[i].kind = .change
            }
            if s.end >= bEnd - 1e-6 { blockIndex += 1 }
            slotBlock.append(block)
            return s
        }
        var events = [TimedEvent(time: bStart, kind: .rest)]
        var tempo = currentBPM
        if blockIndex + 1 < blocks.count, blocks[blockIndex + 1].kind == .play {
            let next = blocks[blockIndex + 1].bpm
            tempo = next
            let n = max(1, ex.beatsPerBar)
            if b.kind == .rest, b.duration >= Double(n) * 60 / next + 1.0 {
                for i in 0..<n { events.append(TimedEvent(time: bEnd - Double(n - i) * 60 / next, kind: .countIn, beat: i)) }
            }
        }
        slotBlock.append(blockIndex)
        blockIndex += 1
        return CycleSlot(index: k, start: bStart, duration: b.duration, bpm: tempo, notes: [], events: events)
    }

    /// The block of a drill of timed blocks that is playing now: what it is, how long is left in it, the round, and
    /// what comes next.
    struct BlockNow {
        var title: String
        var kind: Segment.Kind
        var left: Double
        var round: Int
        var rounds: Int
        var next: String?
    }

    var blockNow: BlockNow? {
        guard runSettings.kind == .routine, !blocks.isEmpty else { return nil }
        let t = now - countInEnd
        let i = blocks.lastIndex(where: { $0.start <= t }) ?? 0
        let b = blocks[i]
        var next: String?
        if i + 1 < blocks.count {
            let n = blocks[i + 1]
            next = n.title + ", " + formatClock(n.duration) + (n.kind == .play ? " at \(Int(n.bpm))" : "")
        }
        return BlockNow(title: b.title, kind: b.kind, left: max(0, b.end - max(0, t)), round: b.round + 1,
                        rounds: (blocks.last?.round ?? 0) + 1, next: next)
    }

    /// Whether a count-in is playing: the first one, or the bar before the notes come back after a pause.
    var countingIn: Bool { now < countInUntil }

    /// Leaving the drill's screen ends whatever is going on there: the click, the guide, the voice, the input and the
    /// timer all stop (Joe, 0.1.6: "Drills keep running when I leave the drill"). A scored run keeps what was
    /// already judged; it is saved, and the screen is left ready for next time.
    func leave() {
        switch phase {
        case .intro, .syncing, .calibrating: stop()
        case .running, .paused: endRun()
        case .ready, .result: break
        }
        player.voice.stop()
        if phase == .result { clearResult() }
        if player.mode == .playAlong { player.stop() }
    }

    /// Host time (seconds) to plan time, before calibration.
    private func planTime(host: Double) -> Double {
        let a = player.audio
        let r = a.report.current
        let f = Double(r.anchorFrame) + (host - r.anchorHost) * a.sampleRate
        return (f - origin) / a.sampleRate
    }

    /// The offset in use now: today's estimate for this route plus its calibration.
    var currentOffset: Double { Latency.offset(estimate: Latency.currentEstimate(), calibration: calibration) }

    /// While calibrating, picks are moved by the estimate only, so the 250 ms match window is around the real delay
    /// even on Bluetooth; what is left is the residual.
    private var shift: Double { phase == .calibrating ? Latency.currentEstimate() : currentOffset }
    private var runRouteKey = ""

    /// Re-reads the route: picks up its calibration, and warns about hands-free Bluetooth or an uncalibrated route.
    /// A route change in the middle of a run stops it (the engine restarts on the new route), and says why.
    func routeChanged() {
        let r = Latency.currentRoute()
        let changed = r.key != route.key
        route = r
        calibration = CalibrationStore.get(r.key)
        interfacePresent = AudioEngine.interfaceInput() != nil
        let onInterface = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .usbAudio }
        let note = onInterface ? L.outputOnInterface : nil
        if note != outputNote { outputNote = note }
        let shown = DisplayOffsetStore.get(Latency.outputKey(r.key))
        if shown != displayOffset { displayOffset = shown }
        if !interfacePresent && !allowPhoneMic {
            routeNote = L.connectInterface
        } else if r.handsFree {
            routeNote = L.callMode
        } else if calibration == nil {
            routeNote = L.newAudioSetup
        } else {
            routeNote = nil
        }
        if changed && (phase == .running || phase == .calibrating) && r.key != runRouteKey {
            message = L.routeChanged(r.name)
        }
    }

    private var window: Double {
        phase == .calibrating ? 0.25 : runExercise.window(bpm: slots.map(\.bpm).max() ?? currentBPM)
    }

    /// The slot playing now, if any.
    var currentSlot: CycleSlot? { slots.last { $0.start <= now } }

    /// The cycle playing now, counted from one.
    var cycleNumber: Int? { currentSlot.map { $0.index + 1 } }
    /// The kind of run going on, how many cycles it was set to, and the accuracy it holds itself to.
    var runKind: SessionSettings.Kind { runSettings.kind }
    var runCycles: Int { runSettings.cycles }
    var runTarget: Int { runSettings.targetPercent }

    /// The timing errors (ms, positive is late) of the latest notes that were played, newest last.
    var recentErrors: [Double] {
        var out: [Double] = []
        var i = min(errors.count, notes.count) - 1
        while i >= 0 && out.count < 12 {
            if notes[i].time <= now + 0.2, let e = errors[i] { out.append(e) }
            i -= 1
        }
        return out.reversed()
    }

    /// How far off a note can be before it earns nothing, in ms, at the spacing being played now.
    var timingSpanMs: Double { scoring.windows(gap: gaps.last ?? 0.25).zero }

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
        guard phase == .running || phase == .calibrating || phase == .syncing else { return }
        now = player.audio.planTime(origin: origin)
        if phase == .syncing {
            if let end = plannedEnd, now > end + 0.4 { endSync() }
            return
        }
        if runScored {
            level = input.level
            for o in input.drain() where o.time > 0 {
                played.append(Onset(time: planTime(host: o.time) - shift, strength: o.strength))
            }
        }
        if phase == .running { scheduleAhead() }
        if let s = currentSlot {
            currentBPM = s.bpm
            if !runScored { topBPM = max(topBPM, Int(s.bpm)) }
        }
        if runScored {
            updateStates()
            if phase == .running { evaluateCycles() }
        }
        if phase == .running { speakCues() }
        guard phase == .running || phase == .calibrating else { return }
        if doneScheduling, let end = plannedEnd, now > end + 0.4 {
            if runScored { finish(stoppedEarly: false) } else { finishUnscored() }
        }
    }

    private func updateStates() {
        let w = window
        let m = Scoring.match(expected: notes.map(\.time), played: played.map(\.time), window: w)
        usedPlayed = Set(m.compactMap { $0 })
        errors = m.enumerated().map { i, j in j.map { (played[$0].time - notes[i].time) * 1000 } }
        for i in notes.indices {
            if let e = errors[i] {
                let c = scoring.credit(errorMs: e, gap: i < gaps.count ? gaps[i] : 1)
                states[i] = c >= 0.999 ? .tight : (c >= 0.5 ? .close : .loose)
            } else {
                states[i] = notes[i].time + w < now ? .missed : .waiting
            }
        }
    }

    /// One past the last note of slot `i`.
    private func noteEnd(_ i: Int) -> Int {
        if i + 1 < noteStart.count { return noteStart[i + 1] }
        return notes.count
    }

    private func evaluateCycles() {
        let w = window
        while accuracies.count < slots.count {
            let k = accuracies.count
            let s = slots[k]
            guard now > s.end + w + 0.05 else { break }
            let lo = noteStart[k]
            let hi = noteEnd(k)
            guard hi <= errors.count, hi <= gaps.count else { break }
            // A rest, or a block with no click: nothing to judge.
            if hi == lo { accuracies.append(1); continue }
            let timed = runSettings.kind == .routine
            // Extra notes in this cycle: played, matched to nothing.
            var extras = 0
            for (j, o) in played.enumerated() where !usedPlayed.contains(j) && o.time >= s.start - w / 2 && o.time < s.end - w / 2 {
                extras += 1
            }
            let acc = Scoring.accuracy(errors: errors[lo..<hi], gaps: gaps[lo..<hi], extras: extras, config: scoring)
            accuracies.append(acc)
            lastCycleAccuracy = acc
            let passed = acc * 100 >= Double(runSettings.targetPercent)
            lastPassed = passed
            // In timed blocks a cycle is a beat or two, too short to say a tempo was reached: the blocks are judged
            // whole when the run ends (blockTopBPM).
            if passed && !timed { topBPM = max(topBPM, Int(s.bpm)) }
            var counts: [Int] = []
            for i in 0..<accuracies.count { counts.append(noteEnd(i) - noteStart[i]) }
            let r = RunBuilder.rolling(accuracies, noteCounts: counts, window: timed ? 8 : runSettings.windowCycles)
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

    /// The end of a run with the audio input off: nothing is scored or saved; the minutes are kept.
    private func finishUnscored() {
        player.onFrame = nil
        player.onStopped = nil
        player.stop()
        let end = min(now, plannedEnd ?? now)
        let seconds = max(0, end - countInEnd)
        guard seconds >= 1 else { phase = .ready; return }
        let done = runSettings.kind == .routine ? 0 : slots.filter { $0.end <= now + 0.05 }.count
        let first = slots.first.map { Int($0.bpm) } ?? bpm
        unscored = UnscoredRun(seconds: seconds, startBPM: first, topBPM: max(topBPM, first), cycles: done)
        UnscoredLog.add(seconds, to: runExercise.id)
        unscoredSeconds = UnscoredLog.all()
        score = nil
        saved = nil
        phase = .result
    }

    /// The fastest play block whose notes, taken together, reached the target: what a run of timed blocks says about
    /// the tempo he reached.
    private func blockTopBPM(judged: Int) -> Int? {
        var credit: [Int: Double] = [:], count: [Int: Double] = [:]
        for k in 0..<min(judged, accuracies.count, slotBlock.count, noteStart.count) {
            let n = Double(noteEnd(k) - noteStart[k])
            guard n > 0 else { continue }
            credit[slotBlock[k], default: 0] += accuracies[k] * n
            count[slotBlock[k], default: 0] += n
        }
        var best: Int?
        for (i, n) in count where n > 0 && i < blocks.count {
            if (credit[i] ?? 0) / n * 100 >= Double(runSettings.targetPercent) { best = max(best ?? 0, Int(blocks[i].bpm)) }
        }
        return best
    }

    private func finish(stoppedEarly: Bool) {
        let wasCalibrating = phase == .calibrating
        let wasPaused = phase == .paused
        let runShift = shift
        player.onFrame = nil
        player.onStopped = nil
        player.stop()
        // Paused: the input was closed and emptied when the run was held.
        if !wasPaused {
            for o in input.finish() where o.time > 0 {
                played.append(Onset(time: planTime(host: o.time) - runShift, strength: o.strength))
            }
        }
        if wasCalibrating {
            if let found = Scoring.calibration(clicks: calibrationClicks, played: played.map(\.time)) {
                let measured = Latency.currentEstimate() + found.offset
                let spreadMs = found.spread * 1000
                let c = Calibration(residual: found.offset, measured: measured, routeName: route.name, date: Date(),
                                    spreadMs: spreadMs, hits: found.hits)
                CalibrationStore.set(c, for: route.key)
                calibration = c
                routeChanged()
                message = L.calibrated(ms: Int((measured * 1000).rounded()), notes: found.hits, spread: Int(spreadMs.rounded()))
            } else {
                message = L.calibrationTooFew
            }
            phase = .ready
            return
        }
        // The notes that count: every cycle that was judged (endurance, or a run stopped early), or all of them.
        let judged = runSettings.kind == .endurance || stoppedEarly ? accuracies.count : slots.count
        let upto = judged < noteStart.count ? noteStart[judged] : notes.count
        let counted = Array(notes.prefix(upto))
        let w = window
        var heard = played
        if runSettings.kind == .routine {
            // Only what was played during the play blocks counts: a pick in a rest is not an extra note.
            let playing = slots.prefix(judged).filter { !$0.notes.isEmpty }
            heard = played.filter { o in playing.contains { o.time >= $0.start - w && o.time < $0.end + w } }
            if counted.isEmpty {
                // Blocks with no click only: there was nothing to score, so it ends as a run that is not scored.
                finishUnscored()
                return
            }
            if let top = blockTopBPM(judged: judged) { topBPM = max(topBPM, top) }
        }
        let r = Scoring.score(notes: counted, played: heard, window: w, rule: runExercise.scoring, config: scoring)
        score = r
        var playedSeconds = 0.0
        if judged > 0 { playedSeconds = slots[min(judged, slots.count) - 1].end - countInEnd }
        let startBPM: Int = slots.first.map { Int($0.bpm) } ?? bpm
        var accentsPercent: Int?
        if let b = r.accentBeats, b > 0 {
            let landed = Double(r.accentsLanded ?? 0)
            accentsPercent = Int((100 * landed / Double(b)).rounded())
        }
        let isEndurance = runSettings.kind == .endurance
        let held: Double? = isEndurance ? sustained : nil
        let passed: Bool = isEndurance ? sustained > 0 : r.passed
        let offsetMs: Double? = currentOffset * 1000
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let result = SessionResult(
            id: UUID(), date: Date(), exerciseID: runExercise.id, exerciseVersion: runExercise.version,
            exerciseName: runExercise.name, mode: runSettings.kind.rawValue, ladderStep: runSettings.ladderStep,
            guided: runGuided, startBPM: startBPM, topBPM: topBPM,
            seconds: playedSeconds, cycles: judged, notes: r.expected, hits: r.hits, missed: r.missed, extra: r.extra,
            pct20: r.pct20, pct40: r.pct40, tightMs: runExercise.scoring.tightMs, closeMs: runExercise.scoring.closeMs,
            meanErrorMs: r.meanError, spreadMs: r.spread, toleranceMs: r.fullMs, targetPercent: runSettings.targetPercent,
            accuracyPercent: r.score, sustainedSeconds: held, score: r.score, passed: passed,
            accentsPercent: accentsPercent, offsetMs: offsetMs, appVersion: appVersion,
            scoringVersion: 2, fullMs: r.fullMs, zeroMs: r.zeroMs)
        newBest = false
        if !runGuided, let previous = Stats.best(history.results, exerciseID: result.exerciseID, mode: result.mode, bpm: result.startBPM) {
            newBest = result.bestValue > previous
        }
        let levelBefore = level(result.exerciseID)
        if r.expected > 0 { history.add(result) }
        if let after = level(result.exerciseID), after > (levelBefore ?? 0), !runGuided {
            levelUp = (levelBefore ?? 0, after)
        }
        Task { await history.sync(); await refreshLevels() }
        saved = result
        phase = .result
    }

    #if DEBUG
    /// For the screenshots in the UI tests: a max on every drill, so the zones show.
    func seedMaxForScreenshots(_ max: Int = 150) {
        var l = serverLevels
        for e in exercises { l[e.id] = max }
        serverLevels = l
    }
    #endif
}

/// Minutes played with the audio input off, per drill, kept on the phone. Not a score, never sent with the runs,
/// and never part of his max or his accuracy.
enum UnscoredLog {
    private static let key = "pa.unscoredSeconds"

    static func all() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    static func add(_ seconds: Double, to exerciseID: String) {
        guard seconds > 0 else { return }
        var a = all()
        a[exerciseID, default: 0] += seconds
        UserDefaults.standard.set(a, forKey: key)
    }
}
