import SwiftUI

/// Routines (Joe, 2026-11-24: "let's build a Routines section where we can interval out warm ups, drills, breaks,
/// etc."): a plain table of his routines (name, blocks, about how long). Plus makes a new one and opens it. Swipe
/// left deletes (it asks once), swipe right duplicates. The same routines are on the computer (the drill server).
struct RoutinesView: View {
    @EnvironmentObject var store: PracticeRoutineStore
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var runner: RoutineRunner
    @State private var path: [String] = []
    @State private var deleting: PracticeRoutine?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                RunningBar()
                List {
                    Section {
                        ForEach(store.routines) { r in
                            Button { path.append(r.id) } label: {
                                TableRow(name: r.name, values: [("\(r.blocks.count)", 44), (L.minutes(r.estimate(drills: pa.exercises)), 64)],
                                         faintValues: true)
                                    .padding(.horizontal, -Space.page)
                            }
                            .buttonStyle(PressStyle())
                            .listRowInsets(EdgeInsets(top: 0, leading: Space.page, bottom: 0, trailing: Space.page))
                            .listRowBackground(Theme.bg)
                            .swipeActions(edge: .trailing) {
                                Button(L.delete, role: .destructive) { deleting = r }
                            }
                            .swipeActions(edge: .leading) {
                                Button(L.duplicate) { store.duplicate(r.id) }.tint(Theme.accentText)
                            }
                            .accessibilityIdentifier("routine.\(r.name)")
                        }
                    } header: {
                        ColumnHeads(first: L.columnRoutine, columns: [(L.columnBlocks, 44), (L.time, 64)])
                            .padding(.horizontal, -Space.page)
                            .textCase(nil)
                    }
                    if store.routines.isEmpty {
                        Text(L.noRoutines).font(Typo.sub).foregroundStyle(Theme.muted).listRowBackground(Theme.bg)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await store.sync() }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(L.routines)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(store.newRoutine(drills: pa.exercises).id) } label: { Image(systemName: "plus") }
                        .accessibilityLabel(L.newRoutine)
                        .accessibilityIdentifier("routines.add")
                }
                ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            }
            .navigationDestination(for: String.self) { id in RoutineEditorView(routineID: id, path: $path) }
            .confirmationDialog(L.deleteRoutineQuestion, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button(L.delete, role: .destructive) { if let d = deleting { store.delete(d.id) }; deleting = nil }
                Button(L.cancel, role: .cancel) { deleting = nil }
            }
            .task { await store.sync() }
        }
    }
}

/// A routine: always editable. A table of its blocks (block, tempo, length), drag to reorder, swipe to delete or
/// duplicate, Add block last, and Start at the bottom. Each change is saved as it is made.
struct RoutineEditorView: View {
    let routineID: String
    @Binding var path: [String]
    @EnvironmentObject var store: PracticeRoutineStore
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var runner: RoutineRunner
    @State private var renaming = false
    @State private var name = ""
    @State private var editing: String?
    @State private var confirmDelete = false

    private var routine: PracticeRoutine? { store.routine(routineID) }

