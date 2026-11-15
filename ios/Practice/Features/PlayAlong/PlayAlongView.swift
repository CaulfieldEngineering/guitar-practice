import SwiftUI

/// The drills: a plain list. Tapping one opens its own screen, where the run is set up and started.
struct PlayAlongView: View {
    @EnvironmentObject var pa: PlayAlong
    @State private var path: [String] = []
    @State private var showStats = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScreenHeader(title: "Play along") {
                    Button { showStats = true } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 17)).foregroundStyle(Theme.muted)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Progress")
                    .accessibilityIdentifier("progress")
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(pa.exercises) { ex in
                            Button {
                                pa.select(ex.id)
                                path.append(ex.id)
                            } label: { row(ex) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("exercise.\(ex.id)")
                        }
                        if let note = pa.catalogNote {
                            Text(note).font(.system(size: 12)).foregroundStyle(Theme.faint)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 20)
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

    private func row(_ ex: Exercise) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ex.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(ex.detail).font(.system(size: 14)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let detail = trailing(ex) {
                    Text(detail).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.faint)
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.faint)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    /// A quiet note on the right: the fastest passing tempo, else the tempo last set.
    private func trailing(_ ex: Exercise) -> String? {
        if let f = pa.fastestPass(ex.id) { return "\(f) bpm" }
        if let t = UserDefaults.standard.object(forKey: "pa.bpm.\(ex.id)") as? Int { return "\(t) bpm" }
        return nil
    }
}
