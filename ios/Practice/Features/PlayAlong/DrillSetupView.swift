import SwiftUI

/// A drill's setup, set before Start (Joe, 2026-11-14: "a setting inside the exercise after you choose but before
/// you start"). On the surface: the pattern, the tempo, three value rows (Tempo zone, Ascending tempo, Length), two
/// switches (Audio input, Guide notes), Audio and Options. Everything else is one step in. Start is fixed at the
/// bottom. The same groups edit a routine's drill block (DrillSetupForm with a block's setup).
struct DrillSetupView: View {
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var audio: AudioSetup

    var body: some View {
        DrillSetupForm(exercise: pa.exercise,
                       bpm: Binding(get: { pa.startTempo }, set: { pa.nudgeTempo(to: $0) }),
                       session: $pa.session, guided: $pa.guided, audioInput: $pa.audioInput,
                       intro: $pa.intro, zones: true)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Space.xs) {
                    if let m = pa.message {
                        Text(m).font(Typo.sub).foregroundStyle(Theme.warn)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("message")
                    }
                    PrimaryButton(title: L.start, systemImage: "play.fill") { pa.start() }
                        .accessibilityIdentifier("start")
                }
                .padding(.horizontal, Space.page)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.xs)
                .background(Theme.side.overlay(alignment: .top) { Hairline() }.ignoresSafeArea(edges: .bottom))
            }
            .onAppear { pa.prepareInput(); audio.refresh() }
            .onChange(of: pa.audioInput) { _, _ in pa.prepareInput(); audio.refresh() }
    }
}

/// The setup's groups, for the drill's own screen (`zones` on: his max and its zones) and for a routine's drill
/// block (the block's own setup).
struct DrillSetupForm: View {
    let exercise: Exercise
    @Binding var bpm: Int
    @Binding var session: SessionSettings
    @Binding var guided: Bool
    @Binding var audioInput: Bool
    @Binding var intro: Bool
    /// The drill's own screen: the tempo zones of his max, the route, the calibration.
    var zones: Bool
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var audio: AudioSetup

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Space.xs) {
                    PatternStrip(exercise: exercise).frame(height: 56)
                    Text(patternLine).font(Typo.foot).foregroundStyle(Theme.muted)
                    TempoBlock(value: bpm, font: Typo.tempoSetup) { v in
                        bpm = min(max(v, exercise.tempo.min), exercise.tempo.max)
                    }
                    .padding(.top, Space.sm)
                    .accessibilityIdentifier("setup.tempo")
                    Text(tempoCaption).font(Typo.foot).foregroundStyle(Theme.muted)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: Space.page, bottom: Space.xs, trailing: Space.xs))
            }

            Section {
                if zones, let max = pa.level(exercise.id) {
                    NavigationLink {
                        ChoiceList(title: L.tempoZone, options: zoneOptions(max), selection: zoneBinding)
                    } label: { LabeledContent(L.tempoZone, value: zoneValue(max)) }
                }
                NavigationLink {
                    TempoPlanView(plan: $session.tempoPlan, start: $bpm, exercise: exercise, audioInput: $audioInput)
                } label: { LabeledContent(L.ascendingTempo, value: L.planSummary(session.tempoPlan, start: bpm, top: planTop)) }
                .accessibilityIdentifier("setup.ascending")
                NavigationLink {
                    LengthView(session: $session, audioInput: audioInput)
                } label: { LabeledContent(L.length, value: L.lengthSummary(session, scored: audioInput)) }
                .accessibilityIdentifier("setup.length")
            }

            Section {
                Toggle(L.audioInput, isOn: $audioInput).tint(Theme.accent)
                    .accessibilityIdentifier("setup.input")
                Toggle(L.guideNotes, isOn: $guided).tint(Theme.accent)
                if zones {
                    NavigationLink {
                        AudioSettingsView()
                    } label: { LabeledContent(L.audio, value: routeValue) }
                    .accessibilityIdentifier("drill.audio")
                }
            } footer: {
                if zones, audioInput, let note = pa.routeNote { Text(note).foregroundStyle(Theme.warn) }
            }

            Section {
                NavigationLink {
                    OptionsView(session: $session, audioInput: audioInput, intro: $intro, calibrate: zones)
                } label: { LabeledContent(L.options, value: L.optionsSummary(session, intro: intro)) }
                .accessibilityIdentifier("setup.options")
            }
        }
        .houseForm()
        .onChange(of: session.tempoPlan.mode) { _, m in if m == .accuracy { audioInput = true } }
        .onChange(of: audioInput) { _, on in
            // Without the input nothing is scored: the plans and lengths that need the accuracy step back.
            if !on && session.tempoPlan.mode == .accuracy { session.tempoPlan.mode = .perLoop }
            if !on && session.kind == .challenge { session.kind = .duration }
        }
    }

    private var planTop: Int { session.tempoPlan.normalized.bounds(start: bpm, rule: exercise.tempo).top }

    private var patternLine: String {
        let sizes = RunBuilder.groupSizes(exercise)
        var runs: [(Int, Int)] = []
        for s in sizes { if let last = runs.last, last.0 == s { runs[runs.count - 1].1 += 1 } else { runs.append((s, 1)) } }
        return L.patternLine(runs)
    }

    private var tempoCaption: String {
        guard zones, let max = pa.level(exercise.id) else { return L.noMaxYet }
        return L.percentOfMaxLine(Int((Double(bpm) / Double(max) * 100).rounded()), max)
    }

    private var routeValue: String {
        audioInput ? L.routeShort(pa.route.input, pa.route.output) : pa.route.output
    }

    private func zoneOptions(_ max: Int) -> [(String, String, String?)] {
        [("manual", L.manual, nil)] + pa.zones.zones.map { z in
            let r = TempoZones.range(z, max: max)
            return (z.id, "\(z.name) \(z.title)", "\(r.lowerBound) to \(r.upperBound)")
        }
    }

    private var zoneBinding: Binding<String> {
        Binding(get: { pa.resume ? (pa.activeZone?.id ?? "manual") : "manual" },
                set: { id in if id == "manual" { pa.resume = false } else { pa.chooseZone(id) } })
    }

    private func zoneValue(_ max: Int) -> String {
        guard pa.resume, let z = pa.activeZone else { return L.manual }
        let r = TempoZones.range(z, max: max)
        return "\(z.name), \(r.lowerBound) to \(r.upperBound)"
    }
}

