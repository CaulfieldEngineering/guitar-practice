import SwiftUI

/// Settings, grouped: what is used often first (sound, voice, timing), then syncing, the app itself, and the
/// rarely touched switch folded away under Advanced. The words are in Shared/Strings.swift.
struct SettingsView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var history: History
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var voice: Voice
    @Environment(\.dismiss) private var dismiss
    @State private var advanced = false
    @AppStorage("audio.lockScreen") private var lockScreen = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Space.sm) {
                        Text(L.clickVolume)
                        Slider(value: $player.volume, in: 0...1).tint(Theme.accent)
                            .accessibilityLabel(L.clickVolume)
                    }
                    Toggle(L.keepScreenOn, isOn: $player.keepScreenOn).tint(Theme.accent)
                    Toggle(L.lockScreenControls, isOn: $lockScreen).tint(Theme.accent)
                } header: { Text(L.sound) } footer: { Text(L.soundFooter) }

                Section {
                    Toggle(L.voiceIntro, isOn: $voice.introOn).tint(Theme.accent)
                    Toggle(L.voiceCues, isOn: $voice.cuesOn).tint(Theme.accent)
                    // The list of voices is read once, in the background, by Voice; this only shows what it holds
                    // (reading it here on every redraw froze this screen in 0.1.4).
                    if voice.voices.isEmpty {
                        HStack { Text(L.voice); Spacer(); ProgressView() }
                    } else {
                        Picker(L.voice, selection: Binding(get: { voice.selectedID }, set: { voice.voiceID = $0 })) {
                            ForEach(voice.voices) { v in Text("\(v.name), \(v.quality)").tag(v.id) }
                        }
                    }
                    Button(L.preview) { voice.speak(L.previewText, always: true) }
                } header: { Text(L.voice) } footer: { Text(L.voiceFooter) }

                Section {
                    Button(L.calibrate) { pa.startCalibration() }
                        .accessibilityIdentifier("settings.calibrate")
                    if let m = pa.message { Text(m).font(Typo.foot).foregroundStyle(Theme.muted) }
                } header: { Text(L.timing) } footer: { Text(L.timingFooter) }

                Section {
                    Button(L.updateDrills) { Task { await pa.refresh() } }
                    if let n = pa.catalogNote { Text(n).font(Typo.foot).foregroundStyle(Theme.muted) }
                    HStack {
                        Text(L.pendingRuns)
                        Spacer()
                        Text("\(history.pendingCount)").font(Typo.figure()).foregroundStyle(Theme.muted)
                    }
                    if history.pendingCount > 0 {
                        Button(L.syncNow) { Task { await history.sync() } }
                    }
                } header: { Text(L.sync) } footer: { Text(L.syncFooter) }

                Section {
                    HStack {
                        Text(L.version)
                        Spacer()
                        Text(updater.current).font(Typo.figure()).foregroundStyle(Theme.muted)
                    }
                    if let v = updater.available {
                        Button { updater.install() } label: {
                            HStack {
                                Text(L.updateTo(v))
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                            }
                            .foregroundStyle(Theme.accentText)
                        }
                    } else {
                        Button(L.checkForUpdates) { Task { await updater.check() } }
                    }
                } header: { Text(L.about) }

                Section {
                    DisclosureGroup(L.advanced, isExpanded: $advanced) {
                        Toggle(L.useMicrophone, isOn: $pa.allowPhoneMic).tint(Theme.accent)
                    }
                } footer: {
                    if advanced { Text(L.microphoneFooter) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.side.ignoresSafeArea())
            .tint(Theme.accentText)
            .navigationTitle(L.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L.done) { dismiss() } } }
            .fullScreenCover(isPresented: Binding(get: { pa.phase == .syncing || pa.phase == .calibrating },
                                                  set: { if !$0 { pa.stop() } })) {
                CalibrationView()
            }
        }
    }
}
