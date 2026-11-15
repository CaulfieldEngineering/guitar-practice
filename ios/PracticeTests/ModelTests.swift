import AVFoundation
import XCTest
@testable import Practice

/// What crashed 0.1.4 on the phone (setting the tempo recursed inside its own didSet) and the zones.
@MainActor
final class ModelTests: XCTestCase {
    func testMetronomeTempoChangesAndClamps() {
        let p = Player()
        let start = p.bpm
        p.setBPM(start + 1)
        XCTAssertEqual(p.bpm, start + 1)
        p.setBPM(10_000)
        XCTAssertEqual(p.bpm, Routine.bpmRange.upperBound)
        p.setBPM(-5)
        XCTAssertEqual(p.bpm, Routine.bpmRange.lowerBound)
        p.setBPM(start)
    }

    func testChoosingEveryExerciseAndLevelDoesNotCrash() {
        let pa = PlayAlong(player: Player(), history: History(inMemory: true))
        XCTAssertFalse(pa.exercises.isEmpty)
        for ex in pa.exercises {
            pa.select(ex.id)
            XCTAssertEqual(pa.exercise.id, ex.id)
            XCTAssertTrue((ex.tempo.min...ex.tempo.max).contains(pa.bpm))
            pa.setBPM(pa.bpm + 2)
            for lv in ex.levels { pa.apply(lv) }
            pa.guided.toggle()
            pa.session.kind = .endurance
            pa.session.cycles += 1
            pa.intro.toggle()
            pa.resume.toggle()
        }
        // Remembered per drill.
        let first = pa.exercises[0].id, second = pa.exercises[1].id
        pa.select(first); pa.guided = false; pa.setBPM(97)
        pa.select(second); pa.guided = true
        pa.select(first)
        XCTAssertFalse(pa.guided)
        XCTAssertEqual(pa.bpm, 97)
    }

    func testStartWithoutAnInterfaceSaysSoAndDoesNotCrash() {
        let pa = PlayAlong(player: Player(), history: History(inMemory: true))
        pa.allowPhoneMic = false
        pa.start()
        if !pa.interfacePresent {
            XCTAssertEqual(pa.phase, .ready)
            XCTAssertEqual(pa.message, L.connectInterface)
        }
    }

    /// Audio input off: no interface is asked for, the input is never opened, and nothing is saved.
    func testAudioInputOffNeverOpensTheInput() {
        let history = History(inMemory: true)
        let pa = PlayAlong(player: Player(), history: history)
        pa.allowPhoneMic = false
        let first = pa.exercises[0].id, second = pa.exercises[1].id
        pa.select(first)
        pa.intro = false
        pa.audioInput = false
        pa.start()
        XCTAssertNotEqual(pa.message, L.connectInterface)
        if pa.phase == .running {
            XCTAssertFalse(pa.player.audio.recording)
            XCTAssertEqual(AVAudioSession.sharedInstance().category, .playback)
            XCTAssertFalse(pa.lastRunWasScored)
        }
        pa.stop()
        XCTAssertNil(pa.saved)
        XCTAssertNil(pa.score)
        XCTAssertTrue(history.results.isEmpty)
        pa.clearResult()
        // Remembered per drill.
        pa.select(second); pa.audioInput = true
        pa.select(first)
        XCTAssertFalse(pa.audioInput)
        pa.audioInput = true
        pa.intro = true
    }

