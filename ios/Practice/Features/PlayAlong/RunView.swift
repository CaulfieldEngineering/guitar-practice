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
/// lane of notes; whether the picks land early or late. Tapping anywhere stops the run.
struct RunView: View {
    let d: RunDisplay
    let onStop: () -> Void

    var body: some View {
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
                BigStat(value: "\(d.bpm)", label: "bpm")
                if d.scored {
                    BigStat(value: d.accuracy.map { "\($0)%" } ?? "--", label: "accuracy",
                            colour: d.accuracy == nil ? Theme.muted : (d.accuracyGood ? Theme.accentText : Theme.warn))
                } else {
                    BigStat(value: d.cycle, label: "cycle")
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
                    Text("Input").font(Typo.caption).foregroundStyle(Theme.faint)
                    ProgressLine(fraction: Double(meterFraction(d.inputLevel)), height: 3)
                }
                .padding(.top, Space.xs)
            }

            Spacer(minLength: Space.sm)

            QuietButton(title: "Stop", systemImage: "stop.fill", height: 48) { onStop() }
                .accessibilityIdentifier("run.stop")
            Text("or tap anywhere")
                .font(Typo.foot).foregroundStyle(Theme.faint)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.sm)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .contentShape(Rectangle())
        .onTapGesture { onStop() }
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
                Text("early")
                Spacer()
                Text("late")
            }
            .font(Typo.caption)
            .foregroundStyle(Theme.faint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timing")
        .accessibilityValue(spoken)
    }

    private var spoken: String {
        guard let last = errors.last else { return "No notes yet" }
        if abs(last) < 3 { return "On the click" }
        return "\(Int(abs(last).rounded())) milliseconds \(last > 0 ? "late" : "early")"
    }
}
