import SwiftUI

/// Progress, a tab of its own (0.3.0): one status line, a table of the drills (max, best), and every session newest
/// first, a drill's run or a whole routine. From the mini PC when it can be reached (every device's runs), otherwise
/// the phone's own copy. Practices, not targets: no streaks, no counts held up at him.
struct ProgressTab: View {
    @EnvironmentObject var history: History
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var log: RoutineRunLog
    @State private var server: [SessionResult]?
    @State private var loading = true
    @State private var shown = 30

    private var results: [SessionResult] { server ?? history.results }

    private enum Session: Identifiable {
        case run(SessionResult)
        case routine(RoutineRunRecord)
        var id: String {
            switch self { case .run(let r): return r.id.uuidString; case .routine(let r): return "r" + r.id.uuidString }
        }
        var date: Date {
            switch self { case .run(let r): return r.date; case .routine(let r): return r.date }
        }
    }

    /// Drill runs that were a routine's blocks show inside the routine, not again on their own.
    private var sessions: [Session] {
        let inRoutines = Set(log.runs.flatMap { $0.blocks.compactMap(\.sessionID) })
        let runs = results.filter { !inRoutines.contains($0.id) }.map(Session.run)
        return (runs + log.runs.map(Session.routine)).sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.xs) {
                        Circle().fill(server == nil && !loading ? Theme.warn : Theme.muted).frame(width: 6, height: 6)
                        Text(source).font(Typo.foot).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, Space.page).padding(.vertical, Space.sm)

                    if sessions.isEmpty {
                        Text(L.noSessions).font(Typo.sub).foregroundStyle(Theme.muted).padding(.horizontal, Space.page)
                    } else {
                        label(L.drills)
                        ColumnHeads(first: L.columnDrill, columns: [(L.columnMax, 48), (L.columnBest, 52)])
                        Hairline()
                        ForEach(drillIDs, id: \.self) { id in
                            NavigationLink { DrillProgressView(exerciseID: id, results: results) } label: {
                                TableRow(name: name(id), values: [(pa.level(id).map { "\($0)" } ?? "–", 48), (best(id).map { L.percent($0) } ?? "–", 52)])
                            }
                            .buttonStyle(PressStyle())
                            Hairline().padding(.leading, Space.page)
                        }

                        label(L.sessions)
                        ColumnHeads(first: L.columnSession, columns: [(L.tempo, 84), (L.accuracy, 64)])
                        Hairline()
                        ForEach(sessions.prefix(shown)) { s in
                            row(s)
                            Hairline().padding(.leading, Space.page)
                        }
                        if sessions.count > shown {
                            Button(L.showMore) { shown += 30 }.font(Typo.body).foregroundStyle(Theme.accentText)
                                .frame(minHeight: Control.row).padding(.horizontal, Space.page)
                        }
                    }
                }
                .padding(.bottom, Space.lg)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(L.progress)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Typo.foot).foregroundStyle(Theme.muted)
            .padding(.horizontal, Space.page).padding(.top, Space.lg).padding(.bottom, Space.xxs)
    }

    @ViewBuilder
    private func row(_ s: Session) -> some View {
        switch s {
        case .run(let r):
            NavigationLink { SavedRunView(result: r) } label: {
                TableRow(name: r.exerciseName, detail: when(r.date),
                         values: [(L.tempoRange(r.startBPM, r.topBPM), 84), (headline(r), 64)])
            }
            .buttonStyle(PressStyle())
        case .routine(let r):
            NavigationLink {
                ScrollView { RoutineRunSummary(record: r).padding(.horizontal, Space.page) }
                    .background(Theme.bg.ignoresSafeArea())
                    .navigationTitle(r.routineName).navigationBarTitleDisplayMode(.inline)
            } label: {
                let acc = r.blocks.compactMap(\.accuracy)
                TableRow(name: r.routineName, detail: when(r.date),
                         values: [(L.blockCount(r.blocks.count), 84), (acc.isEmpty ? "–" : L.percent(acc.reduce(0, +) / acc.count), 64)])
            }
            .buttonStyle(PressStyle())
        }
    }

    private func headline(_ r: SessionResult) -> String {
        switch r.mode {
        case "endurance": return formatClock(r.sustainedSeconds ?? 0)
        case "challenge": return formatClock(r.earnedSeconds ?? 0)
        default: return L.percent(r.accuracyPercent)
        }
    }

    private func when(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return L.today + " " + d.formatted(date: .omitted, time: .shortened) }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }

    private func load() async {
        loading = true
        await history.sync()
        await log.sync()
        server = await DrillServer.fetchSessions()
        loading = false
    }

    private var source: String {
        if loading { return L.syncing }
        return server != nil ? L.allDevices : L.thisPhoneOnly
    }

    private var drillIDs: [String] {
        var seen = Set<String>()
        var ids = pa.exercises.map(\.id).filter { id in results.contains { $0.exerciseID == id } || pa.unscoredSeconds[id] != nil }
        ids.forEach { seen.insert($0) }
        for r in results where seen.insert(r.exerciseID).inserted { ids.append(r.exerciseID) }
        return ids
    }

    private func name(_ id: String) -> String {
        if let e = pa.exercises.first(where: { $0.id == id }) { return e.short.isEmpty ? e.name : e.short }
        return results.first { $0.exerciseID == id }?.exerciseName ?? id
    }

    private func best(_ id: String) -> Int? {
        results.filter { $0.exerciseID == id && !$0.guided && $0.mode != "endurance" && $0.mode != "challenge" }.map(\.accuracyPercent).max()
    }
}

