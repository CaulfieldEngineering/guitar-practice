#if DEBUG
import SwiftUI

/// Debug builds only, for the UI tests' screenshots: the screens that otherwise need a guitar and an interface (a
/// run going on, a break, a Challenge, a result, a routine between blocks), drawn from made-up values. Opened with
/// the launch argument `-screen <name>`.
struct Gallery: View {
    let screen: String

    var body: some View {
        Group {
            switch screen {
            case "run": RunView(d: Gallery.run(scored: true), onPause: {}, onResume: {}, onEnd: {})
            case "runAccuracy": RunView(d: Gallery.run(scored: true, accuracyPlan: true), onPause: {}, onResume: {}, onEnd: {})
            case "runChallenge": RunView(d: Gallery.run(scored: true, challenge: true), onPause: {}, onResume: {}, onEnd: {})
            case "runUnscored": RunView(d: Gallery.run(scored: false), onPause: {}, onResume: {}, onEnd: {})
            case "runFretted": RunView(d: Gallery.runFretted(), onPause: {}, onResume: {}, onEnd: {})
            case "runPaused":
                RunView(d: Gallery.run(scored: true), paused: true, route: L.routeShort("MOMIX-CAB", "OpenRun Pro"), onPause: {}, onResume: {}, onEnd: {})
            case "break": BreakView(left: 18, length: 25, resumeBPM: 116, onSkip: {}, onStop: {})
            case "result": NavigationStack { result(mode: "cycles") }
            case "resultAscending": NavigationStack { result(mode: "ascending") }
            case "resultChallenge": NavigationStack { result(mode: "challenge") }
            case "unscored": UnscoredResultView(run: PlayAlong.UnscoredRun(seconds: 184, startBPM: 120, topBPM: 132, cycles: 23), total: 1260, onAgain: {})
            case "routineDone":
                ScrollView { RoutineRunSummary(record: Gallery.routineRecord).padding(.horizontal, Space.page) }
            default: Text("No such screen: \(screen)").foregroundStyle(Theme.text)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }

    /// A made-up left-hand line, to see real frets on real strings, one of them played on the wrong pitch.
    static let fretted: Exercise = {
        let shape: [(Int, Int)] = [(3, 5), (3, 7), (2, 5), (2, 7), (1, 5), (1, 8), (2, 7), (2, 5), (3, 7), (3, 5), (4, 7), (4, 5), (5, 7), (5, 5), (6, 8), (6, 5)]
        var notes: [NoteSpec] = []
        for (i, n) in shape.enumerated() {
            notes.append(NoteSpec(at: GridPosition(beat: i / 4, step: i % 4, of: 4), string: n.0, fret: n.1, pick: i % 2 == 0 ? .down : .up, accent: i % 4 == 0))
        }
        return Exercise(id: "demo-left", name: "Box", cycleBeats: 4, notes: notes, tempo: TempoRule(start: 100))
    }()

    static func runFretted() -> RunDisplay {
        var d = run(scored: true)
        var notes = fretted.notes(bpm: 100, start: 0, seconds: 9.6)
        for i in notes.indices { notes[i].pitch = Tuning.standard.pitch(string: notes[i].string, fret: notes[i].fret) }
        d.notes = notes
        d.played = notes.filter { $0.time < d.now }.map { Onset(time: $0.time + 0.006, strength: 1) }
        d.states = notes.enumerated().map { i, n in n.time < d.now ? (i == 5 ? .wrong : .tight) : .waiting }
        d.heard = [5: 66]
        d.cue = "Box"
        d.cueDetail = " "
        d.bpm = 100
        return d
    }

    static let drill = Exercise.fallback

    /// Notes of two loops at 128, and picks a little off each, the same every time.
    static func sample() -> (notes: [Exercise.Note], played: [Onset]) {
        let notes = drill.notes(bpm: 128, start: 0, seconds: 7.5)
        var played: [Onset] = []
        for (i, n) in notes.enumerated() {
            if i % 17 == 11 { continue }
            let wobble = sin(Double(i) * 1.7) * 0.014 + (i % 9 == 4 ? 0.034 : 0.004)
            played.append(Onset(time: n.time + wobble, strength: 1))
        }
        return (notes, played)
    }

    static func run(scored: Bool, accuracyPlan: Bool = false, challenge: Bool = false) -> RunDisplay {
        let s = sample()
        let now = 2.62
        let config = ScoringConfig.standard
        let gaps = Scoring.gaps(s.notes.map(\.time))
        let m = Scoring.match(expected: s.notes.map(\.time), played: s.played.map(\.time), window: 0.05)
        var states: [PlayAlong.NoteState] = []
        var errors: [Double] = []
        for (i, n) in s.notes.enumerated() {
            guard scored, n.time < now else { states.append(.waiting); continue }
            if let j = m[i] {
                let e = (s.played[j].time - n.time) * 1000
                let c = config.credit(errorMs: e, gap: gaps[i])
                states.append(c >= 0.999 ? .tight : (c >= 0.5 ? .close : .loose))
                errors.append(e)
            } else {
                states.append(.missed)
            }
        }
        var plan = TempoPlan()
        plan.mode = .accuracy
        plan.breakOn = true
        let step: PlayAlong.StepInfo? = accuracyPlan
            ? PlayAlong.StepInfo(state: .up, fraction: 0.625, measure: L.ofLoops(5, 8), target: 128, next: 132)
            : (challenge ? nil : PlayAlong.StepInfo(state: .perLoop, fraction: 0.5, measure: L.ofLoops(1, 2), target: 160, next: 132))
        return RunDisplay(
            title: drill.name, cue: "16ths", cueDetail: "Triplets in 3", cueWarn: false,
            bpm: 128, countingIn: false, beatsPerBar: 4, currentBeat: 2,
            step: step, scored: scored, accuracy: scored ? 0.92 : nil, zone: accuracyPlan ? .up : (scored ? .up : nil),
            lines: accuracyPlan ? [plan.breakPercent, plan.downPercent, plan.upPercent] : [85], zoned: accuracyPlan,
            notes: s.notes, played: scored ? s.played.filter { $0.time < now } : [], states: states, now: now,
            recentErrors: Array(errors.suffix(12)), spanMs: config.windows(gap: gaps.last ?? 0.1).zero,
            statusLeft: L.loopOf(5, 16), statusRight: L.leftClock("2:14"),
            challenge: challenge ? RunDisplay.ChallengeLine(earned: 134, target: 300, elapsed: 190, inZone: false, share: 0.7) : nil)
    }

    @ViewBuilder
    private func result(mode: String) -> some View {
        let s = Gallery.sample()
        let r = Scoring.score(notes: s.notes, played: s.played, window: 0.05)
        let ascending = mode == "ascending"
        let challenge = mode == "challenge"
        let saved = SessionResult(
            id: UUID(), date: Date(), exerciseID: "trip16x4", exerciseVersion: 1, exerciseName: Gallery.drill.name,
            mode: challenge ? "challenge" : "cycles", ladderStep: 0, guided: false,
            startBPM: 120, topBPM: ascending ? 136 : 120,
            seconds: 360, cycles: 24, notes: r.expected, hits: r.hits, missed: r.missed, extra: r.extra,
            pct20: r.pct20, pct40: r.pct40, tightMs: 20, closeMs: 40, meanErrorMs: r.meanError, spreadMs: r.spread,
            toleranceMs: r.fullMs, targetPercent: 90, accuracyPercent: r.score, sustainedSeconds: nil,
            score: r.score, passed: true, accentsPercent: nil, offsetMs: 12, appVersion: "0",
            scoringVersion: 2, fullMs: r.fullMs, zeroMs: r.zeroMs,
            tempoMode: ascending ? "accuracy" : nil, breaks: ascending ? 1 : nil,
            earnedSeconds: challenge ? 300 : nil, elapsedSeconds: challenge ? 372 : nil, bestStreakSeconds: challenge ? 148 : nil,
            tempoSteps: ascending ? [TempoStep(bpm: 120, seconds: 96, accuracy: 93), TempoStep(bpm: 124, seconds: 72, accuracy: 91),
                                     TempoStep(bpm: 128, seconds: 64, accuracy: 74), TempoStep(bpm: 128, seconds: 25, accuracy: nil, rest: true),
                                     TempoStep(bpm: 124, seconds: 80, accuracy: 92)] : nil)
        ResultView(score: r, saved: saved, guided: false, maxUp: ascending ? (132, 136) : nil,
                   primaryTitle: L.again, primaryImage: "arrow.clockwise", onPrimary: {})
            .navigationTitle(Gallery.drill.short)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.done) {}.accessibilityIdentifier("result.done") } }
    }

    static let routineRecord = RoutineRunRecord(
        id: UUID(), date: Date(), routineID: "x", routineName: "Picking session", seconds: 1450, completed: true,
        blocks: [.init(kind: "warmup", name: "Warm-up", seconds: 180),
                 .init(kind: "drill", name: "Triplets to 16ths, 4+4", seconds: 300, accuracy: 91, startBPM: 90, topBPM: 120),
                 .init(kind: "rest", name: "Break", seconds: 60),
                 .init(kind: "drill", name: "Challenge", seconds: 236, accuracy: 93, startBPM: 100, topBPM: 100),
                 .init(kind: "free", name: "Open practice", seconds: 0, skipped: true)],
        device: "iPhone", appVersion: "0.3.0")
}
#endif
