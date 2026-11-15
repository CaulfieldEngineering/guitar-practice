import SwiftUI

@main
struct PracticeApp: App {
    @StateObject private var player: Player
    @StateObject private var playAlong: PlayAlong
    @StateObject private var history: History
    @StateObject private var store = RoutineStore()
    @StateObject private var updater = Updater()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let p = Player()
        let h = History()
        _player = StateObject(wrappedValue: p)
        _history = StateObject(wrappedValue: h)
        _playAlong = StateObject(wrappedValue: PlayAlong(player: p, history: h))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .environmentObject(playAlong)
                .environmentObject(store)
                .environmentObject(updater)
                .environmentObject(history)
                .environmentObject(player.voice)
                .task { await updater.check() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await updater.check(); await history.sync() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var updater: Updater
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            MetronomeView()
                .tabItem { Label("Metronome", systemImage: "metronome") }.tag(0)
            RoutinesView()
                .tabItem { Label("Intervals", systemImage: "timer") }.tag(1)
            PlayAlongView()
                .tabItem { Label("Play along", systemImage: "waveform") }.tag(2)
        }
        .tint(Theme.accent)
        .alert("Sound could not start", isPresented: Binding(get: { player.errorText != nil }, set: { if !$0 { player.errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(player.errorText ?? "") }
    }
}

/// The top of each screen: a small title, the Update capsule when there is one, and Settings.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing
    @EnvironmentObject var updater: Updater
    @State private var settings = false

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            if updater.available != nil {
                Button { updater.install() } label: {
                    Text("Update").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Theme.accent, in: Capsule()).foregroundStyle(Theme.onAccent)
                }.buttonStyle(.plain)
            }
            trailing
            Button { settings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 17)).foregroundStyle(Theme.muted)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .sheet(isPresented: $settings) { SettingsView() }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}