/// One drill's progress: his max big, how the tempo he reaches has moved, the best run at each tempo, and the time
/// played with the audio input off.
struct DrillProgressView: View {
    let exerciseID: String
    let results: [SessionResult]
    @EnvironmentObject var pa: PlayAlong

    var body: some View {
        let solo = results.filter { $0.exerciseID == exerciseID && !$0.guided }.sorted { $0.date < $1.date }
        let bests = Stats.bests(results).filter { $0.exerciseID == exerciseID }
        let reached = solo.map { Double($0.topBPM) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(pa.level(exerciseID).map { "\($0)" } ?? "–").font(Typo.statLarge).foregroundStyle(Theme.text)
                    Text(L.bpmMax).font(Typo.body).foregroundStyle(Theme.muted)
                }
                .padding(.top, Space.sm)
                if reached.count >= 2 {
                    Sparkline(values: reached).frame(height: 56).padding(.top, Space.md)
                        .accessibilityLabel(L.tempoTrendLabel)
                        .accessibilityValue(L.tempoTrend(Int(reached.min() ?? 0), Int(reached.max() ?? 0)))
                }
                ColumnHeads(first: L.tempo, columns: [(L.best, 64), (L.date, 72)])
                    .padding(.horizontal, -Space.page).padding(.top, Space.lg)
                Hairline()
                ForEach(bests, id: \.self) { b in
                    TableRow(name: "\(b.bpm) \(L.bpm), \(L.modeName(b.mode))",
                             values: [(b.mode == "endurance" || b.mode == "challenge" ? formatClock(b.value) : L.percent(Int(b.value)), 64),
                                      (b.last.formatted(.dateTime.month(.abbreviated).day()), 72)], faintValues: true)
                        .padding(.horizontal, -Space.page)
                    Hairline()
                }
                if let secs = pa.unscoredSeconds[exerciseID], secs > 0 {
                    HStack {
                        Text(L.unscoredTime).font(Typo.body)
                        Spacer()
                        Text(formatMinutes(secs)).font(Typo.figure(.body)).foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: Control.row)
                    .overlay(alignment: .bottom) { Hairline() }
                }
            }
            .padding(.horizontal, Space.page)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(pa.exercises.first { $0.id == exerciseID }?.short ?? L.progress)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A saved run, read only: the result screen without its button.
struct SavedRunView: View {
    let result: SessionResult
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(L.resultSummary(guided: result.guided, start: result.startBPM, top: result.topBPM, seconds: result.seconds))
                    .font(Typo.sub).foregroundStyle(Theme.muted).padding(.top, Space.sm)
                Text(result.date.formatted(date: .abbreviated, time: .shortened)).font(Typo.foot).foregroundStyle(Theme.faint)
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(result.mode == "challenge" ? formatClock(result.earnedSeconds ?? 0)
                         : result.mode == "endurance" ? formatClock(result.sustainedSeconds ?? 0) : L.percent(result.accuracyPercent))
                        .font(Typo.statLarge)
                    Text(L.modeName(result.mode)).font(Typo.body).foregroundStyle(Theme.muted)
                }
                if let steps = result.tempoSteps, steps.count > 1 {
                    ColumnHeads(first: L.tempo, columns: [(L.time, 64), (L.accuracy, 72)]).padding(.horizontal, -Space.page).padding(.top, Space.md)
                    Hairline()
                    ForEach(steps.indices, id: \.self) { i in
                        let s = steps[i]
                        TableRow(name: s.rest == true ? L.breakTitle : "\(s.bpm)",
                                 values: [(formatClock(s.seconds), 64), (s.accuracy.map { L.percent($0) } ?? "–", 72)], faintValues: true)
                            .padding(.horizontal, -Space.page)
                        Hairline()
                    }
                }
                ForEach(rows.indices, id: \.self) { i in
                    HStack {
                        Text(rows[i].0)
                        Spacer()
                        Text(rows[i].1).font(Typo.figure(.body)).foregroundStyle(Theme.muted)
                    }
                    .frame(minHeight: Control.row)
                    .overlay(alignment: .bottom) { Hairline() }
                }
            }
            .padding(.horizontal, Space.page)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(result.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var rows: [(String, String)] {
        var out: [(String, String)] = [(L.accuracy, L.percent(result.accuracyPercent)),
                                       (L.spread, L.ms(Int(result.spreadMs.rounded()))),
                                       (L.missed, L.ofTotal(result.missed, result.notes)),
                                       (L.extraNotes, "\(result.extra)")]
        if let e = result.elapsedSeconds { out.append((L.elapsed, formatClock(e))) }
        if let b = result.bestStreakSeconds { out.append((L.bestStreak, formatClock(b))) }
        if let w = result.wrongPitch { out.append((L.wrongNotes, "\(w)")) }
        if let d = result.device { out.append((L.device, d)) }
        return out
    }
}

/// A small line of values in order, the last one marked.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
            let range = Swift.max(1, hi - lo)
            let inset: CGFloat = 4
            func point(_ i: Int) -> CGPoint {
                let x = inset + (size.width - inset * 2) * CGFloat(i) / CGFloat(values.count - 1)
                let y = size.height - inset - (size.height - inset * 2) * CGFloat((values[i] - lo) / range)
                return CGPoint(x: x, y: y)
            }
            var path = Path()
            path.move(to: point(0))
            for i in 1..<values.count { path.addLine(to: point(i)) }
            ctx.stroke(path, with: .color(Theme.accentText), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            let last = point(values.count - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(Theme.accentText))
        }
    }
}