    /// A run can be held and picked up; leaving the drill ends it; and the app has one player, so starting the
    /// metronome ends a drill too. Nothing is left making sound (Joe, on 0.1.6: "Drills keep running when I leave").
    func testPauseResumeLeaveAndOnePlayer() {
        let player = Player()
        let pa = PlayAlong(player: player, history: History(inMemory: true))
        pa.select("trip16x4")
        pa.intro = false
        pa.audioInput = false
        pa.start()
        if pa.phase == .running {
            XCTAssertEqual(player.mode, .playAlong)
            pa.pause()
            XCTAssertEqual(pa.phase, .paused)
            XCTAssertEqual(player.mode, .idle)
            XCTAssertFalse(player.audio.isRunning, "paused: the engine is off")
            pa.resumeRun()
            XCTAssertEqual(pa.phase, .running)
            XCTAssertTrue(player.audio.isRunning)
            XCTAssertFalse(player.audio.recording, "the input stays closed")
            pa.pause()
            pa.leave()
            XCTAssertEqual(pa.phase, .ready)
            XCTAssertFalse(player.audio.isRunning, "left while paused: still off")

            pa.start()
            XCTAssertEqual(pa.phase, .running)
            pa.leave()
            XCTAssertEqual(pa.phase, .ready)
            XCTAssertEqual(player.mode, .idle)
            XCTAssertFalse(player.audio.isRunning, "left while running: the engine is off")

            pa.start()
            player.startMetronome()
            XCTAssertEqual(pa.phase, .paused, "the metronome took over, and the drill is held")
            XCTAssertEqual(player.mode, .metronome)
            player.stop()
            XCTAssertFalse(player.audio.isRunning)
        }
        pa.leave()
        XCTAssertEqual(pa.phase, .ready)
        pa.audioInput = true
        pa.intro = true
    }

    /// The intro is short and plain: the name and the pattern, the tempo, the goal. Nothing about how to play.
    func testIntroIsShortAndEveryPartIsRecorded() throws {
        let pa = PlayAlong(player: Player(), history: History(inMemory: true))
        let ex = try XCTUnwrap(pa.exercises.first { $0.id == "trip16x4" })
        var s = SessionSettings()
        s.kind = .cycles
        s.cycles = 8
        XCTAssertEqual(IntroText.exercise(ex, bpm: 120, session: s), "Triplets to sixteenths. Four and four. 120. 8 cycles.")
        s.kind = .duration
        s.seconds = 90
        XCTAssertEqual(IntroText.parts(ex, bpm: 96, session: s).map(\.key), ["say.trip16x4", "bpm.96", "time.90"])
        s.kind = .endurance
        XCTAssertEqual(IntroText.parts(ex, bpm: 96, session: s, scored: true).last?.text, "Endurance.")
        XCTAssertEqual(IntroText.parts(ex, bpm: 96, session: s, scored: false).last?.text, "Open.")
        // The app carries the recorded voice, and it says these words.
        let clips = VoiceClips.shared
        XCTAssertGreaterThanOrEqual(clips.version, 1)
        for drill in pa.exercises {
            s.kind = .cycles
            s.cycles = 4
            for part in IntroText.parts(drill, bpm: drill.tempo.start, session: s) {
                XCTAssertNotNil(clips.clip(part.key, text: part.text), "\(part.key) is recorded as \"\(part.text)\"")
            }
            XCTAssertFalse(drill.say.isEmpty, "\(drill.id) has a spoken line")
        }
        XCTAssertNotNil(clips.clip(IntroText.cue(group: 3).key, text: IntroText.cue(group: 3).text))
        XCTAssertNil(clips.clip("say.trip16x4", text: "Different words."), "a clip is not used for other words")
        let data = try XCTUnwrap(clips.clip("bpm.120", text: "120."))
        XCTAssertNoThrow(try AVAudioPlayer(data: data), "a clip is audio the phone can play")
    }

