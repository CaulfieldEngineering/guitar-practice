import SwiftUI

/// After a scored run: the accuracy (or the time held) big, what it means in a line, every note's timing as a
/// strip, and the detail in rows. The run is already saved; the buttons are Again (or Play Solo after a guided
/// run) and Done.
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
                    Chip(text: L.chip(guided: guided, tempo: L.tempoRange(saved.startBPM, saved.topBPM))).padding(.top, Space.xs)

                    VStack(spacing: Space.xxs) {
                        if endurance {
                            Text(formatClock(saved.sustainedSeconds ?? 0))
                                .font(Typo.number(44)).foregroundStyle(Theme.accentText)
                                .lineLimit(1).minimumScaleFactor(0.5)
                            Text(L.heldAt(saved.targetPercent)).font(Typo.callout).foregroundStyle(Theme.muted)
                        } else {
                            Text(L.percent(score.score))
                                .font(Typo.number(44)).foregroundStyle(score.passed ? Theme.accentText : Theme.text)
                                .lineLimit(1).minimumScaleFactor(0.5)
                            Text(score.passed ? L.accuracyPassed : L.accuracyPassMark(score.passMark))
                                .font(Typo.callout).foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    if newBest || maxUp != nil {
                        VStack(spacing: Space.xxs) {
                            if newBest { Text(L.newBest) }
                            if let up = maxUp { Text(L.newMax(up.1, from: up.0)) }
                        }
                        .font(Typo.subStrong).foregroundStyle(Theme.accentText)
                        .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: Space.xs) {
                        SectionLabel(L.timingPerNote)
                        ErrorStrip(errors: score.errors, spanMs: max(40, score.zeroMs))
                            .frame(height: 64)
                        HStack {
                            Text(L.early)
                            Spacer()
                            Text(L.late)
                        }
                        .font(Typo.caption).foregroundStyle(Theme.faint)
                        .accessibilityHidden(true)
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
                TextButton(title: L.done, action: onDone)
                    .accessibilityIdentifier("result.done")
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)
            .background(alignment: .top) { Hairline() }
        }
    }

    /// The detail, most telling first.
    private var stats: [(String, String)] {
        var out: [(String, String)] = []
        if endurance { out.append((L.statAccuracy, L.percent(score.score))) }
        out.append((L.statOnBeat, L.percent(score.pctFull)))
        out.append((L.statAverage, averageText(score.meanError)))
        out.append((L.statSpread, L.ms(Int(score.spread.rounded()))))
        out.append((L.statMissed, L.ofTotal(score.missed, score.expected)))
        out.append((L.statExtra, "\(score.extra)"))
        if let a = saved.accentsPercent { out.append((L.statAccents, L.percent(a))) }
        out.append((L.statDuration, L.durationAndCycles(formatClock(saved.seconds), saved.cycles)))
        return out
    }

    private func averageText(_ e: Double) -> String {
        if abs(e) < 3 { return L.onTheBeat }
        let ms = Int(abs(e).rounded())
        return e > 0 ? L.msLate(ms) : L.msEarly(ms)
    }
}

/// After a run with the audio input off: how long it went, and that it was not scored.
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
                    .font(Typo.number(44)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(L.durationAndCycles(L.tempoRange(run.startBPM, run.topBPM), run.cycles))
                    .font(Typo.callout).foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .combine)
            Text(L.unscoredTotal(formatMinutes(total)))
                .font(Typo.sub).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, Space.lg)
                .padding(.horizontal, Space.xl)
            Spacer()
            VStack(spacing: 0) {
                PrimaryButton(title: againTitle, systemImage: "arrow.clockwise", action: onAgain)
                    .accessibilityIdentifier("result.primary")
                TextButton(title: L.done, action: onDone)
                    .accessibilityIdentifier("result.done")
            }
            .padding(.horizontal, Space.page)
        }
    }
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
