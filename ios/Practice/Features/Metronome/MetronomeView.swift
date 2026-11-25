import SwiftUI

/// The metronome: the tempo is the screen. One big plain numeral, left-aligned; drag on it, hold the minus or the
/// plus, the slider, or Tap. The beat bar above it; the four settings as value rows under it; Tap and Start at the
/// bottom.
struct MetronomeView: View {
    @EnvironmentObject var player: Player

    private var running: Bool { player.mode == .metronome && player.blockClickBPM == nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RunningBar(own: .metronome)
                BeatBar(beats: player.beatsPerBar, current: running ? player.currentBeat : -1,
                        accented: player.accent ? 0 : -1)
                    .padding(.horizontal, Space.page)
                    .padding(.top, Space.lg)

                TempoBlock(value: player.bpm, font: Typo.tempoHero) { player.setBPM($0) }
                    .padding(.leading, Space.page)
                    .padding(.trailing, Space.xs)
                    .padding(.top, Space.md)
                    .accessibilityIdentifier("metronome.tempo")

                Slider(value: Binding(get: { Double(player.bpm) }, set: { player.setBPM(Int($0.rounded())) }), in: 30...300)
                    .tint(Theme.accent)
                    .padding(.horizontal, Space.page)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Hairline().padding(.top, Space.md)
                    FlatValueRow(label: L.timeSignature, value: "\(player.beatsPerBar)/4") {
                        ChoiceList(title: L.timeSignature, options: meterOptions.map { ($0, "\($0)/4", nil) }, selection: $player.beatsPerBar)
                    }
                    FlatValueRow(label: L.subdivision, value: subdivisionOptions.first { $0.0 == player.subdivision }?.1 ?? "") {
                        ChoiceList(title: L.subdivision, options: subdivisionOptions.map { ($0.0, $0.1, nil) }, selection: $player.subdivision)
                    }
                    FlatValueRow(label: L.accent, value: player.accent ? L.accentOne : L.off) {
                        ChoiceList(title: L.accent, options: [(false, L.off, nil), (true, L.accentOne, nil)], selection: $player.accent)
                    }
                    FlatValueRow(label: L.clickSound, value: L.soundName(player.clickSound)) {
                        ChoiceList(title: L.clickSound, options: SessionSettings.ClickSound.allCases.map { ($0, L.soundName($0), nil) },
                                   selection: $player.clickSound)
                    }
                }
                .padding(.leading, Space.page)

                Spacer(minLength: Space.md)

                HStack(spacing: Space.sm) {
                    QuietButton(title: L.tap, systemImage: "hand.tap") { Haptics.tapTempo(); player.tap() }
                        .frame(width: 104)
                        .accessibilityLabel(L.tapTempo)
                    PrimaryButton(title: running ? L.stop : L.start, systemImage: running ? "stop.fill" : "play.fill") {
                        player.toggleMetronome()
                    }
                    .accessibilityIdentifier("metronome.start")
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.md)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(L.metronome)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { SettingsButton() } }
        }
    }
}

/// A flat value row: the label, the value in the muted colour, a chevron; a hairline under it from the label's
/// edge. Pushes its detail.
struct FlatValueRow<Destination: View>: View {
    let label: String
    let value: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: Space.xs) {
                Text(label).font(Typo.body).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: Space.xs)
                Text(value).font(Typo.figure(.body)).foregroundStyle(Theme.muted).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.faint)
            }
            .padding(.trailing, Space.page)
            .frame(minHeight: Control.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .overlay(alignment: .bottom) { Hairline() }
    }
}
