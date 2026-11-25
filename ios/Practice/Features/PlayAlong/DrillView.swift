import SwiftUI

/// One drill. Ready: its setup, with Start at the bottom. Then the intro, the run (with its pause and the breaks the
/// accuracy calls for), and the result. Leaving the screen ends whatever is going on in it (Joe, 0.1.6: "Drills keep
/// running when I leave the drill").
struct DrillView: View {
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var player: Player

    private var live: Bool { ([.running, .paused, .resting] as [PlayAlong.Phase]).contains(pa.phase) }
    private var busy: Bool { live || pa.phase == .intro }

    var body: some View {
        Group {
            switch pa.phase {
            case .ready, .syncing, .calibrating: DrillSetupView()
            case .intro: IntroView()
            case .running, .paused:
                RunView(d: RunDisplay.from(pa, beat: player.currentBeat), paused: pa.phase == .paused, message: pa.message,
                        route: L.routeShort(pa.route.input, pa.route.output),
                        onPause: { pa.pause() }, onResume: { pa.resumeRun() }, onEnd: { pa.endRun() })
            case .resting:
                BreakView(left: pa.breakLeft, length: pa.breakLength, resumeBPM: pa.resumeBPM,
                          onSkip: { pa.endBreak() }, onStop: { pa.endRun() })
            case .result: result
            }
        }
        .background((pa.phase == .ready ? Theme.side : Theme.bg).ignoresSafeArea())
        .navigationTitle(pa.exercise.short.isEmpty ? pa.exercise.name : pa.exercise.short)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(busy || pa.phase == .result)
        .toolbar(live ? .hidden : .visible, for: .navigationBar)
        .toolbar(busy ? .hidden : .visible, for: .tabBar)
        .toolbar {
            if pa.phase == .ready {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { pa.repeatIntro() } label: { Image(systemName: "speaker.wave.2") }
                        .accessibilityLabel(L.hearIntro)
                }
            }
            if pa.phase == .result {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.done) { pa.clearResult() }.accessibilityIdentifier("result.done")
                }
            }
        }
        // The calibration is over everything, from wherever it was started (the drill's Options or Settings).
        .fullScreenCover(isPresented: Binding(get: { pa.phase == .syncing || pa.phase == .calibrating }, set: { if !$0 { pa.stop() } })) {
            CalibrationView().routeNotice()
        }
        .onDisappear { if pa.phase != .syncing && pa.phase != .calibrating { pa.leave() } }
    }

    @ViewBuilder
    private var result: some View {
        if let r = pa.score, let s = pa.saved {
            ResultView(score: r, saved: s, guided: pa.lastRunWasGuided, maxUp: pa.levelUp.map { ($0.from, $0.to) },
                       primaryTitle: pa.lastRunWasGuided ? L.playSolo : L.again,
                       primaryImage: pa.lastRunWasGuided ? "play.fill" : "arrow.clockwise",
                       onPrimary: { if pa.lastRunWasGuided { pa.nowSolo() } else { pa.start() } })
        } else if let u = pa.unscored {
            UnscoredResultView(run: u, total: pa.unscoredSeconds[pa.exercise.id] ?? u.seconds, onAgain: { pa.start() })
        } else {
            VStack(alignment: .leading) {
                Text(L.noNotes).font(Typo.body).foregroundStyle(Theme.muted).padding(Space.page)
                Spacer()
            }
        }
    }
}

/// The spoken intro: the tempo big and the drill's line, with Skip and Stop.
struct IntroView: View {
    @EnvironmentObject var pa: PlayAlong
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Spacer()
            Text(L.introLine(guided: pa.guided, scored: pa.audioInput)).font(Typo.sub).foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: Space.tiny) {
                Text("\(pa.startTempo)").font(Typo.tempoHero).foregroundStyle(Theme.text)
                Text(L.bpm).font(Typo.body).foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: Space.sm) {
                QuietButton(title: L.stop, systemImage: "stop.fill") { pa.stop() }
                    .frame(width: 120)
                    .accessibilityIdentifier("intro.stop")
                PrimaryButton(title: L.skip, systemImage: "forward.fill") { pa.skipIntro() }
                    .accessibilityIdentifier("intro.skip")
            }
            .padding(.bottom, Space.sm)
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.bg)
    }
}

extension RunDisplay {
    /// The run screen's values from the play-along now.
    @MainActor
    static func from(_ pa: PlayAlong, beat: Int) -> RunDisplay {
        let counting = pa.countingIn
        let ex = pa.runExerciseNow
        let s = pa.runSettingsNow
        let plan = pa.runPlan
        var cue = ex.short.isEmpty ? ex.name : ex.short
        var detail = " "
        var warn = false
        if counting {
            cue = L.countInWord
        } else if let c = pa.groupCue {
            cue = L.groupName(c.now)
            detail = c.beatsUntil == 1 ? L.nextBeat(L.groupName(c.next)) : L.inBeats(L.groupName(c.next), c.beatsUntil)
            warn = c.beatsUntil == 1
        }
        let n = pa.cycleNumber
        var left = ""
        if !counting, let n {
            left = s.kind == .cycles ? L.loopOf(n, max(1, s.cycles)) : L.loopN(n)
        }
        var right = ""
        if let end = pa.plannedEnd { right = L.leftClock(formatClock(max(0, end - pa.now))) }
        else { right = formatClock(max(0, pa.now - pa.countInEnd)) }
        var challenge: RunDisplay.ChallengeLine?
        if let c = pa.challenge {
            challenge = RunDisplay.ChallengeLine(earned: c.earned, target: c.target, elapsed: c.elapsed, inZone: c.inZone || c.elapsed == 0, share: c.share)
        }
        return RunDisplay(
            title: pa.runSetup == nil ? ex.name : (ex.short.isEmpty ? ex.name : ex.short),
            cue: cue, cueDetail: detail, cueWarn: warn,
            bpm: Int(pa.currentBPM), countingIn: counting, beatsPerBar: ex.beatsPerBar, currentBeat: beat,
            step: pa.stepInfo, scored: pa.lastRunWasScored,
            accuracy: pa.rolling ?? pa.lastCycleAccuracy, zone: pa.accuracyZone, lines: pa.meterLines,
            zoned: plan.mode == .accuracy,
            notes: pa.notes, played: pa.played, states: pa.states, heard: pa.heardPitch, now: pa.laneNow, tuning: pa.runTuning,
            recentErrors: pa.recentErrors, spanMs: pa.timingSpanMs,
            statusLeft: left, statusRight: right, challenge: challenge)
    }
}
