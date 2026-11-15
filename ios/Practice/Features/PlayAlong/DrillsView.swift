import SwiftUI

/// Drills: a table, one line a drill (Joe, on 0.1.6: "the lists still need a big cleanup. Like a table of some
/// kind?"). Columns: the name, the pattern in a few characters, his max, when it was last played, his best
/// accuracy. Grouped by kind under small headers. What a drill is, in words, is on its own screen.
/// Timed routines are out of the app for now (Joe, 2026-11-14: "Let's omit the timed routines for now and just focus
/// on the drills themselves. We'll build in routines later"); a drill made of timed blocks is left out of the list.
struct DrillsView: View {
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var history: History
    @EnvironmentObject var player: Player
    @State private var path: [String] = []
    @State private var showStats = false
    @State private var query = ""
    @AppStorage("drills.sort") private var sort = "catalog"

    private static let sectionOrder = ["Picking", "Speed", "Accents"]
    // The name takes what is left (Joe, on 0.1.9: "We can allocate more room to the title"): the pattern is a
    // narrow fixed column, the two numbers are compact, and when it was last played is a small line under the name.
    private let patternWidth: CGFloat = 54
    private let maxWidth: CGFloat = 34
    private let bestWidth: CGFloat = 42

    /// What the table shows for one drill.
    private struct Line: Identifiable {
        var id: String
        var name: String
        var full: String
        var category: String
        var glyph: String
        var max: Int?
        var last: Date?
        var best: Int?
        var order: Int
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScreenHeader(title: L.drills) {
                    Menu {
                        Picker(L.sort, selection: $sort) {
                            Text(L.sortDefault).tag("catalog")
                            Text(L.sortRecent).tag("recent")
                            Text(L.sortMax).tag("max")
                            Text(L.sortName).tag("name")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(sort == "catalog" ? Theme.muted : Theme.accentText)
                            .frame(width: Space.touch, height: Space.touch)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L.sort)
                    .accessibilityIdentifier("sort")
                    BarIcon(systemImage: "chart.xyaxis.line", label: L.progress) { showStats = true }
                        .accessibilityIdentifier("progress")
                }
                RunningBar(own: .playAlong)
                ScrollView {
                    VStack(spacing: 0) {
                        let lines = self.lines
                        if lines.count > 12 || !query.isEmpty { search }
                        columnHeads
                        ForEach(sections(lines), id: \.name) { section in
                            SectionLabel(section.name)
                                .padding(.top, Space.md).padding(.bottom, Space.xxs)
                            Hairline()
                            ForEach(section.lines) { line in
                                Button {
                                    pa.select(line.id)
                                    path.append(line.id)
                                } label: { row(line) }
                                .buttonStyle(PressStyle())
                                .accessibilityIdentifier("exercise.\(line.id)")
                                .accessibilityLabel(spoken(line))
                            }
                        }
                        if lines.isEmpty {
                            Text(query.isEmpty ? L.noDrills : L.noResults)
                                .font(Typo.sub).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Space.md)
                        }
                        if let note = pa.catalogNote {
                            Text(note).font(Typo.foot).foregroundStyle(Theme.faint)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Space.md)
                        }
                        #if DEBUG
                        // For the UI test: whether anything is making sound.
                        Text(player.mode == .idle ? "stopped" : "running")
                            .font(.system(size: 4)).foregroundStyle(Color.clear)
                            .accessibilityIdentifier("engine.state")
                        #endif
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.bottom, Space.xl)
                }
                .refreshable { await pa.refresh() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { _ in ExerciseView() }
        }
        .sheet(isPresented: $showStats) { StatsView() }
        .task { await pa.refresh() }
    }

    // MARK: The table

    private var search: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Theme.faint)
            TextField(L.search, text: $query)
                .font(Typo.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Space.sm)
        .frame(minHeight: 36)
        .background(Theme.hover, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .padding(.top, Space.xxs)
    }

    private var columnHeads: some View {
        HStack(spacing: Space.xs) {
            Text(L.columnDrill).frame(maxWidth: .infinity, alignment: .leading)
            Text(L.columnPattern).frame(width: patternWidth, alignment: .leading)
            Text(L.columnMax).frame(width: maxWidth, alignment: .trailing)
            Text(L.columnBest).frame(width: bestWidth, alignment: .trailing)
        }
        .font(Typo.caption)
        .foregroundStyle(Theme.faint)
        .lineLimit(1)
        .padding(.top, Space.xs)
        .accessibilityHidden(true)
    }

    private func row(_ l: Line) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.xs) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(l.name).font(Typo.body).foregroundStyle(Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    if let d = l.last {
                        Text(L.lastPlayed(ago(d))).font(Typo.caption).foregroundStyle(Theme.faint).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(l.glyph).font(Typo.figure(.subheadline)).foregroundStyle(Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: patternWidth, alignment: .leading)
                Text(l.max.map { "\($0)" } ?? L.none).font(Typo.figure(.subheadline, weight: .medium))
                    .foregroundStyle(l.max == nil ? Theme.faint : Theme.text)
                    .frame(width: maxWidth, alignment: .trailing)
                Text(l.best.map { L.percent($0) } ?? L.none).font(Typo.figure(.subheadline))
                    .foregroundStyle(l.best == nil ? Theme.faint : Theme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: bestWidth, alignment: .trailing)
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
            Hairline()
        }
    }

    private func spoken(_ l: Line) -> String {
        var parts = [l.full, "\(L.columnPattern) \(l.glyph)"]
        if let m = l.max { parts.append("\(L.columnMax) \(m)") }
        if let d = l.last { parts.append("\(L.columnLast) \(ago(d))") }
        if let b = l.best { parts.append("\(L.columnBest) \(L.percent(b))") }
        return parts.joined(separator: ", ")
    }

    // MARK: The lines

    /// One line a drill, with what his runs say about it: found, then sorted.
    private var lines: [Line] {
        var last: [String: Date] = [:]
        var best: [String: Int] = [:]
        for r in history.results {
            if let d = last[r.exerciseID] { if r.date > d { last[r.exerciseID] = r.date } } else { last[r.exerciseID] = r.date }
            if !r.guided { best[r.exerciseID] = Swift.max(best[r.exerciseID] ?? 0, r.accuracyPercent) }
        }
        var out: [Line] = []
        for (i, ex) in pa.exercises.enumerated() where !ex.isRoutine {
            out.append(Line(id: ex.id, name: ex.short.isEmpty ? ex.name : ex.short, full: ex.name, category: ex.category,
                            glyph: ex.glyph, max: pa.serverLevels[ex.id] ?? pa.fastestPass(ex.id),
                            last: last[ex.id], best: best[ex.id], order: i))
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty { out = out.filter { $0.full.lowercased().contains(q) || $0.name.lowercased().contains(q) } }
        switch sort {
        case "recent": out.sort { ($0.last ?? .distantPast, -$0.order) > ($1.last ?? .distantPast, -$1.order) }
        case "max": out.sort { ($0.max ?? 0, -$0.order) > ($1.max ?? 0, -$1.order) }
        case "name": out.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        default: break
        }
        return out
    }

    /// The lines under their kinds: Picking, Speed, Accents, then any other kind in the order it first appears.
    private func sections(_ lines: [Line]) -> [(name: String, lines: [Line])] {
        var names: [String] = []
        for l in lines.sorted(by: { $0.order < $1.order }) where !names.contains(l.category) { names.append(l.category) }
        let known = DrillsView.sectionOrder.filter { names.contains($0) }
        let ordered = known + names.filter { !known.contains($0) }
        return ordered.map { n in (name: n, lines: lines.filter { $0.category == n }) }
    }

    /// "now", "12m", "3h", "2d", "5w", "4mo", "2y": how long ago, in as few characters as it takes.
    private func ago(_ date: Date) -> String {
        let s = Swift.max(0, Date().timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86_400 { return "\(Int(s / 3600))h" }
        if s < 86_400 * 14 { return "\(Int(s / 86_400))d" }
        if s < 86_400 * 60 { return "\(Int(s / (86_400 * 7)))w" }
        if s < 86_400 * 365 { return "\(Int(s / (86_400 * 30)))mo" }
        return "\(Int(s / (86_400 * 365)))y"
    }
}
