import SwiftUI

/// Everything the run screen shows, as plain values, so the screen is a function of them (and can be drawn in a
/// test with made-up values).
struct RunDisplay {
    /// "Solo · Z3 Tempo · 88% of max"
    var chip: String
    /// The pattern being played now ("Triplets"), and what comes after it.
    var cue: String
    var cueDetail: String
    var cueWarn: Bool
    var bpm: Int
    /// With the audio input on: the rolling accuracy (nil until a cycle has been judged).
    var scored: Bool
    var accuracy: Int?
    var accuracyGood: Bool
    /// "3 of 8", or "3" when the run has no set number of cycles.
    var cycle: String
    var cycleLabel: String = L.cycle
    var clock: String
    var clockLabel: String
    var countingIn: Bool
    var calibrating: Bool
    var notes: [Exercise.Note]
    var played: [Onset]
    var states: [PlayAlong.NoteState]
    var now: Double
    var beat: Double
    /// The latest notes' timing errors (ms, positive late), and how far off earns nothing.
    var recentErrors: [Double]
    var spanMs: Double
    var inputLevel: Float
}

/// A run, made to be glanced at while playing: the pattern now, the tempo, the accuracy and the time, all big; the
/// lane of notes; whether the picks land early or late. Tapping anywhere pauses it; Pause and Stop are always there
/// at the bottom (Joe, on 0.1.6: "can't figure out how to stop it"). Paused, the screen says so and offers Resume
/// and End.
struct RunView: View {
    let d: RunDisplay
    var paused = false
    /// Something to say while paused (the interface was unplugged, say).
    var message: String? = nil
    /// Where the sound comes in and goes out ("In: iRig · Out: Shokz"), shown while paused beside the picker.
    var route: String = ""
    let onPause: () -> Void
    let onResume: () -> Void
    let onEnd: () -> Void

    var body: some View {
        ZStack {
            running
                .opacity(paused ? 0.5 : 1)
                .allowsHitTesting(!paused)
                .accessibilityHidden(paused)
            if paused { pausedCard }
        }
        // The system's output picker, always in reach: the headphones, the interface or the speaker.
        .overlay(alignment: .topTrailing) {
            RoutePicker().frame(width: 40, height: 40)
                .padding(.trailing, Space.xs)
                .padding(.top, Space.xxs)
                .accessibilityLabel(L.chooseOutput)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .contentShape(Rectangle())
        .onTapGesture { if !paused { onPause() } }
    }

    private var running: some View {
        VStack(spacing: 0) {
            Chip(text: d.chip)
                .padding(.top, Space.sm)

            Spacer(minLength: Space.sm)

            Text(d.cue)
                .font(Typo.number(60))
                .foregroundStyle(d.cueWarn ? Theme.warn : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.opacity)
            Text(d.cueDetail)
                .font(Typo.figure(.title3))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, Space.xxs)

            Spacer(minLength: Space.sm)

            HStack(alignment: .top, spacing: 0) {
                BigStat(value: "\(d.bpm)", label: L.bpm)
                if d.scored {
                    BigStat(value: d.accuracy.map { L.percent($0) } ?? "--", label: L.accuracy,
                            colour: d.accuracy == nil ? Theme.muted : (d.accuracyGood ? Theme.accentText : Theme.warn))
                } else {
                    BigStat(value: d.cycle, label: d.cycleLabel)
                }
                BigStat(value: d.clock, label: d.clockLabel, colour: d.countingIn ? Theme.warn : Theme.text)
            }

            LaneView(notes: d.notes, played: d.played, states: d.states, now: d.now, beat: d.beat)
                .frame(height: 132)
                .padding(.top, Space.lg)

            if d.scored {
                TimingMeter(errors: d.recentErrors, spanMs: d.spanMs)
                    .frame(height: 44)
                    .padding(.top, Space.sm)
                HStack(spacing: Space.xs) {
                    Text(L.input).font(Typo.caption).foregroundStyle(Theme.faint)
                    ProgressLine(fraction: Double(meterFraction(d.inputLevel)), height: 3)
                }
                .padding(.top, Space.xs)
            }

            Spacer(minLength: Space.sm)

            HStack(spacing: Space.sm) {
                QuietButton(title: L.pause, systemImage: "pause.fill", height: 52) { onPause() }
                    .accessibilityIdentifier("run.pause")
                QuietButton(title: L.stop, systemImage: "stop.fill", height: 52) { onEnd() }
                    .accessibilityIdentifier("run.stop")
            }
            Text(L.tapToPause)
                .font(Typo.foot).foregroundStyle(Theme.faint)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.sm)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.page)
    }

    private var pausedCard: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "pause.fill").font(.system(size: 34, weight: .regular)).foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            Text(L.paused).font(Typo.number(44)).foregroundStyle(Theme.text)
                .padding(.top, Space.sm)
            Text(L.pausedHelp)
                .font(Typo.callout).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
            if let message {
                Text(message).font(Typo.sub).foregroundStyle(Theme.warn)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.sm)
                    .accessibilityIdentifier("run.message")
            }
            if !route.isEmpty {
                Text(route).font(Typo.foot).foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
                    .padding(.top, Space.sm)
            }
            Spacer()
            PrimaryButton(title: L.resume, systemImage: "play.fill") { onResume() }
                .accessibilityIdentifier("run.resume")
            QuietButton(title: L.end, systemImage: "stop.fill", height: 52) { onEnd() }
                .accessibilityIdentifier("run.end")
                .padding(.top, Space.sm)
                .padding(.bottom, Space.md)
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.opacity(0.95))
    }

    /// The input level as a fraction of a 60 dB scale.
    private func meterFraction(_ level: Float) -> CGFloat {
        let db = 20 * log10(Double(max(level, 1e-5)))
        let f = (db + 60) / 60
        return CGFloat(min(1, max(0, f)))
    }
}