    var body: some View {
        Group {
            if let r = routine {
                List {
                    Section {
                        ForEach(r.blocks) { b in
                            Button { editing = b.id } label: {
                                TableRow(name: b.title(drills: pa.exercises), values: [(tempoText(b), 84), (lengthText(b), 72)], faintValues: true)
                                    .padding(.horizontal, -Space.page)
                            }
                            .buttonStyle(PressStyle())
                            .listRowInsets(EdgeInsets(top: 0, leading: Space.page, bottom: 0, trailing: Space.page))
                            .listRowBackground(Theme.bg)
                            .swipeActions(edge: .trailing) {
                                Button(L.delete, role: .destructive) { update { $0.blocks.removeAll { $0.id == b.id } } }
                            }
                            .swipeActions(edge: .leading) {
                                Button(L.duplicate) { duplicateBlock(b.id) }.tint(Theme.accentText)
                            }
                            .accessibilityIdentifier("block.\(b.kind.rawValue)")
                        }
                        .onMove { from, to in
                            update { $0.blocks.move(fromOffsets: from, toOffset: to) }
                            Haptics.tick()
                        }
                        Menu {
                            Button(L.warmUp) { add(.warmup) }
                            Button(L.drill) { add(.drill) }
                            Button(L.breakTitle) { add(.rest) }
                            Button(L.openPractice) { add(.free) }
                            Button(L.customBlock) { add(.custom) }
                        } label: {
                            Text(L.addBlock).font(Typo.body).foregroundStyle(Theme.accentText).frame(minHeight: Control.row)
                        }
                        .listRowBackground(Theme.bg)
                        .accessibilityIdentifier("routine.addBlock")
                    } header: {
                        ColumnHeads(first: L.columnBlock, columns: [(L.tempo, 84), (L.length, 72)])
                            .padding(.horizontal, -Space.page).textCase(nil)
                    } footer: {
                        Text(L.blocksAbout(r.blocks.count, formatMinutes(r.estimate(drills: pa.exercises))))
                            .font(Typo.foot).foregroundStyle(Theme.muted)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.inactive))
                .safeAreaInset(edge: .bottom) {
                    PrimaryButton(title: L.start, systemImage: "play.fill", enabled: !r.blocks.isEmpty) {
                        runner.start(r, drills: pa.exercises)
                    }
                    .accessibilityIdentifier("routine.start")
                    .padding(.horizontal, Space.page).padding(.top, Space.sm).padding(.bottom, Space.xs)
                    .background(Theme.bg.overlay(alignment: .top) { Hairline() }.ignoresSafeArea(edges: .bottom))
                }
                .navigationTitle(r.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(L.rename) { name = r.name; renaming = true }
                            Button(L.duplicate) { if let c = store.duplicate(r.id) { path = [c.id] } }
                            Button(L.delete, role: .destructive) { confirmDelete = true }
                        } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel(L.more)
                    }
                }
                .alert(L.rename, isPresented: $renaming) {
                    TextField(L.name, text: $name)
                    Button(L.save) { let n = name.trimmingCharacters(in: .whitespaces); if !n.isEmpty { update { $0.name = n } } }
                    Button(L.cancel, role: .cancel) {}
                }
                .confirmationDialog(L.deleteRoutineQuestion, isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button(L.delete, role: .destructive) { store.delete(r.id); path.removeAll() }
                    Button(L.cancel, role: .cancel) {}
                }
                .navigationDestination(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                    if let id = editing { BlockEditorView(routineID: routineID, blockID: id) }
                }
            } else {
                Text(L.noRoutines).font(Typo.sub).foregroundStyle(Theme.muted)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func update(_ change: (inout PracticeRoutine) -> Void) {
        guard var r = routine else { return }
        change(&r)
        store.save(r)
    }

    private func add(_ kind: RoutineBlock.Kind) {
        let b = RoutineBlock.new(kind, drills: pa.exercises)
        update { $0.blocks.append(b) }
        editing = b.id
    }

    private func duplicateBlock(_ id: String) {
        update { r in
            guard let i = r.blocks.firstIndex(where: { $0.id == id }) else { return }
            var c = r.blocks[i]
            c.id = UUID().uuidString.lowercased()
            r.blocks.insert(c, at: i + 1)
        }
    }

    private func tempoText(_ b: RoutineBlock) -> String {
        switch b.kind {
        case .drill:
            guard let d = b.drill else { return "" }
            let p = d.session.tempoPlan
            if p.mode != .off, let ex = pa.exercises.first(where: { $0.id == b.drillID }) {
                return L.tempoRange(d.bpm, p.normalized.bounds(start: d.bpm, rule: ex.tempo).top)
            }
            return "\(d.bpm)"
        case .rest: return ""
        default: return b.click ? "\(b.bpm)" : ""
        }
    }

    private func lengthText(_ b: RoutineBlock) -> String {
        guard b.kind == .drill, let s = b.drill?.session else { return formatClock(Double(b.seconds)) }
        switch s.kind {
        case .cycles, .routine: return L.loopCount(s.cycles)
        case .duration: return formatClock(Double(s.seconds))
        case .endurance: return L.holdShort
        case .challenge: return formatClock(Double(s.seconds))
        }
    }
}

/// One block of a routine. Changes save as they are made. A drill block has the drill's own setup groups.
struct BlockEditorView: View {
    let routineID: String
    let blockID: String
    @EnvironmentObject var store: PracticeRoutineStore
    @EnvironmentObject var pa: PlayAlong
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var block: RoutineBlock? { store.routine(routineID)?.blocks.first { $0.id == blockID } }

