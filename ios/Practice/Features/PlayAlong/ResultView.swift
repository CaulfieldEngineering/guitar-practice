import SwiftUI

/// After a scored run: the accuracy (or the time held) big, what it means in a line, the detail in two columns, and
/// every note's timing as a strip. One primary button: again, or now solo after a guided run.
struct ResultView: View {
    let score: ScoreResult
    let saved: SessionResult
    let guided: Bool
    let newBest: Bool
    let maxUp: (Int, Int)?
    let primaryTitle: String
    let primaryImage: String
    let onPrimary: () -> Void
    let onDone: () -> Void

    private var endurance: Bool { saved.mode == "endurance" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Space.lg) {
                    Chip(text: chipText).padding(.top, Space.xs)

                    VStack(spacing: Space.xxs) {
                        if endurance {
                            Text(formatClock(saved.sustainedSeconds ?? 0))
                                .font(Typo.number(96)).foregroundStyle(Theme.accentText)
                                .lineLimit(1).minimumScaleFactor(0.5)
                            Text("held at \(saved.targetPercent)% accuracy or better").font(Typo.callout).foregroundStyle(Theme.muted)
                        } else {
                            Text("\(score.score)%")
                                .font(Typo.number(96)).foregroundStyle(score.passed ? Theme.accentText : Theme.text)
                                .lineLimit(1).minimumScaleFactor(0.5)
                            Text(score.passed ? "accuracy · passed" : "accuracy · \(score.passMark)% passes")
                                .font(Typo.callout).foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    if newBest || maxUp != nil {
                        VStack(spacing: Space.xxs) {
                            if newBest { Text("A new best at this tempo.") }
                            if let up = maxUp {
                                Text(up.0 > 0 ? "Your max is now \(up.1), up from \(up.0)." : "Your max is now \(up.1).")
                            }
                        }
                        .font(Typo.subStrong).foregroundStyle(Theme.accentText)
                        .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        SectionLabel("Every note: early above, late below")
                        ErrorStrip(errors: score.errors, spanMs: max(40, score.zeroMs))
                            .frame(height: 64)
                    }

                    VStack(spacing: 0) {
                        Hairline()
                        ForEach(stats.indices, id: \.self) { i in
                            Row(label: stats[i].0) {
                                Text(stats[i].1).font(Typo.figure(.body)).foregroundStyle(Theme.muted)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.lg)
            }
            VStack(spacing: 0) {
                PrimaryButton(title: primaryTitle, systemImage: primaryImage, action: onPrimary)
                    .accessibilityIdentifier("result.primary")
                TextButton(title: "Done", action: onDone)
                    .accessibilityIdentifier("result.done")
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)
            .background(alignment: .top) { Hairline() }
        }
    }

    private var chipText: String {
        let tempo = saved.topBPM > saved.startBPM ? "\(saved.startBPM) to \(saved.topBPM) bpm" : "\(saved.startBPM) bpm"
        return "\(guided ? "Guided" : "Solo") · \(tempo)"
    }

    /// The detail, most telling first.
    private var stats: [(String, String)] {
        var out: [(String, String)] = []
        if endurance { out.append(("Accuracy", "\(score.score)%")) }
        out.append(("On the click", "\(score.pctFull)% of notes"))
        out.append(("On average", averageText(score.meanError)))
        out.append(("Spread", "\(Int(score.spread.rounded())) ms"))
        out.append(("Missed", "\(score.missed) of \(score.expected)"))
        out.append(("Extra notes", "\(score.extra)"))
        if let a = saved.accentsPercent { out.append(("Accents that stood out", "\(a)%")) }
        out.append(("Played", "\(formatClock(saved.seconds)), \(saved.cycles) cycle\(saved.cycles == 1 ? "" : "s")"))
        return out
    }

    private func averageText(_ e: Double) -> String {
        abs(e) < 3 ? "right on the click" : "\(Int(abs(e).rounded())) ms \(e > 0 ? "late" : "early")"
    }
}

/// After a run with the audio input off: how long it went, and that nothing was scored.
struct UnscoredResultView: View {
    let run: PlayAlong.UnscoredRun
    /// Minutes on this drill with the audio input off, in all (this run included).
    let total: Double
    let againTitle: String
    let onAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Space.xxs) {
                Text(formatClock(run.seconds))
                    .font(Typo.number(96)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(tempoLine).font(Typo.callout).foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .combine)
            Text("Not scored: the audio input was off. \(formatMinutes(total).capitalizedFirst) on this drill that way so far.")
                .font(Typo.sub).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, Space.lg)
                .padding(.horizontal, Space.xl)
            Spacer()
            VStack(spacing: 0) {
                PrimaryButton(title: againTitle, systemImage: "arrow.clockwise", action: onAgain)
                    .accessibilityIdentifier("result.primary")
                TextButton(title: "Done", action: onDone)
                    .accessibilityIdentifier("result.done")
            }
            .padding(.horizontal, Space.page)
        }
    }

    private var tempoLine: String {
        let tempo = run.topBPM > run.startBPM ? "\(run.startBPM) to \(run.topBPM) bpm" : "\(run.startBPM) bpm"
        return "played at \(tempo), \(run.cycles) cycle\(run.cycles == 1 ? "" : "s")"
    }
}

extension String {
    /// The same words with the first letter a capital.
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}

/// Every note of the run, early above the line and late below, so a drift shows at a glance.
struct ErrorStrip: View {
    let errors: [Double?]
    var spanMs: Double = 60

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            ctx.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(Theme.lineStrong))
            guard !errors.isEmpty else { return }
            let step = size.width / CGFloat(errors.count)
            let span = Swift.max(1, spanMs)
            for (i, e) in errors.enumerated() {
                let x = (CGFloat(i) + 0.5) * step
                guard let e else {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: mid - 1.5, width: 3, height: 3)), with: .color(Theme.danger))
                    continue
                }
                let f = Swift.max(-1, Swift.min(1, e / span))
                let y = mid + CGFloat(f) * (mid - 3)
                let c = abs(f) <= 0.35 ? Theme.accent : (abs(f) < 0.7 ? Theme.accent.opacity(0.55) : Theme.warn)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(c))
            }
        }
        .background(Theme.side, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityHidden(true)
    }
}
