import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var store: RoutineStore
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var history: History
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var voice: Voice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(updater.current).foregroundStyle(Theme.muted)
                    }
                    if let v = updater.available {
                        Button { updater.install() } label: {
                            HStack {
                                Text("Update to \(v)").foregroundStyle(Theme.accent)
                                Spacer()
                                Image(systemName: "arrow.down.circle").foregroundStyle(Theme.accent)
                            }
                        }
                    } else {
                        Button("Check for an update") { Task { await updater.check() } }
                    }
                } header: { Text("App") }

                Section {
                    HStack {
                        Text("Click volume")
                        Slider(value: $player.volume, in: 0...1).tint(Theme.accent)
                    }
                    Toggle("Keep the screen on while playing", isOn: $player.keepScreenOn).tint(Theme.accent)
                } header: { Text("Sound") } footer: {
                    Text("The click plays alongside other apps and keeps going with the screen locked.")
                }

                Section {
                    Toggle("Speak an intro before each drill", isOn: $voice.introOn).tint(Theme.accent)
                    Toggle("Short spoken cues", isOn: $voice.cuesOn).tint(Theme.accent)
                    Picker("Voice", selection: Binding(get: { voice.voice?.identifier ?? "" }, set: { voice.voiceID = $0 })) {
                        ForEach(Voice.englishVoices, id: \.identifier) { v in
                            Text("\(v.name), \(Voice.qualityName(v.quality))").tag(v.identifier)
                        }
                    }
                    Button("Hear it") {
                        voice.speak("Triplets to sixteenths, four and four. Eighty beats per minute.", always: true)
                    }
                } header: { Text("Voice") } footer: {
                    Text("The best voice on the phone is used. For a better one, download a Premium or Enhanced English voice in the iPhone's Settings, Accessibility, Spoken Content, Voices, English. Cues say the next tempo or the switch to sixteenths; they stay quiet when the phone is on its own speaker and microphone.")
                }

                Section {
                    Button("Get drills from the mini PC") { Task { await pa.refresh() } }
                    if let n = pa.catalogNote { Text(n).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                    HStack {
                        Text("Runs not sent yet")
                        Spacer()
                        Text("\(history.pendingCount)").foregroundStyle(Theme.muted)
                    }
                    Button("Send runs now") { Task { await history.sync() } }
                    Button("Put back the starter routines") { store.restoreStarters() }
                    Toggle("Use the phone's microphone (testing)", isOn: $pa.allowPhoneMic).tint(Theme.accent)
                } header: { Text("Drills and runs") } footer: {
                    Text("Drills come from the mini PC over Tailscale and are kept on the phone for when it is out of reach. Every run is sent back to it.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.side.ignoresSafeArea())
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
