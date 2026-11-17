import SwiftUI

/// Settings > Audio: pick the input and the output, see the guitar's level, test the sound, hear the guitar through
/// the app, the latencies and the calibration, and, when something is wrong, what to try (Joe, 2026-11-16: "a whole
/// audio test area? to define the input, and the output and check levels etc"; "just allow me to pick input and
/// output explicitly"). The choices come first; the check and the session's details come after.
struct AudioSettingsView: View {
    @EnvironmentObject var setup: AudioSetup
    @EnvironmentObject var player: Player
    @EnvironmentObject var pa: PlayAlong
    @State private var details = false

    var body: some View {
        Form {
            Section {
                InputPickerRow()
                if let n = setup.inputNote { NoteLine(text: n) }
                if let input = setup.input, input.sources.count > 1 {
                    Picker(L.micPosition, selection: Binding(get: { setup.sourceID ?? -1 }, set: { setup.selectSource($0) })) {
                        ForEach(input.sources) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.navigationLink)
                }
                if setup.gainSettable {
                    SliderRow(label: L.inputGain, value: Binding(get: { Double(setup.gain) }, set: { setup.setGain(Float($0)) }))
                }
                MeterRow()
                if setup.listening {
                    LabeledContent(L.level) {
                        Text(L.verdict(setup.meter.verdict))
                            .foregroundStyle(setup.meter.verdict == .good ? Theme.accentText : (setup.meter.verdict == .noSignal ? Theme.muted : Theme.warn))
                            .accessibilityIdentifier("audio.verdict")
                    }
                } else {
                    LabeledContent(L.level) { Text(setup.startError ?? L.notListening).foregroundStyle(Theme.muted) }
                }
            } header: { Text(L.inputDevice) }

            Section {
                OutputPickerRow()
                if let n = setup.outputNote { NoteLine(text: n) }
                LabeledContent(L.otherOutput) {
                    RoutePicker().frame(width: 32, height: 32).accessibilityLabel(L.chooseOutput)
                }
                Button(L.testTone) { setup.playTone() }.disabled(!setup.listening)
                    .accessibilityIdentifier("audio.tone")
                Button(L.clickTest) { setup.playClicks() }.disabled(!setup.listening)
                SliderRow(label: L.appSounds, value: $player.volume)
            } header: { Text(L.outputDevice) } footer: { Text(L.appSoundsFooter) }

            if !setup.problems.isEmpty {
                Section {
                    ForEach(setup.problems) { ProblemRow(problem: $0) }
                } header: { Text(L.check) }
            }

            Section {
                Toggle(L.hearGuitar, isOn: Binding(get: { setup.monitor }, set: { setup.setMonitor($0) }))
                    .tint(Theme.accent)
                    .disabled(setup.route.phoneSpeakerAndMic)
                if setup.monitor {
                    SliderRow(label: L.guitarLevel, value: Binding(get: { setup.monitorLevel }, set: { setup.setMonitorLevel($0) }))
                }
            } header: { Text(L.monitoring) } footer: {
                if setup.route.phoneSpeakerAndMic { Text(L.monitorSpeaker) } else if setup.route.bluetoothOutput { Text(L.monitorBluetooth) }
            }

            Section {
                ms(L.latencyInput, setup.inputLatency)
                ms(L.latencyOutput, setup.outputLatency)
                ms(L.latencyBuffer, setup.ioBuffer)
                ms(L.latencyTotal, setup.inputLatency + setup.outputLatency + setup.ioBuffer)
                LabeledContent(L.calibration) {
                    if let c = pa.calibration {
                        Text(L.calibratedOn(Int((c.measured * 1000).rounded()), c.date.formatted(.dateTime.month(.abbreviated).day())))
                            .font(Typo.figure())
                    } else {
                        Text(L.notCalibrated)
                    }
                }
                Button(L.calibrate) { setup.calibrate() }
                    .accessibilityIdentifier("audio.calibrate")
            } header: { Text(L.latency) } footer: { Text(L.timingFooter) }

            Section {
                DisclosureGroup(L.sessionDetails, isExpanded: $details) {
                    LabeledContent(L.category, value: setup.category)
                    LabeledContent(L.mode, value: setup.mode)
                    LabeledContent(L.sessionOptions, value: setup.options)
                    LabeledContent(L.microphone, value: permissionText)
                    LabeledContent(L.interface, value: setup.inputs.first(where: { $0.kind == .interface })?.name ?? L.notFound)
                    LabeledContent(L.inputsListed, value: setup.inputs.isEmpty ? L.none : setup.inputs.map(\.name).joined(separator: ", "))
                    LabeledContent(L.outputsListed, value: setup.outputs.isEmpty ? L.none : setup.outputs.map(\.name).joined(separator: ", "))
                    LabeledContent(L.channels, value: "\(setup.channelCount)")
                    LabeledContent(L.sampleRate, value: L.hz(setup.sampleRate))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.side.ignoresSafeArea())
        .navigationTitle(L.audio)
        .navigationBarTitleDisplayMode(.inline)
        .background { RoutePicker(trigger: setup.systemPicker).frame(width: 1, height: 1).opacity(0.01).accessibilityHidden(true) }
        .onAppear { setup.open() }
        .onDisappear { setup.close() }
        .onChange(of: pa.phase) { _, phase in
            // Back from the calibration: listen again.
            if phase == .ready { setup.startListening() }
        }
    }

    private var permissionText: String {
        switch setup.permission { case .granted: return L.allowed; case .denied: return L.denied; case .undetermined: return L.notAsked }
    }

    private func ms(_ label: String, _ seconds: Double) -> some View {
        LabeledContent(label) { Text(L.ms(Int((seconds * 1000).rounded()))).font(Typo.figure()) }
    }
}

/// The Input list: every input iOS offers, and each input of a two-input interface on its own line.
struct InputPickerRow: View {
    @EnvironmentObject var setup: AudioSetup

    var body: some View {
        Picker(L.inputDevice, selection: Binding(get: { setup.inputChoiceID ?? "" }, set: { id in
            if let c = setup.inputChoices.first(where: { $0.id == id }) { setup.select(c) }
        })) {
            if setup.inputChoiceID == nil { Text(L.noInputName).tag("") }
            ForEach(setup.inputChoices) { Text($0.name).tag($0.id) }
        }
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier("audio.input")
    }
}

/// The Output list: the speaker, and every output this phone has used (iOS names only the one in use). Picking one
/// other than the speaker opens iOS's own list, since only iOS can move the sound there.
struct OutputPickerRow: View {
    @EnvironmentObject var setup: AudioSetup

    var body: some View {
        Picker(L.outputDevice, selection: Binding(get: { setup.outputChoiceID ?? "" }, set: { setup.selectOutput($0) })) {
            if setup.outputChoiceID == nil || !setup.outputChoices.contains(where: { $0.id == setup.outputChoiceID }) {
                Text(setup.outputs.first?.name ?? L.noOutputName).tag(setup.outputChoiceID ?? "")
            }
            ForEach(setup.outputChoices) { Text($0.name).tag($0.id) }
        }
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier("audio.output")
    }
}

/// One line in amber under a choice that iOS did not take.
struct NoteLine: View {
    let text: String
    var body: some View {
        Text(text).font(Typo.foot).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("audio.note")
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    var body: some View {
        HStack(spacing: Space.sm) {
            Text(label).lineLimit(1)
            Slider(value: $value, in: 0...1).tint(Theme.accent).accessibilityLabel(label)
        }
    }
}

/// The level meter: the bar, the peak-hold tick, the clip light; the scale runs from -60 to 0 dBFS.
struct MeterRow: View {
    @EnvironmentObject var setup: AudioSetup

    var body: some View {
        HStack(spacing: Space.sm) {
            GeometryReader { g in
                let w = g.size.width
                let level = AudioLevel.fraction(setup.meter.levelDB)
                let hold = AudioLevel.fraction(setup.meter.holdDB)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.lineStrong)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(setup.meter.clipping ? Theme.danger : (setup.meter.levelDB > -6 ? Theme.warn : Theme.accent))
                        .frame(width: max(0, w * level))
                    if hold > 0 {
                        Rectangle().fill(Theme.text).frame(width: 2).offset(x: max(0, w * hold - 2))
                    }
                }
            }
            .frame(height: 8)
            Circle()
                .fill(setup.meter.clipping ? Theme.danger : Theme.lineStrong)
                .frame(width: 8, height: 8)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.level)
        .accessibilityValue(setup.listening ? L.verdict(setup.meter.verdict) : L.notListening)
        .accessibilityIdentifier("audio.meter")
    }
}

/// A problem, what to try, and its one action if it has one.
struct ProblemRow: View {
    @EnvironmentObject var setup: AudioSetup
    let problem: AudioProblem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(problem.title).foregroundStyle(problem.warning ? Theme.warn : Theme.text)
            ForEach(Array(problem.steps.enumerated()), id: \.offset) { i, step in
                Text("\(i + 1). \(step)").font(Typo.foot).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let a = problem.action {
                Button(title(a)) { setup.perform(a) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.accentText)
                    .padding(.top, Space.xxs)
            }
        }
        .padding(.vertical, Space.xxs)
        .accessibilityIdentifier("problem.\(problem.id)")
    }

    private func title(_ a: AudioProblem.Action) -> String {
        switch a {
        case .openSettings: return L.openSettings
        case .askPermission: return L.allow
        case .useChannel(let c): return L.useInput(c == .second ? 2 : 1)
        }
    }
}
