import SwiftUI
import UIKit

@main
struct PracticeApp: App {
    @StateObject private var player: Player
    @StateObject private var playAlong: PlayAlong
    @StateObject private var history: History
    @StateObject private var store = RoutineStore()
    @StateObject private var updater = Updater()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // The UI tests start from a clean slate (the unit tests share this app's settings on the simulator).
        if UserDefaults.standard.bool(forKey: "resetState"), let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        #endif
        let p = Player()
        let h = History()
        let pa = PlayAlong(player: p, history: h)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "seedMax") { pa.seedMaxForScreenshots() }
        #endif
        _player = StateObject(wrappedValue: p)
        _history = StateObject(wrappedValue: h)
        _playAlong = StateObject(wrappedValue: pa)
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
                .task { await updater.check() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await updater.check(); await history.sync() } }
                }
        }
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
            .tint(Theme.accentText)
            .preferredColorScheme(forcedScheme)
            .alert("Sound could not start", isPresented: Binding(get: { player.errorText != nil }, set: { if !$0 { player.errorText = nil } })) {
                Button("OK", role: .cancel) {}
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
                .tabItem { tabLabel("Metronome", "metronome") }.tag(0)
            DrillsView()
                .tabItem { tabLabel("Drills", "waveform") }.tag(1)
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
