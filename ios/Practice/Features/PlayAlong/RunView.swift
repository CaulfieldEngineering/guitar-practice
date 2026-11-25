import SwiftUI

/// Everything the run screen shows, as plain values, so the screen is a function of them (and the UI test can draw
/// it from made-up values).
struct RunDisplay {
    var title: String
    /// The pattern now ("Triplets") and what comes after it ("16ths in 2 beats").
    var cue: String
    var cueDetail: String
    var cueWarn: Bool
    var bpm: Int
    var countingIn: Bool
    var beatsPerBar: Int = 4
    var currentBeat: Int = -1
    /// The tempo plan: where it is heading and how far to the next step (nil: off).
    var step: PlayAlong.StepInfo?
    /// With the audio input on: the rolling accuracy (nil until a loop is judged), its zone, and the meter's lines.
    var scored: Bool
    var accuracy: Double?
    var zone: TempoPlan.Zone?
    var lines: [Int]
    var zoned: Bool
    var notes: [Exercise.Note]
    var played: [Onset]
    var states: [PlayAlong.NoteState]
    var heard: [Int: Double] = [:]
    var now: Double
    var tuning: Tuning = .standard
    var recentErrors: [Double]
    var spanMs: Double
    /// "Loop 5 of 16" and "2:14 left".
    var statusLeft: String
    var statusRight: String
    /// Challenge: the time earned, the time it has taken, the target, and whether the clock is running.
    var challenge: ChallengeLine?

    struct ChallengeLine {
        var earned: Double
        var target: Double
        var elapsed: Double
        var inZone: Bool
        var share: Double
    }
}

/// A run, made to be glanced at from a metre away while both hands are busy: the pattern now, the tempo big, the beat,
/// where the tempo is going, the accuracy meter, the lane, the timing strip, and Pause and Stop. A tap anywhere above
/// the buttons pauses (Joe, on 0.1.6: "can't figure out how to stop it"). In a routine the routine's own buttons
/// take the place of Pause and Stop.
struct RunView: View {
    let d: RunDisplay
    var paused = false
    var message: String? = nil
    var route: String = ""
    var showsControls = true
    let onPause: () -> Void
    let onResume: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ZStack {
            running
                .opacity(paused ? 0.4 : 1)
                .allowsHitTesting(!paused)
                .accessibilityHidden(paused)
            if paused { pausedPanel }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(d.title).font(Typo.sub).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer()
                    RoutePicker().frame(width: 44, height: 44).accessibilityLabel(L.chooseOutput)
                }
                .frame(height: 44)

                HStack(alignment: .firstTextBaseline) {
                    Text(d.cue).font(Typo.cue).foregroundStyle(d.cueWarn ? Theme.warn : Theme.text).lineLimit(1)
                    Spacer()
                    Text(d.cueDetail).font(Typo.sub).foregroundStyle(Theme.muted).lineLimit(1)
                }

