import SwiftUI

/// The metronome: the tempo is the screen. Drag on the number, hold the minus or the plus, or tap it in.
struct MetronomeView: View {
    @EnvironmentObject var player: Player

    private var running: Bool { player.mode == .metronome }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: L.metronome)
            RunningBar(own: .metronome)

            Spacer(minLength: Space.xs)
            BeatDots(beats: player.beatsPerBar, current: running ? player.currentBeat : -1)
            Spacer(minLength: Space.sm)

            TempoDial(value: player.bpm, caption: L.bpm, size: 88) { player.setBPM($0) }
                .padding(.horizontal, Space.page)

            Slider(value: Binding(get: { Double(player.bpm) }, set: { player.setBPM(Int($0.rounded())) }), in: 30...300)
                .tint(Theme.accent)
                .padding(.horizontal, Space.page + Space.xxs)
                .padding(.top, Space.sm)
                .accessibilityHidden(true)

            Spacer(minLength: Space.md)

            VStack(spacing: 0) {
                Row(label: L.timeSignature) {
                    Menu {
                        ForEach(meterOptions, id: \.self) { n in
                            Button("\(n)/4") { player.beatsPerBar = n }
                        }
                    } label: {
                        HStack(spacing: Space.xxs) {
                            Text("\(player.beatsPerBar)/4").font(Typo.figure(.body, weight: .medium))
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: Space.touch)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L.timeSignature)
                    .accessibilityValue("\(player.beatsPerBar) 4")
                }
                ToggleRow(label: L.accentFirstBeat, isOn: $player.accent)
                VStack(spacing: Space.xs) {
                    SectionLabel(L.subdivision)
                    Segmented(options: subdivisionOptions, selection: $player.subdivision)
                }
                .padding(.top, Space.md)
            }
            .padding(.horizontal, Space.page)

            Spacer(minLength: Space.md)

            HStack(spacing: Space.sm) {
                QuietButton(title: L.tap, systemImage: "hand.tap") {
                    Haptics.tick()
                    player.tap()
                }
                .frame(maxWidth: 96)
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
    }
}