    private func set(_ change: @escaping (inout RoutineBlock) -> Void) {
        guard var r = store.routine(routineID), let i = r.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        change(&r.blocks[i])
        store.save(r)
    }

    private func binding<T>(_ key: WritableKeyPath<RoutineBlock, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { block?[keyPath: key] ?? fallback }, set: { v in set { $0[keyPath: key] = v } })
    }

    var body: some View {
        Group {
            if let b = block {
                if b.kind == .drill { drillEditor(b) } else { plainEditor(b) }
            }
        }
        .navigationTitle(block.map { L.blockKind($0.kind) } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L.deleteBlockQuestion, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L.delete, role: .destructive) {
                guard var r = store.routine(routineID) else { return }
                r.blocks.removeAll { $0.id == blockID }
                store.save(r)
                dismiss()
            }
            Button(L.cancel, role: .cancel) {}
        }
    }

    private func plainEditor(_ b: RoutineBlock) -> some View {
        Form {
            Section {
                LabeledContent(L.name) {
                    TextField(b.title(), text: binding(\.name, "")).multilineTextAlignment(.trailing)
                }
                Stepper(value: binding(\.seconds, 60), in: (b.kind == .rest ? 15 : 30)...1800, step: b.kind == .rest ? 15 : 30) {
                    LabeledContent(L.length) { Text(formatClock(Double(b.seconds))).font(Typo.figure(.body)) }
                }
                if b.kind != .rest {
                    Toggle(L.click, isOn: binding(\.click, false)).tint(Theme.accent)
                    if b.click {
                        Stepper(value: binding(\.bpm, 80), in: 30...300) {
                            LabeledContent(L.tempo) { Text(L.bpmValue(b.bpm)).font(Typo.figure(.body)) }
                        }
                    }
                }
            }
            actions
        }
        .houseForm()
    }

    private func drillEditor(_ b: RoutineBlock) -> some View {
        let ex = pa.exercises.first { $0.id == b.drillID } ?? pa.exercises.first ?? .fallback
        let setup = b.drill ?? DrillSetup(bpm: ex.tempo.start)
        func setDrill(_ change: @escaping (inout DrillSetup) -> Void) {
            set { blk in
                var d = blk.drill ?? setup
                change(&d)
                blk.drill = d
                if blk.drillID == nil { blk.drillID = ex.id }
            }
        }
        return VStack(spacing: 0) {
            if pa.exercises.count > 1 {
                Form {
                    Section {
                        Picker(L.drill, selection: binding(\.drillID, ex.id as String?)) {
                            ForEach(pa.exercises) { Text($0.short.isEmpty ? $0.name : $0.short).tag(Optional($0.id)) }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }
                .houseForm()
                .frame(height: 100)
            }
            DrillSetupForm(exercise: ex,
                           bpm: Binding(get: { block?.drill?.bpm ?? setup.bpm }, set: { v in setDrill { $0.bpm = v } }),
                           session: Binding(get: { block?.drill?.session ?? setup.session }, set: { v in setDrill { $0.session = v } }),
                           guided: Binding(get: { block?.drill?.guided ?? setup.guided }, set: { v in setDrill { $0.guided = v } }),
                           audioInput: Binding(get: { block?.drill?.audioInput ?? setup.audioInput }, set: { v in setDrill { $0.audioInput = v } }),
                           intro: .constant(false), zones: false)
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: Space.lg) {
                        Button(L.duplicate) { duplicateSelf() }.foregroundStyle(Theme.accentText)
                        Button(L.delete) { confirmDelete = true }.foregroundStyle(Theme.danger)
                        Spacer()
                    }
                    .font(Typo.body)
                    .frame(minHeight: Control.row)
                    .padding(.horizontal, Space.page)
                    .background(Theme.side.overlay(alignment: .top) { Hairline() }.ignoresSafeArea(edges: .bottom))
                }
        }
    }

    private var actions: some View {
        Section {
            Button(L.duplicate) { duplicateSelf() }.foregroundStyle(Theme.accentText)
            Button(L.delete) { confirmDelete = true }.foregroundStyle(Theme.danger)
        }
    }

    private func duplicateSelf() {
        guard var r = store.routine(routineID), let i = r.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        var c = r.blocks[i]
        c.id = UUID().uuidString.lowercased()
        r.blocks.insert(c, at: i + 1)
        store.save(r)
        dismiss()
    }
}