/// Early or late: the latest picks as dots along a line whose middle is the click. Left of the middle is ahead of
/// the click, right is behind it; the newest dot is the brightest. The ends are where a note earns nothing.
struct TimingMeter: View {
    let errors: [Double]
    let spanMs: Double

    var body: some View {
        VStack(spacing: Space.xxs) {
            Canvas { ctx, size in
                let mid = size.width / 2
                let y = size.height / 2
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: y - 1, width: size.width, height: 2), cornerRadius: 1), with: .color(Theme.line))
                ctx.fill(Path(roundedRect: CGRect(x: mid - 1, y: 0, width: 2, height: size.height), cornerRadius: 1), with: .color(Theme.lineStrong))
                let span = max(1, spanMs)
                let count = errors.count
                for (i, e) in errors.enumerated() {
                    let f = max(-1, min(1, e / span))
                    let x = mid + CGFloat(f) * (mid - 6)
                    let age = Double(count - 1 - i)
                    let alpha = max(0.15, 1 - age * 0.09)
                    let newest = i == count - 1
                    let r: CGFloat = newest ? 6 : 4
                    let colour = abs(f) <= 0.35 ? Theme.accent : (abs(f) < 1 ? Theme.warn : Theme.danger)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(colour.opacity(alpha)))
                }
            }
            HStack {
                Text(L.early)
                Spacer()
                Text(L.late)
            }
            .font(Typo.caption)
            .foregroundStyle(Theme.faint)
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

/// A quiet bar that says something is playing and stops it: on a tab whose own screen is not the one making the
/// sound (the metronome ticking while the Drills list is open, a drill that somehow outlived its screen).
struct RunningBar: View {
    /// The mode this screen makes itself; its own sound needs no bar.
    let own: Player.Mode
    @EnvironmentObject var player: Player
    @EnvironmentObject var pa: PlayAlong

    private var drill: Bool { player.mode == .playAlong || pa.phase == .paused }
    private var shows: Bool {
        if drill { return own != .playAlong }
        return player.mode != .idle && player.mode != own
    }

    var body: some View {
        if shows {
            HStack(spacing: Space.sm) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(text).font(Typo.sub).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: Space.xs)
                Button {
                    Haptics.tap()
                    pa.leave()
                    player.stop()
                } label: {
                    Label(L.stop, systemImage: "stop.fill")
                        .font(Typo.subStrong)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, Space.sm)
                        .frame(minHeight: 36)
                        .background(Theme.hover, in: Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("running.stop")
            }
            .padding(.horizontal, Space.page)
            .frame(minHeight: Space.touch + Space.xs)
            .background(Theme.accentSoft)
            .accessibilityElement(children: .contain)
        }
    }

    private var text: String {
        if drill { return pa.phase == .paused ? L.drillPaused : L.drillRunning }
        switch player.mode {
        case .metronome: return L.metronomeAt(player.bpm)
        case .routine: return L.routineRunning
        default: return L.playing
        }
    }
}
