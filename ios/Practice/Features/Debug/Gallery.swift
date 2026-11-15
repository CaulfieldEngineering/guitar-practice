#if DEBUG
import SwiftUI

/// Debug builds only, for the UI tests' screenshots: the screens that otherwise need a guitar and an interface (a
/// run going on, a result), drawn from made-up values. Opened with the launch argument `-screen <name>`.
struct Gallery: View {
    let screen: String

    var body: some View {
        Group {
            switch screen {
            case "run": RunView(d: Gallery.run(scored: true), onPause: {}, onResume: {}, onEnd: {})
            case "runUnscored": RunView(d: Gallery.run(scored: false), onPause: {}, onResume: {}, onEnd: {})
            case "runFretted": RunView(d: Gallery.runFretted(), onPause: {}, onResume: {}, onEnd: {})
            case "runPaused":
                RunView(d: Gallery.run(scored: true), paused: true, route: L.route("iRig HD 2", "OpenRun"), onPause: {}, onResume: {}, onEnd: {})
            case "result": result(endurance: false)
            case "resultEndurance": result(endurance: true)
            case "unscored":
                UnscoredResultView(run: PlayAlong.UnscoredRun(seconds: 184, startBPM: 120, topBPM: 132, cycles: 23), total: 1260,
                                   againTitle: L.again, onAgain: {}, onDone: {})
            default: Text("No such screen: \(screen)").foregroundStyle(Theme.text)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }

    /// A made-up left-hand line, to see real frets on real strings: four notes a beat up and down a box.
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
        let notes = fretted.notes(bpm: 100, start: 0, seconds: 9.6)
        d.notes = notes
        d.played = notes.filter { $0.time < d.now }.map { Onset(time: $0.time + 0.006, strength: 1) }
        d.states = notes.map { $0.time < d.now ? .tight : .waiting }
        d.cue = "Box"
        d.cueDetail = " "
        d.bpm = 100
        return d
    }

    static let drill = Exercise(id: "demo", name: "Triplets to sixteenths, 4 and 4", cycleBeats: 8,
                                notes: Exercise.expand(groups: [3, 3, 3, 3, 4, 4, 4, 4], accentFirst: false),
                                tempo: TempoRule(start: 128))

    /// Notes of two cycles at 128, and picks a little off each, the same every time.
    static func sample() -> (notes: [Exercise.Note], played: [Onset]) {
        let notes = drill.notes(bpm: 128, start: 0, seconds: 7.5)
        var played: [Onset] = []
        for (i, n) in notes.enumerated() {
            if i % 17 == 11 { continue }                                  // a missed note now and then
            let wobble = sin(Double(i) * 1.7) * 0.014 + (i % 9 == 4 ? 0.034 : 0.004)
            played.append(Onset(time: n.time + wobble, strength: 1))
        }
        return (notes, played)
    }

    static func run(scored: Bool) -> RunDisplay {
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
        return RunDisplay(
            chip: scored ? "Solo · Z3 Tempo · 85% of max" : "Guided · Z3 Tempo · 85% of max · Not scored",
            cue: "Sixteenths", cueDetail: "Triplets in 3", cueWarn: false, bpm: 128,
            scored: scored, accuracy: 91, accuracyGood: true, cycle: "3 of 8", clock: "1:12", clockLabel: scored ? L.held : L.left,
            countingIn: false, calibrating: false,
            notes: s.notes, played: scored ? s.played.filter { $0.time < now } : [], states: states, now: now, beat: 60.0 / 128,
            recentErrors: Array(errors.suffix(12)), spanMs: config.windows(gap: gaps.last ?? 0.1).zero, inputLevel: 0.2)
    }

    @ViewBuilder
    private func result(endurance: Bool) -> some View {
        let s = Gallery.sample()
        let r = Scoring.score(notes: s.notes, played: s.played, window: 0.05)
        let saved = SessionResult(
            id: UUID(), date: Date(), exerciseID: "demo", exerciseVersion: 1, exerciseName: Gallery.drill.name,
            mode: endurance ? "endurance" : "cycles", ladderStep: endurance ? 0 : 4, guided: false,
            startBPM: 128, topBPM: endurance ? 128 : 136,
            seconds: 96, cycles: 8, notes: r.expected, hits: r.hits, missed: r.missed, extra: r.extra,
            pct20: r.pct20, pct40: r.pct40, tightMs: 20, closeMs: 40, meanErrorMs: r.meanError, spreadMs: r.spread,
            toleranceMs: r.fullMs, targetPercent: 85, accuracyPercent: r.score, sustainedSeconds: endurance ? 96 : nil,
            score: r.score, passed: true, accentsPercent: nil, offsetMs: 12, appVersion: "0",
            scoringVersion: 2, fullMs: r.fullMs, zeroMs: r.zeroMs)
        ResultView(score: r, saved: saved, guided: false, newBest: !endurance, maxUp: endurance ? nil : (132, 136),
                   primaryTitle: L.again, primaryImage: "arrow.clockwise", onPrimary: {}, onDone: {})
    }
}
#endif
