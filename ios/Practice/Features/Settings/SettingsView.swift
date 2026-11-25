import SwiftUI

/// Settings, a sheet with Done: Audio, Guitar (the tuning), Sound, Voice, Screen, Sync, About. One helper line at
/// most, under the group it explains. The words are in Shared/Strings.swift.
struct SettingsView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var history: History
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var voice: Voice
    @EnvironmentObject var audio: AudioSetup
    @EnvironmentObject var tunings: TuningStore
    @EnvironmentObject var routines: PracticeRoutineStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("audio.lockScreen") private var lockScreen = false
    @AppStorage("sound.chime") private var chime = true
    @AppStorage("sound.ticks") private var ticks = true
    @AppStorage(DrillServer.addressKey) private var serverAddress = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { AudioSettingsView() } label: { LabeledContent(L.audio, value: audio.input?.name ?? L.noInputName) }
                        .accessibilityIdentifier("settings.audio")
                    Button { pa.startCalibration() } label: {
                        LabeledContent(L.calibration, value: pa.calibration.map { L.ms(Int(($0.measured * 1000).rounded())) } ?? L.notYet)
                    }
                    .foregroundStyle(Theme.text)
                    .accessibilityIdentifier("settings.calibrate")
                    Toggle(L.phoneMicrophone, isOn: $pa.allowPhoneMic).tint(Theme.accent)
                } header: { Text(L.audio) } footer: { Text(L.phoneMicFooter) }

                Section(L.guitar) {
                    NavigationLink {
                        TuningView(selection: Binding(get: { tunings.tuning }, set: { if let t = $0 { tunings.set(t) } }))
                    } label: { LabeledContent(L.tuning, value: tunings.tuning.name) }
                    .accessibilityIdentifier("settings.tuning")
                }

                Section(L.sound) {
                    NavigationLink {
                        ChoiceList(title: L.clickSound, options: SessionSettings.ClickSound.allCases.map { ($0, L.soundName($0), nil) },
                                   selection: $player.clickSound)
                    } label: { LabeledContent(L.clickSound, value: L.soundName(player.clickSound)) }
                    LabeledContent(L.clickLevel) {
                        HStack(spacing: Space.sm) {
                            Slider(value: $player.clickLevel, in: 0...1).tint(Theme.accent).frame(maxWidth: 150)
                            Text(L.percent(Int((player.clickLevel * 100).rounded()))).font(Typo.figure(.body)).foregroundStyle(Theme.muted)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    Toggle(L.blockChime, isOn: $chime).tint(Theme.accent)
                    Toggle(L.countdownTicks, isOn: $ticks).tint(Theme.accent)
                }

                Section(L.voice) {
                    Toggle(L.voiceIntro, isOn: $voice.introOn).tint(Theme.accent)
                    Toggle(L.voiceCues, isOn: $voice.cuesOn).tint(Theme.accent)
                    if voice.voices.isEmpty {
                        HStack { Text(L.voice); Spacer(); ProgressView() }
                    } else {
                        Picker(L.voice, selection: Binding(get: { voice.selectedID }, set: { voice.voiceID = $0 })) {
                            ForEach(voice.voices) { v in Text(v.name).tag(v.id) }
                        }
                        .pickerStyle(.navigationLink)
                    }
                    Button(L.preview) { voice.speak(parts: L.previewParts, always: true) }.foregroundStyle(Theme.accentText)
                }

                Section(L.screen) {
                    Toggle(L.keepScreenOn, isOn: $player.keepScreenOn).tint(Theme.accent)
                    Toggle(L.lockScreenControls, isOn: $lockScreen).tint(Theme.accent)
                }

                Section {
                    LabeledContent(L.server) {
                        TextField(DrillServer.base.absoluteString, text: $serverAddress)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("settings.server")
                    }
                    LabeledContent(L.drills, value: pa.catalogNote ?? L.upToDate)
                    LabeledContent(L.runsWaiting) { Text("\(history.pendingCount)").font(Typo.figure(.body)) }
                    Button(L.syncNow) {
                        Task { await pa.refresh(); await routines.sync(); await tunings.sync() }
                    }
                    .foregroundStyle(Theme.accentText)
                } header: { Text(L.sync) } footer: { Text(L.syncFooter) }

                Section(L.about) {
                    LabeledContent(L.version) { Text(updater.current).font(Typo.figure(.body)) }
                    if let v = updater.available {
                        Button(L.updateTo(v)) { updater.install() }.foregroundStyle(Theme.accentText)
                    } else {
                        Button(L.checkForUpdates) { Task { await updater.check() } }.foregroundStyle(Theme.accentText)
                    }
                }
            }
            .houseForm()
            .navigationTitle(L.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.done) { dismiss() } } }
            .onAppear { audio.refresh() }
            .routeNotice()
            .fullScreenCover(isPresented: Binding(get: { pa.phase == .syncing || pa.phase == .calibrating },
                                                  set: { if !$0 { pa.stop() } })) {
                CalibrationView().routeNotice()
            }
        }
    }
}