// MARK: Ascending tempo

/// Ascending tempo (Joe, 2026-11-24): off, per loop, or by accuracy with three thresholds (speed up, slow down,
/// break), each held for its own window, kept apart and settled after each change.
struct TempoPlanView: View {
    @Binding var plan: TempoPlan
    @Binding var start: Int
    let exercise: Exercise
    @Binding var audioInput: Bool

    private var top: Int { plan.normalized.bounds(start: start, rule: exercise.tempo).top }

    var body: some View {
        Form {
            Section {
                modeRow(.off, L.off)
                modeRow(.perLoop, L.perLoop)
                modeRow(.accuracy, L.byAccuracy)
            } footer: {
                if plan.mode == .accuracy { Text(L.usesAudioInput) }
            }

            if plan.mode != .off {
                Section(L.range) {
                    stepper(L.startTempo, L.bpmValue(start), $start, 1, exercise.tempo.min...exercise.tempo.max)
                    stepper(L.endTempo, L.bpmValue(top), Binding(get: { top }, set: { plan.endBPM = $0 }), 1,
                            start...exercise.tempo.max)
                    stepper(L.step, L.plusBPM(plan.step), $plan.step, 1, 1...20)
                    if plan.mode == .perLoop {
                        Picker(L.atTheTop, selection: $plan.atTop) {
                            Text(L.hold).tag(TempoPlan.AtTop.hold)
                            Text(L.restart).tag(TempoPlan.AtTop.restart)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }

            if plan.mode == .perLoop {
                Section(L.steps) {
                    Picker(L.count, selection: $plan.everyUnit) {
                        Text(L.loops).tag(TempoPlan.Unit.loops)
                        Text(L.seconds).tag(TempoPlan.Unit.seconds)
                    }
                    .pickerStyle(.segmented)
                    if plan.everyUnit == .loops {
                        stepper(L.every, L.loopCount(plan.every), $plan.every, 1, 1...16)
                    } else {
                        stepper(L.every, L.secondsValue(plan.every), $plan.every, 5, 5...300)
                    }
                }
            }

            if plan.mode == .accuracy {
                let n = plan.normalized
                Section(L.speedUp) {
                    stepper(L.atOrAbove, L.percent(plan.upPercent), $plan.upPercent, 1, 50...100)
                    stepper(L.forWindow, windowText(plan.upWindow), $plan.upWindow, windowStep, windowRange)
                }
                Section(L.slowDown) {
                    Toggle(L.slowDown, isOn: $plan.downOn).tint(Theme.accent)
                    if plan.downOn {
                        stepper(L.below, L.percent(n.downPercent), Binding(get: { n.downPercent }, set: { plan.downPercent = $0 }), 1,
                                30...max(30, n.upPercent - 5))
                        stepper(L.forWindow, windowText(plan.downWindow), $plan.downWindow, windowStep, windowRange)
                        stepper(L.lowest, L.bpmValue(n.bounds(start: start, rule: exercise.tempo).floor),
                                Binding(get: { plan.minBPM > 0 ? min(plan.minBPM, start) : start }, set: { plan.minBPM = $0 }), 1,
                                exercise.tempo.min...start)
                    }
                }
                Section(L.breakTitle) {
                    Toggle(L.autoBreak, isOn: $plan.breakOn).tint(Theme.accent)
                    if plan.breakOn {
                        stepper(L.below, L.percent(n.breakPercent), Binding(get: { n.breakPercent }, set: { plan.breakPercent = $0 }), 1,
                                0...max(0, (n.downOn ? n.downPercent : n.upPercent - 5) - 5))
                        stepper(L.forWindow, windowText(plan.breakWindow), $plan.breakWindow, windowStep, windowRange)
                        stepper(L.breakLength, L.secondsValue(plan.breakSeconds), $plan.breakSeconds, 5, 10...120)
                        Toggle(L.resumeSlower, isOn: $plan.slowerAfterBreak).tint(Theme.accent)
                    }
                }
                Section {
                    Picker(L.count, selection: $plan.windowUnit) {
                        Text(L.loops).tag(TempoPlan.Unit.loops)
                        Text(L.seconds).tag(TempoPlan.Unit.seconds)
                    }
                    .pickerStyle(.segmented)
                    stepper(L.waitAfterChange, L.loopCount(plan.cooldownLoops), $plan.cooldownLoops, 1, 0...8)
                } header: { Text(L.stability) } footer: { Text(L.stabilityFooter) }
            }
        }
        .houseForm()
        .navigationTitle(L.ascendingTempo)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: plan.mode) { _, m in if m == .accuracy { audioInput = true } }
    }

    private var windowStep: Int { plan.windowUnit == .loops ? 1 : 5 }
    private var windowRange: ClosedRange<Int> { plan.windowUnit == .loops ? 1...32 : 5...300 }
    private func windowText(_ n: Int) -> String { plan.windowUnit == .loops ? L.loopCount(n) : L.secondsValue(n) }

    private func modeRow(_ m: TempoPlan.Mode, _ title: String) -> some View {
        Button {
            Haptics.tick()
            plan.mode = m
        } label: {
            HStack {
                Text(title).foregroundStyle(Theme.text)
                Spacer()
                if plan.mode == m { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentText) }
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("plan.\(m.rawValue)")
    }

    private func stepper(_ label: String, _ value: String, _ binding: Binding<Int>, _ step: Int, _ range: ClosedRange<Int>) -> some View {
        Stepper(value: binding, in: range, step: step) {
            LabeledContent(label) { Text(value).font(Typo.figure(.body)).foregroundStyle(Theme.text) }
        }
        .sensoryFeedback(.selection, trigger: binding.wrappedValue)
    }
}

// MARK: Length

/// How long a run goes: loops, a time, holding an accuracy (or until stopped, with the input off), or a Challenge
/// (Joe, 2026-11-24: "counts duration but only counts towards the time when the accuracy is above a certain
/// threshold").
struct LengthView: View {
    @Binding var session: SessionSettings
    let audioInput: Bool

    var body: some View {
        Form {
            Section {
                row(.cycles, L.loopsTitle)
                row(.duration, L.time)
                row(.endurance, audioInput ? L.holdAccuracy : L.untilStopped)
                if audioInput { row(.challenge, L.challenge) }
            } footer: {
                if session.kind == .challenge { Text(L.challengeFooter) }
            }
            Section {
                switch session.kind {
                case .cycles, .routine:
                    stepper(L.loopsTitle, L.loopCount(session.cycles), $session.cycles, 1, 1...100)
                case .duration:
                    stepper(L.time, formatClock(Double(session.seconds)), $session.seconds, 30, 30...1800)
                case .endurance:
                    if audioInput {
                        stepper(L.accuracy, L.percent(session.targetPercent), $session.targetPercent, 5, 50...100)
                        stepper(L.over, L.loopCount(session.windowCycles), $session.windowCycles, 1, 1...8)
                    }
                case .challenge:
                    stepper(L.earn, formatClock(Double(session.seconds)), $session.seconds, 30, 30...1800)
                    stepper(L.atOrAbove, L.percent(session.targetPercent), $session.targetPercent, 1, 50...100)
                    stepper(L.over, L.loopCount(session.windowCycles), $session.windowCycles, 1, 1...8)
                    stepper(L.cap, session.capSeconds == 0 ? L.off : formatClock(Double(session.capSeconds)),
                            $session.capSeconds, 60, 0...3600)
                }
            }
        }
        .houseForm()
        .navigationTitle(L.length)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ k: SessionSettings.Kind, _ title: String) -> some View {
        Button {
            Haptics.tick()
            session.kind = k
            if k == .challenge && session.targetPercent < 80 { session.targetPercent = 90 }
        } label: {
            HStack {
                Text(title).foregroundStyle(Theme.text)
                Spacer()
                if session.kind == k { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentText) }
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("length.\(k.rawValue)")
    }

    private func stepper(_ label: String, _ value: String, _ binding: Binding<Int>, _ step: Int, _ range: ClosedRange<Int>) -> some View {
        Stepper(value: binding, in: range, step: step) {
            LabeledContent(label) { Text(value).font(Typo.figure(.body)).foregroundStyle(Theme.text) }
        }
        .sensoryFeedback(.selection, trigger: binding.wrappedValue)
    }
}

// MARK: Options

/// The rest of a drill's setup, one step in: the click (sound, level, accent, count-in, the gap trainer), the
/// scoring (the pass mark, the calibration), the voice, and the guitar's tuning for this drill.
struct OptionsView: View {
    @Binding var session: SessionSettings
    let audioInput: Bool
    @Binding var intro: Bool
    /// The drill's own screen: the calibration is here too.
    var calibrate: Bool
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var tunings: TuningStore

    var body: some View {
        Form {
            Section(L.click) {
                NavigationLink {
                    ChoiceList(title: L.clickSound, options: SessionSettings.ClickSound.allCases.map { ($0, L.soundName($0), nil) },
                               selection: $session.clickSound)
                } label: { LabeledContent(L.clickSound, value: L.soundName(session.clickSound)) }
                LabeledContent(L.clickLevel) {
                    HStack(spacing: Space.sm) {
                        Slider(value: $session.clickLevel, in: 0...1).tint(Theme.accent).frame(maxWidth: 150)
                        Text(L.percent(Int((session.clickLevel * 100).rounded()))).font(Typo.figure(.body))
                            .foregroundStyle(Theme.muted).frame(width: 48, alignment: .trailing)
                    }
                }
                NavigationLink {
                    ChoiceList(title: L.accent, options: [(SessionSettings.Accent.off, L.off, nil), (.one, L.accentOne, nil),
                                                         (.groups, L.accentGroups, nil)], selection: $session.accent)
                } label: { LabeledContent(L.accent, value: L.accentName(session.accent)) }
                Stepper(value: $session.countInBars, in: 0...4) {
                    LabeledContent(L.countIn) { Text(session.countInBars == 0 ? L.off : L.barCount(session.countInBars)).font(Typo.figure(.body)) }
                }
                NavigationLink {
                    ChoiceList(title: L.gapTrainer, options: [0, 2, 3, 4, 8].map { ($0, L.gapName($0), nil) },
                               selection: $session.gapEvery, footer: L.gapFooter)
                } label: { LabeledContent(L.gapTrainer, value: L.gapName(session.gapEvery)) }
                Toggle(L.clickOn, isOn: $pa.gridClicks).tint(Theme.accent)
            }

            if audioInput {
                Section(L.scoring) {
                    if session.kind != .endurance && session.kind != .challenge {
                        Stepper(value: $session.targetPercent, in: 50...100, step: 5) {
                            LabeledContent(L.passMark) { Text(L.percent(session.targetPercent)).font(Typo.figure(.body)) }
                        }
                    }
                    if calibrate {
                        Button { pa.startCalibration() } label: {
                            LabeledContent(L.calibration, value: pa.calibration.map { L.ms(Int(($0.measured * 1000).rounded())) } ?? L.notYet)
                        }
                        .foregroundStyle(Theme.text)
                        .accessibilityIdentifier("calibrate")
                    }
                }
            }

            Section(L.voice) {
                Toggle(L.voiceIntro, isOn: $intro).tint(Theme.accent)
            }

            Section(L.guitar) {
                NavigationLink {
                    TuningView(selection: $session.tuning, allowDefault: true)
                } label: { LabeledContent(L.tuning, value: session.tuning?.name ?? L.defaultTuning(tunings.tuning.name)) }
            }
        }
        .houseForm()
        .navigationTitle(L.options)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Tuning

/// The tuning: the presets with their notes, low string first, and Custom. From Settings it sets the guitar's; from
/// a drill or a block's Options it is an override, with "Default" (the guitar's) first.
struct TuningView: View {
    @Binding var selection: Tuning?
    var allowDefault = false
    @EnvironmentObject var tunings: TuningStore
    @State private var custom = false

    var body: some View {
        Form {
            Section {
                if allowDefault {
                    row(title: L.defaultWord, value: tunings.tuning.name, chosen: selection == nil) { selection = nil }
                }
                ForEach(Tuning.presets) { t in
                    row(title: t.name, value: t.lowToHigh, chosen: selection?.id == t.id) { selection = t }
                }
                Button {
                    if selection?.isCustom != true { selection = Tuning.custom((selection ?? tunings.tuning).strings) }
                    custom = true
                } label: {
                    HStack {
                        Text(L.custom).foregroundStyle(Theme.text)
                        Spacer()
                        if let s = selection, s.isCustom { Text(s.lowToHigh).font(Typo.figure(.subheadline)).foregroundStyle(Theme.muted) }
                        if selection?.isCustom == true { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentText) }
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.faint)
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .houseForm()
        .navigationTitle(L.tuning)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $custom) {
            CustomTuningView(tuning: Binding(get: { selection ?? Tuning.custom(tunings.tuning.strings) }, set: { selection = $0 }))
        }
    }

    private func row(title: String, value: String, chosen: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            Haptics.tick()
            pick()
        } label: {
            HStack {
                Text(title).foregroundStyle(Theme.text)
                Spacer()
                Text(value).font(Typo.figure(.subheadline)).foregroundStyle(Theme.muted).lineLimit(1)
                if chosen { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accentText) }
            }
            .contentShape(Rectangle())
        }
    }
}

/// A tuning of his own: six or seven strings, each a semitone at a time.
struct CustomTuningView: View {
    @Binding var tuning: Tuning

    var body: some View {
        Form {
            Section {
                Picker(L.strings, selection: Binding(get: { tuning.strings.count }, set: { n in
                    var s = tuning.strings
                    if n == 7 && s.count == 6 { s.append(s.last! - 5) }
                    if n == 6 && s.count == 7 { s.removeLast() }
                    tuning = Tuning.custom(s)
                })) {
                    Text("6").tag(6)
                    Text("7").tag(7)
                }
                .pickerStyle(.segmented)
            }
            Section {
                ForEach(Array(tuning.strings.indices.reversed()), id: \.self) { i in
                    Stepper(value: Binding(get: { tuning.strings.indices.contains(i) ? tuning.strings[i] : 40 }, set: { v in
                        var s = tuning.strings
                        guard s.indices.contains(i) else { return }
                        s[i] = v
                        tuning = Tuning.custom(s)
                    }), in: (Tuning.standard.strings[min(i, 5)] - 18)...(Tuning.standard.strings[min(i, 5)] + 18)) {
                        LabeledContent(L.stringNumber(i + 1)) {
                            Text(tuning.strings.indices.contains(i) ? Tuning.noteName(tuning.strings[i], octave: true) : "").font(Typo.figure(.body))
                        }
                    }
                    .sensoryFeedback(.selection, trigger: tuning.strings)
                }
            }
            Section {
                Menu {
                    ForEach(Tuning.presets) { t in
                        Button(t.name) { tuning = Tuning.custom(t.strings) }
                    }
                } label: { Text(L.copyFrom).foregroundStyle(Theme.accentText) }
            }
        }
        .houseForm()
        .navigationTitle(L.customTuning)
        .navigationBarTitleDisplayMode(.inline)
    }
}
