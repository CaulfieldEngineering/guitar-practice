import SwiftUI

struct RoutinesView: View {
    @EnvironmentObject var store: RoutineStore
    @EnvironmentObject var player: Player
    @State private var path: [UUID] = []
    @State private var editing: Routine?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScreenHeader(title: "Intervals") {
                    Button {
                        editing = Routine(name: "New routine", intervals: [Interval(.play, 60, bpm: 100), Interval(.rest, 30)], rounds: 4, stepBPM: 4)
                    } label: {
                        Image(systemName: "plus").font(.system(size: 18)).foregroundStyle(Theme.muted).frame(width: 36, height: 36)
                    }.buttonStyle(.plain)
                }
                List {
                    ForEach(store.routines) { r in
                        Button { path.append(r.id) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.text)
                                Text(r.summary).font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.bg)
                        .listRowSeparatorTint(Theme.line)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { store.delete(r) } label: { Label("Delete", systemImage: "trash") }
                            Button { store.duplicate(r) } label: { Label("Copy", systemImage: "plus.square.on.square") }.tint(Theme.faint)
                            Button { editing = r } label: { Label("Edit", systemImage: "pencil") }.tint(Theme.accent)
                        }
                    }
                    .onMove { store.routines.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let r = store.routines.first(where: { $0.id == id }) { RunnerView(routine: r) }
            }
        }
        .sheet(item: $editing) { r in
            RoutineEditor(routine: r) { saved in store.upsert(saved) }
        }
    }
}
