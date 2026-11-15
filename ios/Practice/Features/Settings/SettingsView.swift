import SwiftUI

/// Settings, grouped: what is used often first (sound, voice), then the drills and runs, then the app itself, and
/// the rarely touched switches folded away under Advanced.
struct SettingsView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var store: RoutineStore
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var history: History
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var voice: Voice
    @Environment(\.dismiss) private var dismiss
    @State private var advanced = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Space.sm) {
                        Text("Click volume")
                        Slider(value: $player.volume, in: 0...1).tint(Theme.accent)
                            .accessibilityLabel("Click volume")
                    }
                    Toggle("Keep the screen on while playing", isOn: $player.keepScreenOn).tint(Theme.accent)
                } header: { Text("Sound") } footer: {
                    Text("The click plays alongside other apps and keeps going with the screen locked.")
                }

                Section {
                    Toggle("Speak an intro before each drill", isOn: $voice.introOn).tint(Theme.accent)
                    Toggle("Short spoken cues", isOn: $voice.cuesOn).tint(Theme.accent)
                    // The list of voices is read once, in the background, by Voice; this only shows what it holds
                    // (reading it here on every redraw froze this screen in 0.1.4).
                    if voice.voices.isEmpty {
                        HStack { Text("Voice"); Spacer(); ProgressView() }
                    } else {
                        Picker("Voice", selection: Binding(get: { voice.selectedID }, set: { voice.voiceID = $0 })) {
                            ForEach(voice.voices) { v in Text("\(v.name), \(v.quality)").tag(v.id) }
                        }
                    }
                    Button("Hear it") {
                        voice.speak("Triplets to sixteenths, four and four. Eighty beats per minute.", always: true)
                    }
                } header: { Text("Voice") } footer: {
                    Text("Cues say the next tempo or the switch to sixteenths. For a better voice, download a Premium or Enhanced English one in the iPhone's Settings, Accessibility, Spoken Content, Voices.")
                }

                Section {
                    Button("Calibrate the timing") { pa.startCalibration() }
                        .accessibilityIdentifier("settings.calibrate")
                    if let m = pa.message { Text(m).font(Typo.foot).foregroundStyle(Theme.muted) }
                } header: { Text("Timing") } footer: {
                    Text("Two steps: line the picture up with the click you hear, then pick along so the guitar's delay is measured. Kept for each audio setup; do it again when the headphones or the interface change.")
                }

                Section {
                    Button("Get drills from the mini PC") { Task { await pa.refresh() } }
                    if let n = pa.catalogNote { Text(n).font(Typo.foot).foregroundStyle(Theme.muted) }
                    HStack {
                        Text("Runs not sent yet")
                        Spacer()
                        Text("\(history.pendingCount)").font(Typo.figure()).foregroundStyle(Theme.muted)
                    }
                    if history.pendingCount > 0 {
                        Button("Send runs now") { Task { await history.sync() } }
                    }
                } header: { Text("Drills and runs") } footer: {
                    Text("Drills come from the mini PC over Tailscale and are kept on the phone for when it is out of reach. Every scored run is sent back to it.")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(updater.current).font(Typo.figure()).foregroundStyle(Theme.muted)
                    }
                    if let v = updater.available {
                        Button { updater.install() } label: {
                            HStack {
                                Text("Update to \(v)")
                                Spacer()
                                Image(systemName: "arrow.down.circle")
                            }
                            .foregroundStyle(Theme.accentText)
                        }
                    } else {
                        Button("Check for an update") { Task { await updater.check() } }
                    }
                } header: { Text("App") }

                Section {
                    DisclosureGroup("Advanced", isExpanded: $advanced) {
                        Toggle("Use the phone's microphone (testing)", isOn: $pa.allowPhoneMic).tint(Theme.accent)
                        Button("Put back the starter routines") { store.restoreStarters() }
                    }
                } footer: {
                    if advanced {
                        Text("The phone's microphone hears the click and the room, so it is only for trying things without the interface.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.side.ignoresSafeArea())
            .tint(Theme.accentText)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(isPresented: Binding(get: { pa.phase == .syncing || pa.phase == .calibrating },
                                                  set: { if !$0 { pa.stop() } })) {
                CalibrationView()
            }
        }
    }
}
