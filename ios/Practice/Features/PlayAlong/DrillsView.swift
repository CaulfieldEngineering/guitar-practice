import SwiftUI

/// Drills: a plain table, one line a drill (Joe, on 0.1.6: "a table of some kind?"): the name, his max, his best
/// accuracy. Only the drills the catalog offers (one since 2026-11-24, "Let's remove all drills for now except for
/// 'Triplets to 16th's, 4+4'"); the table is the same when more come back. A section label only with two groups or
/// more.
struct DrillsView: View {
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var history: History
    @EnvironmentObject var player: Player
    @State private var path: [String] = []

    private let maxWidth: CGFloat = 48
    private let bestWidth: CGFloat = 52

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                RunningBar(own: .playAlong)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ColumnHeads(first: L.columnDrill, columns: [(L.columnMax, maxWidth), (L.columnBest, bestWidth)])
                        Hairline()
                        let groups = self.groups
                        ForEach(groups) { group in
                            if groups.count > 1 {
                                Text(group.name).font(Typo.foot).foregroundStyle(Theme.muted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, Space.page).padding(.top, Space.md).padding(.bottom, Space.xxs)
                            }
                            ForEach(group.drills) { ex in
                                Button {
                                    pa.select(ex.id)
                                    path.append(ex.id)
                                } label: {
                                    TableRow(name: ex.short.isEmpty ? ex.name : ex.short,
                                             values: [(pa.level(ex.id).map { "\($0)" } ?? "–", maxWidth),
                                                      (best(ex.id).map { L.percent($0) } ?? "–", bestWidth)])
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityIdentifier("exercise.\(ex.id)")
                                Hairline().padding(.leading, Space.page)
                            }
                        }
                        if pa.exercises.isEmpty {
                            Text(L.noDrills).font(Typo.sub).foregroundStyle(Theme.muted).padding(.top, Space.lg)
                        }
                        #if DEBUG
                        // For the UI test: whether anything is making sound.
                        Text(player.mode == .idle ? "stopped" : "running")
                            .font(.system(size: 4)).foregroundStyle(Color.clear)
                            .accessibilityIdentifier("engine.state")
                        #endif
                        if let note = pa.catalogNote {
                            Text(note).font(Typo.foot).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Space.page).padding(.top, Space.sm)
                        }
                    }
                }
                .refreshable { await pa.refresh() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(L.drills)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
            .navigationDestination(for: String.self) { id in
                DrillView().onAppear { pa.select(id) }
            }
            .task { await pa.refresh() }
        }
    }

    private var visible: [Exercise] {
        pa.exercises.filter { !$0.isRoutine }
    }

    private struct DrillGroup: Identifiable { var name: String; var drills: [Exercise]; var id: String { name } }

    private var groups: [DrillGroup] {
        var order: [String] = []
        var by: [String: [Exercise]] = [:]
        for e in visible {
            if by[e.category] == nil { order.append(e.category) }
            by[e.category, default: []].append(e)
        }
        return order.map { DrillGroup(name: $0, drills: by[$0] ?? []) }
    }

    /// His best accuracy on a drill (solo runs scored by accuracy).
    private func best(_ id: String) -> Int? {
        let v = history.results.filter { $0.exerciseID == id && !$0.guided && $0.mode != "endurance" && $0.mode != "challenge" }
            .map(\.accuracyPercent).max()
        return v
    }
}