                HStack(alignment: .lastTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.tiny) {
                        Text("\(d.bpm)").font(Typo.tempoRun).foregroundStyle(d.countingIn ? Theme.muted : Theme.text)
                            .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.6)
                        Text(L.bpm).font(Typo.body).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if d.countingIn {
                            Text(L.countInWord)
                        } else if let s = d.step {
                            Text(L.targetBPM(s.target))
                            if let n = s.next { Text(L.nextBPM(n)) }
                        }
                    }
                    .font(Typo.figure(.subheadline)).foregroundStyle(Theme.muted)
                }
                .sensoryFeedback(.increase, trigger: d.step?.target ?? 0) { a, b in b > a }
                .sensoryFeedback(.decrease, trigger: d.step?.target ?? 0) { a, b in b < a && b > 0 }

                BeatBar(beats: d.beatsPerBar, current: d.currentBeat).padding(.top, Space.xs)

                if let s = d.step {
                    StepProgress(info: s).padding(.top, Space.md)
                }
                if d.scored {
                    AccuracyMeter(accuracy: d.accuracy, lines: d.lines, zone: d.zone, zoned: d.zoned).padding(.top, Space.md)
                }
                if let c = d.challenge { challengeLine(c).padding(.top, Space.md) }
            }
            .padding(.horizontal, Space.page)

            TabLane(notes: d.notes, played: d.played, states: d.states, now: d.now, beatsPerBar: d.beatsPerBar,
                    tuning: d.tuning, heard: d.heard)
                .frame(minHeight: 140, maxHeight: 220)
                .padding(.top, Space.md)

            VStack(alignment: .leading, spacing: 0) {
                if d.scored {
                    TimingMeter(errors: d.recentErrors, spanMs: d.spanMs).frame(height: 28).padding(.top, Space.xs)
                }
                HStack {
                    Text(d.statusLeft)
                    Spacer()
                    Text(d.statusRight)
                }
                .font(Typo.figure(.subheadline)).foregroundStyle(Theme.muted)
                .padding(.top, Space.xs)
                Spacer(minLength: Space.xs)
                if showsControls {
                    HStack(spacing: Space.sm) {
                        QuietButton(title: L.pause, systemImage: "pause.fill") { onPause() }
                            .accessibilityIdentifier("run.pause")
                        QuietButton(title: L.stop, systemImage: "stop.fill") { onEnd() }
                            .accessibilityIdentifier("run.stop")
                    }
                    .padding(.bottom, Space.sm)
                }
            }
            .padding(.horizontal, Space.page)
        }
        .contentShape(Rectangle())
        .onTapGesture { if showsControls { onPause() } }
    }

    private func challengeLine(_ c: RunDisplay.ChallengeLine) -> some View {
        VStack(alignment: .leading, spacing: Space.tiny) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.challenge).font(Typo.foot).foregroundStyle(Theme.muted)
                Spacer()
                Text(L.earnedOf(formatClock(c.earned), formatClock(c.target)))
                    .font(Typo.stat).foregroundStyle(c.inZone ? Theme.text : Theme.warn)
                    .contentTransition(.numericText())
            }
            ProgressLine(fraction: c.target > 0 ? c.earned / c.target : 0, colour: c.inZone ? Theme.accent : Theme.warn)
            HStack {
                Text(c.inZone ? L.clockRunning : L.clockHeld)
                Spacer()
                Text(L.inZoneShare(formatClock(c.elapsed), Int((c.share * 100).rounded())))
            }
            .font(Typo.figure(.footnote)).foregroundStyle(c.inZone ? Theme.muted : Theme.warn)
        }
        .accessibilityElement(children: .combine)
    }

    private var pausedPanel: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Spacer()
            Text(L.paused).font(Typo.cue).foregroundStyle(Theme.text)
            if let message {
                Text(message).font(Typo.sub).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("run.message")
            } else if !route.isEmpty {
                Text(route).font(Typo.sub).foregroundStyle(Theme.muted)
            }
            Spacer()
            if showsControls {
                PrimaryButton(title: L.resume, systemImage: "play.fill") { onResume() }
                    .accessibilityIdentifier("run.resume")
                HStack {
                    Spacer()
                    TextButton(title: L.end, colour: Theme.danger) { onEnd() }
                        .accessibilityIdentifier("run.end")
                    Spacer()
                }
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// A break the accuracy called for: the click stops, a countdown runs, and the run goes on by itself, a step slower
/// when the plan says so. Calm, not red.
struct BreakView: View {
    let left: Double
    let length: Double
    let resumeBPM: Int
    var showsControls = true
    let onSkip: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Spacer()
            Text(L.breakTitle).font(Typo.cue).foregroundStyle(Theme.text)
            Text(left <= 3 ? "\(Int(left.rounded(.up)))" : formatClock(left.rounded(.up)))
                .font(Typo.tempoHero).foregroundStyle(Theme.text)
                .contentTransition(.numericText())
                .accessibilityIdentifier("break.clock")
            Text(L.restYourHand).font(Typo.body).foregroundStyle(Theme.muted)
            Text(L.resumesAt(resumeBPM)).font(Typo.sub).foregroundStyle(Theme.muted)
            ProgressLine(fraction: length > 0 ? left / length : 0, colour: Theme.lineStrong, track: Theme.line)
                .padding(.top, Space.sm)
            Spacer()
            if showsControls {
                HStack(spacing: Space.sm) {
                    QuietButton(title: L.skip, systemImage: "forward.end.fill") { onSkip() }
                        .accessibilityIdentifier("break.skip")
                    QuietButton(title: L.stop, systemImage: "stop.fill") { onStop() }
                }
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.bg)
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: Int(left.rounded(.up))) { _, n in n <= 3 && n > 0 }
    }
}

/// Early or late: the latest picks as dots along a line whose middle is the click. The newest is the brightest.
struct TimingMeter: View {
    let errors: [Double]
    let spanMs: Double

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(L.early).font(Typo.caption).foregroundStyle(Theme.faint)
            Canvas { ctx, size in
                let mid = size.width / 2
                let y = size.height / 2
                ctx.fill(Path(CGRect(x: 0, y: y - 0.5, width: size.width, height: 1)), with: .color(Theme.line))
                ctx.fill(Path(CGRect(x: mid - 0.5, y: 2, width: 1, height: size.height - 4)), with: .color(Theme.lineStrong))
                let span = max(1, spanMs)
                for (i, e) in errors.enumerated() {
                    let f = max(-1, min(1, e / span))
                    let x = mid + CGFloat(f) * (mid - 5)
                    let age = Double(errors.count - 1 - i)
                    let alpha = max(0.15, 1 - age * 0.09)
                    let r: CGFloat = i == errors.count - 1 ? 4 : 3
                    let colour = abs(f) <= 0.35 ? Theme.accent : (abs(f) < 1 ? Theme.warn : Theme.danger)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(colour.opacity(alpha)))
                }
            }
            Text(L.late).font(Typo.caption).foregroundStyle(Theme.faint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.timingLabel)
        .accessibilityValue(spoken)
    }

    private var spoken: String {
        guard let last = errors.last else { return L.noNotesYet }
        if abs(last) < 3 { return L.onTheBeat }
        let ms = Int(abs(last).rounded())
        return last > 0 ? L.msLate(ms) : L.msEarly(ms)
    }
}
