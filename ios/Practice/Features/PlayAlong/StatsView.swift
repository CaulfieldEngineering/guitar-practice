import SwiftUI

/// Progress: the best run at each tempo, per exercise and kind of run, and the latest runs. From the mini PC when it
/// can be reached (every device's runs), otherwise the phone's own copy.
struct StatsView: View {
    @EnvironmentObject var history: History
    @EnvironmentObject var pa: PlayAlong
    @Environment(\.dismiss) private var dismiss
    @State private var server: [SessionResult]?
    @State private var loading = true

    private var results: [SessionResult] { server ?? history.results }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(source).font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.bg)

                ForEach(exerciseIDs, id: \.self) { id in
                    Section {
                        ForEach(Stats.bests(results).filter { $0.exerciseID == id }, id: \.self) { b in
                            HStack {
                                Text("\(b.bpm) bpm").monospacedDigit().foregroundStyle(Theme.text)
                                Text(modeName(b.mode)).foregroundStyle(Theme.muted)
                                Spacer()
                                Text(b.mode == "endurance" ? formatClock(b.value) : "\(Int(b.value))").monospacedDigit().foregroundStyle(Theme.text)
                                Text("\(b.runs) run\(b.runs == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Theme.faint)
                                    .frame(width: 56, alignment: .trailing)
                            }
                            .font(.system(size: 15))
                        }
                    } header: { Text(name(id)) }
                    .listRowBackground(Theme.bg)
                }

                Section {
                    ForEach(results.prefix(30)) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(r.exerciseName).foregroundStyle(Theme.text)
                                Spacer()
                                Text(r.mode == "endurance" ? formatClock(r.sustainedSeconds ?? 0) : "\(r.score)").monospacedDigit().foregroundStyle(Theme.text)
                            }
                            .font(.system(size: 15))
                            Text("\(r.date.formatted(date: .abbreviated, time: .shortened)), \(r.startBPM)\(r.topBPM > r.startBPM ? " to \(r.topBPM)" : "") bpm, \(modeName(r.mode))\(r.guided ? ", guided" : ""), \(r.accuracyPercent)% within \(Int(r.toleranceMs)) ms")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                } header: { Text("Latest runs") }
                .listRowBackground(Theme.bg)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        await history.sync()
        server = await DrillServer.fetchSessions()
        loading = false
    }

    private var source: String {
        if loading { return "Checking the mini PC." }
        if server != nil { return "From the mini PC, every run. \(history.pendingCount == 0 ? "Everything is sent." : "\(history.pendingCount) still to send.")" }
        return "The mini PC is out of reach: the runs on this phone. \(history.pendingCount) to send when it is back."
    }

    private var exerciseIDs: [String] {
        var seen = Set<String>()
        return results.map(\.exerciseID).filter { seen.insert($0).inserted }
    }

    private func name(_ id: String) -> String {
        pa.exercises.first { $0.id == id }?.name ?? results.first { $0.exerciseID == id }?.exerciseName ?? id
    }

    private func modeName(_ m: String) -> String {
        switch m { case "endurance": return "endurance"; case "duration": return "timed"; default: return "cycles" }
    }
}
