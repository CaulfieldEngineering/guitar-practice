import SwiftUI

/// Progress: for each drill, his max and how the tempo he reaches has moved, the best run at each tempo, and the
/// minutes played with the audio input off; then the latest runs. From the mini PC when it can be reached (every
/// device's runs), otherwise the phone's own copy.
struct StatsView: View {
    @EnvironmentObject var history: History
    @EnvironmentObject var pa: PlayAlong
    @Environment(\.dismiss) private var dismiss
    @State private var server: [SessionResult]?
    @State private var loading = true

    private var results: [SessionResult] { server ?? history.results }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    HStack(spacing: Space.xs) {
                        Circle().fill(server == nil && !loading ? Theme.warn : Theme.accent).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(source).font(Typo.foot).foregroundStyle(Theme.muted)
                    }

                    if results.isEmpty && pa.unscoredSeconds.isEmpty {
                        Text(L.noRuns).font(Typo.callout).foregroundStyle(Theme.muted)
                    }

                    ForEach(exerciseIDs, id: \.self) { id in
                        drill(id)
                    }

                    if !results.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel(L.recent).padding(.bottom, Space.xs)
                            Hairline()
                            ForEach(results.prefix(30)) { r in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(r.exerciseName).font(Typo.body).foregroundStyle(Theme.text).lineLimit(1)
                                        Spacer(minLength: Space.sm)
                                        Text(r.mode == "endurance" ? formatClock(r.sustainedSeconds ?? 0) : L.percent(r.score))
                                            .font(Typo.figure(.body, weight: .medium)).foregroundStyle(Theme.text)
                                    }
                                    Text(detail(r)).font(Typo.foot).foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, Space.sm)
                                .accessibilityElement(children: .combine)
                                Hairline()
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.vertical, Space.md)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(L.progress)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.done) { dismiss() } } }
            .refreshable { await load() }
            .task { await load() }
        }
        .tint(Theme.accentText)
    }

    /// One drill: its name, the max, the trend, the bests, the minutes with the input off.
    private func drill(_ id: String) -> some View {
        let solo = results.filter { $0.exerciseID == id && !$0.guided }.sorted { $0.date < $1.date }
        let bests = Stats.bests(results).filter { $0.exerciseID == id }
        let reached = solo.map { Double($0.topBPM) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(name(id)).font(Typo.title).foregroundStyle(Theme.text)
                Spacer(minLength: Space.sm)
                if let m = pa.level(id) {
                    Text(L.maxBPM(m)).font(Typo.figure(.subheadline, weight: .medium)).foregroundStyle(Theme.accentText)
                }
            }
            .padding(.bottom, Space.xs)

            if reached.count >= 2 {
                Sparkline(values: reached)
                    .frame(height: 44)
                    .accessibilityLabel(L.tempoTrendLabel)
                    .accessibilityValue(L.tempoTrend(Int(reached.min() ?? 0), Int(reached.max() ?? 0)))
                Text(L.tempoTrend(Int(reached.min() ?? 0), Int(reached.max() ?? 0)))
                    .font(Typo.caption).foregroundStyle(Theme.faint)
                    .padding(.top, Space.xxs).padding(.bottom, Space.xs)
            }

            Hairline()
            ForEach(bests, id: \.self) { b in
                HStack(spacing: Space.xs) {
                    Text("\(b.bpm) \(L.bpm)").font(Typo.figure(.body)).foregroundStyle(Theme.text)
                    Text(L.modeName(b.mode)).font(Typo.sub).foregroundStyle(Theme.muted)
                    Spacer(minLength: Space.xs)
                    Text(b.mode == "endurance" ? formatClock(b.value) : L.percent(Int(b.value)))
                        .font(Typo.figure(.body, weight: .medium)).foregroundStyle(Theme.text)
                    Text(L.runCount(b.runs)).font(Typo.caption).foregroundStyle(Theme.faint)
                        .frame(minWidth: 52, alignment: .trailing)
                }
                .frame(minHeight: Space.touch)
                .accessibilityElement(children: .combine)
                Hairline()
            }
            if let secs = pa.unscoredSeconds[id], secs > 0 {
                HStack {
                    Text(L.unscoredPractice).font(Typo.sub).foregroundStyle(Theme.muted)
                    Spacer(minLength: Space.xs)
                    Text(formatMinutes(secs)).font(Typo.figure(.subheadline)).foregroundStyle(Theme.muted)
                }
                .frame(minHeight: Space.touch)
                .accessibilityElement(children: .combine)
                Hairline()
            }
        }
    }

    private func load() async {
        loading = true
        await history.sync()
        server = await DrillServer.fetchSessions()
        loading = false
    }

    /// "Nov 14, 3:01 PM · 128 bpm · Cycles · Guided · 91%"
    private func detail(_ r: SessionResult) -> String {
        var parts = [r.date.formatted(date: .abbreviated, time: .shortened), L.tempoRange(r.startBPM, r.topBPM), L.modeName(r.mode)]
        if r.guided { parts.append(L.guided) }
        parts.append(L.percent(r.accuracyPercent))
        return parts.joined(separator: " · ")
    }

    private var source: String {
        if loading { return L.syncing }
        return server != nil ? L.synced(pending: history.pendingCount) : L.offline(pending: history.pendingCount)
    }

    /// Drills with runs, newest first, then drills that only have minutes with the input off.
    private var exerciseIDs: [String] {
        var seen = Set<String>()
        var ids = results.map(\.exerciseID).filter { seen.insert($0).inserted }
        for id in pa.unscoredSeconds.keys.sorted() where seen.insert(id).inserted { ids.append(id) }
        return ids
    }

    private func name(_ id: String) -> String {
        pa.exercises.first { $0.id == id }?.name ?? results.first { $0.exerciseID == id }?.exerciseName ?? id
    }
}

/// A small line of values in order, the last one marked.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
            let range = Swift.max(1, hi - lo)
            let inset: CGFloat = 5
            func point(_ i: Int) -> CGPoint {
                let x = inset + (size.width - inset * 2) * CGFloat(i) / CGFloat(values.count - 1)
                let y = size.height - inset - (size.height - inset * 2) * CGFloat((values[i] - lo) / range)
                return CGPoint(x: x, y: y)
            }
            var path = Path()
            path.move(to: point(0))
            for i in 1..<values.count { path.addLine(to: point(i)) }
            ctx.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            let last = point(values.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)), with: .color(Theme.accent))
        }
    }
}