    /// The guide guitar: recorded notes for every pitch a drill can ask for, and the engine plays them.
    func testGuideGuitar() throws {
        let bank = try XCTUnwrap(GuitarBank.shared, "the recorded notes are in the app")
        XCTAssertEqual(bank.ptrs.count, GuitarBank.pitches.count * 4)
        XCTAssertEqual(bank.sampleRate, 24000)
        XCTAssertEqual(GuitarBank.pitch(string: nil, fret: nil), 55)
        XCTAssertEqual(GuitarBank.pitch(string: 6, fret: 0), 40)
        XCTAssertEqual(GuitarBank.pitch(string: 1, fret: 12), 76)
        let open = bank.lookup(pitch: 55, accent: false, up: false)
        XCTAssertEqual(open.step, 1, accuracy: 1e-12)
        XCTAssertEqual(bank.lookup(pitch: 55, accent: true, up: true).sample, open.sample + 3)
        let sharp = bank.lookup(pitch: 56, accent: false, up: false)
        XCTAssertEqual(sharp.sample, open.sample)
        XCTAssertEqual(sharp.step, pow(2, 1.0 / 12), accuracy: 1e-12)
        // A guided cycle carries the pitch and the stroke of every note.
        let ex = Exercise(id: "t", name: "t", cycleBeats: 1, notes: Exercise.expand(groups: [2], accentFirst: false), tempo: TempoRule(start: 100))
        let plucks = RunBuilder.cycle(ex, index: 0, start: 0, bpm: 120, guided: true).events.filter { $0.kind == .pluck }
        XCTAssertEqual(plucks.map(\.pitch), [55, 55])
        XCTAssertEqual(plucks.map(\.up), [false, true])
        // The engine renders a recorded note: sound comes out, and it ends.
        let state = RenderState(sampleRate: 48000, params: Locked(EngineParams()), report: Locked(EngineReport()))
        let queue = EventQueue()
        queue.append([ClickEvent(frame: 10, kind: .pluck, beat: -1, sample: open.sample, step: open.step)])
        state.track = queue
        let frames = 4096
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { buffer.deallocate() }
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: buffer))
        var stamp = AudioTimeStamp()
        var loudest: Float = 0
        var quietAtEnd = false
        for block in 0..<12 {
            state.render(frames, &stamp, &list)
            let peak = (0..<frames).map { abs(buffer[$0]) }.max() ?? 0
            loudest = max(loudest, peak)
            if block == 11 { quietAtEnd = peak == 0 }
        }
        XCTAssertGreaterThan(loudest, 0.1, "the note sounds")
        XCTAssertLessThanOrEqual(loudest, 1)
        XCTAssertTrue(quietAtEnd, "and it ends")
    }

    func testPatternGlyphsAndShortNames() throws {
        let pa = PlayAlong(player: Player(), history: History(inMemory: true))
        func glyph(_ id: String) -> String? { pa.exercises.first { $0.id == id }?.glyph }
        XCTAssertEqual(glyph("trip16x4"), "3→4")
        XCTAssertEqual(glyph("alt8"), "8")
        XCTAssertEqual(glyph("alt3"), "3")
        XCTAssertEqual(glyph("alt16"), "16")
        XCTAssertEqual(glyph("burst"), "16·rest")
        XCTAssertEqual(glyph("gallop"), "mix")
        let alt = try XCTUnwrap(pa.exercises.first { $0.id == "alt16" })
        XCTAssertEqual(alt.short, "Alternate 16ths")
        XCTAssertEqual(alt.category, "Picking")
        XCTAssertFalse(pa.exercises.contains { $0.isRoutine }, "no drill of timed blocks in 0.1.7")
    }

    /// The groundwork for bringing the timed routines back as drills: the data reads, and nothing else changes.
    func testTimedBlocksRead() throws {
        let json = """
        {"schema": 1, "exercises": [
          {"id": "ladder", "name": "Speed ladder", "rounds": 8, "stepBPM": 4, "subdivision": 4,
           "segments": [{"kind": "play", "seconds": 60, "bpm": 100}, {"kind": "rest", "seconds": 30}]},
          {"id": "plain", "name": "Plain", "groups": [4], "tempo": {"start": 90}}
        ]}
        """
        let list = try Library.decodeExercises(Data(json.utf8))
        XCTAssertEqual(list.count, 2)
        XCTAssertTrue(list[0].isRoutine)
        XCTAssertEqual(list[0].tempo.start, 100)
        XCTAssertEqual(list[0].session.kind, .routine)
        XCTAssertEqual(list[0].session.cycles, 8)
        XCTAssertEqual(list[0].notes.count, 4)
        XCTAssertEqual(list[0].routine.plan.total, 8 * 90 + 4 * 0.6, accuracy: 1e-9, "eight rounds of 90 seconds behind four beats of count-in at 100")
        XCTAssertFalse(list[1].isRoutine)
        XCTAssertEqual(list[1].session.kind, .cycles)
        let slot = RunBuilder.cycle(list[0], index: 0, start: 0, bpm: 120, guided: false, subdivision: 4)
        XCTAssertEqual(slot.events.filter { $0.kind == .sub }.count, 3)
    }

    /// Changing the tempo by hand leaves the zones; picking a zone comes back to them. Neither loops.
    func testTempoByHandAndByZone() {
        let pa = PlayAlong(player: Player(), history: History(inMemory: true))
        pa.select(pa.exercises[0].id)
        pa.chooseZone("z4")
        XCTAssertTrue(pa.resume)
        XCTAssertEqual(pa.zoneChoice, "z4")
        pa.nudgeTempo(to: 10_000)
        XCTAssertFalse(pa.resume)
        XCTAssertEqual(pa.bpm, pa.exercise.tempo.max)
        XCTAssertEqual(pa.startTempo, pa.exercise.tempo.max)
        pa.nudgeTempo(to: -3)
        XCTAssertEqual(pa.bpm, pa.exercise.tempo.min)
        pa.chooseZone("z2")
        XCTAssertTrue(pa.resume)
    }

    func testZones() {
        let z = TempoZones.standard
        let z3 = z.zone("z3")!
        XCTAssertEqual(TempoZones.range(z3, max: 150), 120...135)
        XCTAssertEqual(z.start(z3, max: 150), 128)
        var s = SessionSettings()
        s.kind = .endurance
        XCTAssertEqual(z.suggested(for: s)?.id, "z2")
        s.kind = .cycles; s.ladderStep = 4
        XCTAssertEqual(z.suggested(for: s)?.id, "z4")
        XCTAssertEqual(z.zone(forBPM: 132, max: 150)?.id, "z3")
        XCTAssertEqual(z.zone(forBPM: 156, max: 150)?.id, "z5")
        XCTAssertEqual(z.zone(forBPM: 80, max: 150)?.id, "z1")
    }

    func testBundledZonesDecode() throws {
        let c = try XCTUnwrap(Library.read(folder: XCTUnwrap(Library.bundledFolder)))
        XCTAssertEqual(c.zones?.zones.count, 5)
        XCTAssertEqual(c.zones?.suggest["endurance"], "z2")
    }

    func testLearnedMaxIsTheSecondBestRecentPass() {
        func r(_ day: Int, _ top: Int, passed: Bool, guided: Bool = false) -> SessionResult {
            SessionResult(id: UUID(), date: Date(timeIntervalSince1970: Double(day) * 86_400), exerciseID: "x", exerciseVersion: 1,
                          exerciseName: "x", mode: "cycles", ladderStep: 0, guided: guided, startBPM: top, topBPM: top,
                          seconds: 30, cycles: 4, notes: 10, hits: 10, missed: 0, extra: 0, pct20: 0, pct40: 0, tightMs: 20,
                          closeMs: 40, meanErrorMs: 0, spreadMs: 0, toleranceMs: 30, targetPercent: 85, accuracyPercent: 90,
                          sustainedSeconds: nil, score: passed ? 90 : 50, passed: passed, accentsPercent: nil, offsetMs: nil,
                          appVersion: "0")
        }
        XCTAssertNil(Stats.learnedTempo([r(1, 100, passed: false)], exerciseID: "x"))
        XCTAssertEqual(Stats.learnedTempo([r(1, 120, passed: true)], exerciseID: "x"), 116)
        var list = [r(1, 140, passed: true)]                                      // old, outside the last ten
        list += (0..<9).map { r(2 + $0, 100 + $0, passed: $0 % 2 == 0) }
        list.append(r(20, 130, passed: true))                                    // one lucky run
        list.append(r(21, 150, passed: true, guided: true))                      // guided: not counted
        XCTAssertEqual(Stats.learnedTempo(list, exerciseID: "x"), 108)
    }
}
