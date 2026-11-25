import SwiftUI

/// After a scored run: one line of what it was, the number big (accuracy, the time held, or the time earned in a
/// Challenge), a new max when there is one, the tempo table when the tempo moved, every note's timing as a strip,
/// then the detail as rows. Left-aligned; the run is already saved. Again at the bottom; Done in the bar.
struct ResultView: View {
    let score: ScoreResult
    let saved: SessionResult
    let guided: Bool
    let maxUp: (Int, Int)?
    let primaryTitle: String
    let primaryImage: String
    let onPrimary: () -> Void
    @State private var about = false

    private var endurance: Bool { saved.mode == "endurance" }
    private var challenge: Bool { saved.mode == "challenge" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L.resultSummary(guided: guided, start: saved.startBPM, top: saved.topBPM, seconds: saved.seconds))
                    .font(Typo.sub).foregroundStyle(Theme.muted)
                    .padding(.top, Space.sm)

                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(headline).font(Typo.statLarge).foregroundStyle(good ? Theme.accentText : Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(headlineCaption).font(Typo.body).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .padding(.top, Space.xs)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("result.headline")

                if let up = maxUp {
                    Text(L.newMax(up.1, from: up.0)).font(Typo.subStrong).foregroundStyle(Theme.accentText).padding(.top, Space.xs)
                }

                if let steps = saved.tempoSteps, steps.count > 1 {
                    VStack(spacing: 0) {
                        ColumnHeads(first: L.tempo, columns: [(L.time, 64), (L.accuracy, 72)]).padding(.horizontal, -Space.page)
                        Hairline()
                        ForEach(steps.indices, id: \.self) { i in
                            let s = steps[i]
                            TableRow(name: s.rest == true ? L.breakTitle : "\(s.bpm)",
                                     values: [(formatClock(s.seconds), 64), (s.accuracy.map { L.percent($0) } ?? "–", 72)], faintValues: true)
                                .padding(.horizontal, -Space.page)
                            Hairline()
                        }
                    }
                    .padding(.top, Space.lg)
                }

                Text(L.timingPerNote).font(Typo.foot).foregroundStyle(Theme.muted).padding(.top, Space.lg)
                ErrorStrip(errors: score.errors, spanMs: max(40, score.zeroMs))
                    .frame(height: 56).padding(.top, Space.xs)
                HStack { Text(L.early); Spacer(); Text(L.late) }
                    .font(Typo.caption).foregroundStyle(Theme.faint).accessibilityHidden(true)

                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { i in
                        HStack {
                            Text(rows[i].0).font(Typo.body).foregroundStyle(Theme.text)
                            Spacer()
                            Text(rows[i].1).font(Typo.figure(.body)).foregroundStyle(Theme.muted)
                        }
                        .frame(minHeight: Control.row)
                        .overlay(alignment: .bottom) { Hairline() }
                        .accessibilityElement(children: .combine)
                    }
                    Button { about = true } label: {
                        HStack {
                            Text(L.aboutNumbers).font(Typo.body).foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.faint)
                        }
                        .frame(minHeight: Control.row)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.top, Space.lg)
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.lg)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: primaryTitle, systemImage: primaryImage, action: onPrimary)
                .accessibilityIdentifier("result.primary")
                .padding(.horizontal, Space.page).padding(.top, Space.sm).padding(.bottom, Space.xs)
                .background(Theme.bg.overlay(alignment: .top) { Hairline() }.ignoresSafeArea(edges: .bottom))
        }
        .background(Theme.bg)
        .sheet(isPresented: $about) {
            NavigationStack {
                ScrollView {
                    Text(L.timingAnchorsLong).font(Typo.body).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.page)
                }
                .navigationTitle(L.aboutNumbers)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.done) { about = false } } }
            }
            .presentationDetents([.medium])
        }
    }

    private var good: Bool { challenge ? saved.passed : (endurance ? (saved.sustainedSeconds ?? 0) > 0 : score.passed) }

    private var headline: String {
        if challenge { return formatClock(saved.earnedSeconds ?? 0) }
        if endurance { return formatClock(saved.sustainedSeconds ?? 0) }
        return L.percent(score.score)
    }

    private var headlineCaption: String {
        if challenge { return L.earnedAt(saved.targetPercent) }
        if endurance { return L.heldAt(saved.targetPercent) }
        return L.accuracyPassMarkLine(score.passMark)
    }

    private var rows: [(String, String)] {
        var out: [(String, String)] = []
        if endurance || challenge { out.append((L.accuracy, L.percent(score.score))) }
        if challenge {
            out.append((L.elapsed, formatClock(saved.elapsedSeconds ?? saved.seconds)))
            if let e = saved.elapsedSeconds, e > 0 { out.append((L.inZone, L.percent(Int(((saved.earnedSeconds ?? 0) / e * 100).rounded())))) }
            out.append((L.bestStreak, formatClock(saved.bestStreakSeconds ?? 0)))
        }
        out.append((L.timing, averageText(score.meanError)))
        out.append((L.spread, L.spreadValue(Int(score.spread.rounded()), Scoring.band(spreadMs: score.spread))))
        if score.extra > 0 { out.append((L.extraNotes, "\(score.extra)")) }
        out.append((L.missed, L.ofTotal(score.missed, score.expected)))
        if let w = saved.wrongPitch { out.append((L.wrongNotes, "\(w)")) }
        if let a = saved.accentsPercent { out.append((L.accents, L.percent(a))) }
        if saved.topBPM > saved.startBPM { out.append((L.topTempo, L.bpmValue(saved.topBPM))) }
        if let b = saved.breaks, b > 0 { out.append((L.breaksRow, "\(b)")) }
        out.append((L.loopsTitle, "\(saved.cycles)"))
        return out
    }

    private func averageText(_ e: Double) -> String {
        if abs(e) < 3 { return L.onTheBeat }
        let ms = Int(abs(e).rounded())
        return e > 0 ? L.msLate(ms) : L.msEarly(ms)
    }
}

/// After a run with the audio input off: how long it went and at what tempo; nothing was scored.
struct UnscoredResultView: View {
    let run: PlayAlong.UnscoredRun
    let total: Double
    let onAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(L.notScoredLine).font(Typo.sub).foregroundStyle(Theme.muted).padding(.top, Space.sm)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(formatClock(run.seconds)).font(Typo.statLarge).foregroundStyle(Theme.text)
                Text(L.tempoRange(run.startBPM, run.topBPM) + " " + L.bpm).font(Typo.body).foregroundStyle(Theme.muted)
            }
            Text(L.unscoredTotal(formatMinutes(total))).font(Typo.sub).foregroundStyle(Theme.muted).padding(.top, Space.xs)
            Spacer()
            PrimaryButton(title: L.again, systemImage: "arrow.clockwise", action: onAgain)
                .accessibilityIdentifier("result.primary")
                .padding(.bottom, Space.xs)
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.bg)
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
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)), with: .color(c))
            }
        }
        .accessibilityHidden(true)
    }
}
