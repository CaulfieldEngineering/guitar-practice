import SwiftUI

struct RoutineEditor: View {
    @State var routine: Routine
    let onSave: (Routine) -> Void
    @Environment(\.dismiss) private var dismiss

    init(routine: Routine, onSave: @escaping (Routine) -> Void) {
        _routine = State(initialValue: routine)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $routine.name)
                } header: { Text("Name") }

                Section {
                    ForEach($routine.intervals) { $iv in
                        IntervalRow(interval: $iv)
                    }
                    .onDelete { routine.intervals.remove(atOffsets: $0) }
                    .onMove { routine.intervals.move(fromOffsets: $0, toOffset: $1) }
                    Menu {
                        Button("Play") { routine.intervals.append(Interval(.play, 60, bpm: routine.intervals.last(where: { $0.kind == .play })?.bpm ?? 100)) }
                        Button("Rest") { routine.intervals.append(Interval(.rest, 30)) }
                        Button("No click") { routine.intervals.append(Interval(.motion, 120)) }
                    } label: { Label("Add interval", systemImage: "plus") }
                } header: { Text("Intervals") } footer: {
                    Text("A bell starts each play interval, a lower one each rest, and the last bar of a rest counts you in.")
                }

                Section {
                    Stepper("Rounds: \(routine.rounds)", value: $routine.rounds, in: 1...50)
                    Stepper("Faster each round: +\(routine.stepBPM) bpm", value: $routine.stepBPM, in: -20...30)
                } header: { Text("Repeat") }

                Section {
                    Picker("Beats in a bar", selection: $routine.beatsPerBar) {
                        ForEach(meterOptions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Clicks per beat", selection: $routine.subdivision) {
                        ForEach(subdivisionOptions.indices, id: \.self) { i in
                            Text(subdivisionOptions[i].1).tag(subdivisionOptions[i].0)
                        }
                    }
                    Picker("Count-in", selection: $routine.countInBeats) {
                        Text("None").tag(0)
                        Text("2 beats").tag(2)
                        Text("4 beats").tag(4)
                        Text("8 beats").tag(8)
                    }
                } header: { Text("Feel") }

                Section {
                    TextField("Notes", text: $routine.notes, axis: .vertical)
                } header: { Text("Notes") } footer: { Text(routine.summary) }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.side.ignoresSafeArea())
            .tint(Theme.accent)
            .navigationTitle("Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(routine); dismiss() }.fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
        }
    }
}

private struct IntervalRow: View {
    @Binding var interval: Interval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $interval.kind) {
                Text("Play").tag(Interval.Kind.play)
                Text("Rest").tag(Interval.Kind.rest)
                Text("No click").tag(Interval.Kind.motion)
            }
            .pickerStyle(.segmented)
            TextField("Label (optional)", text: $interval.label).font(.system(size: 14))
            Stepper("Length: \(formatClock(Double(interval.seconds)))", value: $interval.seconds, in: 5...1800, step: 5)
            if interval.kind == .play {
                Stepper("Tempo: \(interval.bpm) bpm", value: $interval.bpm, in: 20...400)
            }
        }
        .padding(.vertical, 4)
    }
}
