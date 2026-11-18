import AVFoundation
import SwiftUI
import UIKit

@main
struct PracticeApp: App {
    @StateObject private var player: Player
    @StateObject private var playAlong: PlayAlong
    @StateObject private var history: History
    @StateObject private var store = RoutineStore()
    @StateObject private var updater = Updater()
    @StateObject private var audioSetup: AudioSetup
    @Environment(\.scenePhase) private var scenePhase
    /// The lock screen's and Control Center's pause and stop.
    private let nowPlaying: NowPlaying

    init() {
        #if DEBUG
        // The UI tests start from a clean slate (the unit tests share this app's settings on the simulator).
        if UserDefaults.standard.bool(forKey: "resetState"), let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        #endif
        // 0.2.1, once: clear the saved output pick. In 0.2.0 a saved "iPhone Speaker" held the phone's microphone
        // in place of the interface after every restart (Joe, 2026-11-17: "I've even restarted my phone and its still
        // stuck"). Calibrations, runs and the input pick are kept.
        if !UserDefaults.standard.bool(forKey: "migrated.0.2.1") {
            AudioPrefs.preferredOutput = nil
            UserDefaults.standard.set(true, forKey: "migrated.0.2.1")
        }
        RouteHub.start()
        let p = Player()
        let h = History()
        let pa = PlayAlong(player: p, history: h)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "seedMax") { pa.seedMaxForScreenshots() }
        #endif
        _player = StateObject(wrappedValue: p)
        _history = StateObject(wrappedValue: h)
        _playAlong = StateObject(wrappedValue: pa)
        _audioSetup = StateObject(wrappedValue: AudioSetup(player: p, playAlong: pa))
        nowPlaying = NowPlaying(player: p, playAlong: pa)
        PracticeApp.styleBars()
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
                .environmentObject(audioSetup)
                .task { await updater.check() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        audioSetup.resumeIfVisible()
                        Task { await updater.check(); await history.sync() }
                    }
                    if phase == .background { PracticeApp.releaseInput(player: player, setup: audioSetup) }
                }
        }
    }

    /// Leaving the app lets go of the microphone (Joe, 2026-11-17: "it still says guitar practice is using my
    /// microphone"): the Audio screen's listening stops, and with nothing playing the session is let go. A run, the
    /// calibration and the metronome carry on (the audio background mode is for them).
    static func releaseInput(player: Player, setup: AudioSetup) {
        setup.pauseListening()
        guard player.mode == .idle else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The tab bar and the sheets' title bars in the house colours: the content's own background, a hairline, no blur.
    private static func styleBars() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = Theme.uiBg
        tab.shadowColor = Theme.uiLine
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = Theme.uiMuted
            item.normal.titleTextAttributes = [.foregroundColor: Theme.uiMuted]
            item.selected.iconColor = Theme.uiAccentText
            item.selected.titleTextAttributes = [.foregroundColor: Theme.uiAccentText]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = Theme.uiBg
        nav.shadowColor = Theme.uiLine
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}

struct RootView: View {
    @EnvironmentObject var player: Player
    @EnvironmentObject var updater: Updater
    @State private var tab = 0

    var body: some View {
        content
            .routeNotice()
            .tint(Theme.accentText)
            .preferredColorScheme(forcedScheme)
            .alert(L.couldNotStartAudio, isPresented: Binding(get: { player.errorText != nil }, set: { if !$0 { player.errorText = nil } })) {
                Button(L.ok, role: .cancel) {}
            } message: { Text(player.errorText ?? "") }
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if let screen = UserDefaults.standard.string(forKey: "screen"), !screen.isEmpty {
            Gallery(screen: screen)
        } else {
            tabs
        }
        #else
        tabs
        #endif
    }

    /// Two tabs, each a line icon of the same weight (the tab bar would otherwise swap in filled ones). Drills holds
    /// the picking drills and the timed routines; Progress and Settings are icons at the top.
    private var tabs: some View {
        TabView(selection: $tab) {
            MetronomeView()
                .tabItem { tabLabel(L.metronome, "metronome") }.tag(0)
            DrillsView()
                .tabItem { tabLabel(L.drills, "waveform") }.tag(1)
        }
    }

    private func tabLabel(_ title: String, _ systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage).environment(\.symbolVariants, .none)
        }
    }

    /// The system's appearance, unless a UI test asks for one (-appearance dark).
    private var forcedScheme: ColorScheme? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
        #else
        return nil
        #endif
    }
}
