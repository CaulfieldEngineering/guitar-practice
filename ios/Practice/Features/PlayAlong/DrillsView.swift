import SwiftUI

/// Where a row of the Drills list leads.
enum DrillRoute: Hashable {
    case exercise(String)
    case routine(UUID)
}

/// Drills: everything to practise in one list (Joe, 2026-11-14: "intervals and play along can just be combined into
/// Drills"). The picking drills first, each opening its own setup screen; then the timed routines (blocks of play and
/// rest at set tempos), each opening ready to run.
struct DrillsView: View {
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var store: RoutineStore
    @State private var path: [DrillRoute] = []
    @State private var showStats = false
    @State private var editing: Routine?
    @State private var deleting: Routine?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScreenHeader(title: "Drills") {
                    BarIcon(systemImage: "chart.xyaxis.line", label: "Progress") { showStats = true }
                        .accessibilityIdentifier("progress")
                }
                ScrollView {
                    VStack(spacing: 0) {
                        SectionLabel("Picking drills")
                            .padding(.top, Space.xs).padding(.bottom, Space.xxs)
                        ForEach(pa.exercises) { ex in
                            Button {
                                pa.select(ex.id)
                                path.append(.exercise(ex.id))
                            } label: { exerciseRow(ex) }
                            .buttonStyle(PressStyle())
                            .accessibilityIdentifier("exercise.\(ex.id)")
                        }

                        HStack {
                            SectionLabel("Timed routines")
                            Button {
                                editing = Routine(name: "New routine", intervals: [Interval(.play, 60, bpm: 100), Interval(.rest, 30)], rounds: 4, stepBPM: 4)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: Space.touch, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("New routine")
                        }
                        .padding(.top, Space.xl)
                        if store.routines.isEmpty {
                            Text("No routines yet. The plus adds one; Settings puts the starters back.")
                                .font(Typo.sub).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Space.sm)
                        }
                        ForEach(store.routines) { r in
                            routineRow(r)
                        }

                        if let note = pa.catalogNote {
                            Text(note).font(Typo.foot).foregroundStyle(Theme.faint)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Space.md)
                        }
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.bottom, Space.xl)
                }
                .refreshable { await pa.refresh() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DrillRoute.self) { route in
                switch route {
                case .exercise:
                    ExerciseView()
                case .routine(let id):
                    if let r = store.routines.first(where: { $0.id == id }) { RunnerView(routine: r) }
                }
            }
        }
        .sheet(isPresented: $showStats) { StatsView() }
        .sheet(item: $editing) { r in
            RoutineEditor(routine: r) { saved in store.upsert(saved) }
        }
        .confirmationDialog("Delete this routine?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let r = deleting { store.delete(r) }
                deleting = nil
            }
            Button("Keep it", role: .cancel) { deleting = nil }
        }
        .task { await pa.refresh() }
    }

    private func exerciseRow(_ ex: Exercise) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(ex.name).font(Typo.title).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                    Text(ex.detail).font(Typo.sub).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: Space.xs)
                if let t = trailing(ex) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(t.value).font(Typo.figure(.subheadline, weight: .medium)).foregroundStyle(Theme.text)
                        Text(t.label).font(Typo.caption).foregroundStyle(Theme.faint)
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.faint)
            }
            .padding(.vertical, Space.sm)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
            Hairline()
        }
    }

    /// A quiet note on the right: his max on the drill, else the tempo last set.
    private func trailing(_ ex: Exercise) -> (value: String, label: String)? {
        if let m = pa.serverLevels[ex.id] ?? pa.fastestPass(ex.id) { return ("\(m)", "max bpm") }
        if let t = UserDefaults.standard.object(forKey: "pa.bpm.\(ex.id)") as? Int { return ("\(t)", "bpm") }
        return nil
    }

    private func routineRow(_ r: Routine) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.xxs) {
                Button { path.append(.routine(r.id)) } label: {
                    HStack(spacing: Space.sm) {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(r.name).font(Typo.title).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                            Text(routineDetail(r)).font(Typo.sub).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer(minLength: Space.xs)
                        Text(formatClock(r.plan.total)).font(Typo.figure(.subheadline, weight: .medium)).foregroundStyle(Theme.text)
                    }
                    .padding(.vertical, Space.sm)
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("routine.\(r.name)")
                Menu {
                    Button { editing = r } label: { Label("Edit", systemImage: "pencil") }
                    Button { store.duplicate(r) } label: { Label("Make a copy", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { deleting = r } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 36, height: Space.touch)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More for \(r.name)")
            }
            Hairline()
        }
    }

    /// "8 rounds, 100 to 128 bpm" (the length is on the right).
    private func routineDetail(_ r: Routine) -> String {
        var parts: [String] = []
        if r.rounds > 1 { parts.append("\(r.rounds) rounds") }
        let tempos = r.plan.segments.filter { $0.kind == .play }.map { Int($0.bpm) }
        if let lo = tempos.min(), let hi = tempos.max() { parts.append(lo == hi ? "\(lo) bpm" : "\(lo) to \(hi) bpm") }
        let count = r.intervals.count
        parts.append("\(count) block\(count == 1 ? "" : "s")")
        return parts.joined(separator: ", ")
    }
}
