import SwiftUI

struct MetronomeView: View {
    @EnvironmentObject var player: Player
    @State private var dragStart: Int?

    private var running: Bool { player.mode == .metronome }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Metronome")
            Spacer(minLength: 8)
            BeatDots(beats: player.beatsPerBar, current: running ? player.currentBeat : -1)
            Spacer(minLength: 16)

            HStack(spacing: 16) {
                IconButton(systemImage: "minus", size: 52) { player.bpm -= 1 }
                VStack(spacing: 0) {
                    Text("\(player.bpm)")
                        .font(.system(size: 96, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text("bpm").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { g in
                        if dragStart == nil { dragStart = player.bpm }
                        player.bpm = (dragStart ?? player.bpm) + Int((-g.translation.height + g.translation.width) / 6)
                    }
                    .onEnded { _ in dragStart = nil })
                .accessibilityLabel("\(player.bpm) beats per minute. Drag up or down to change.")
                IconButton(systemImage: "plus", size: 52) { player.bpm += 1 }
            }
            .padding(.horizontal, 16)

            Slider(value: Binding(get: { Double(player.bpm) }, set: { player.bpm = Int($0.rounded()) }), in: 30...300)
                .tint(Theme.accent)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Spacer(minLength: 16)

            VStack(spacing: 12) {
                Row(label: "Time signature") {
                    Menu {
                        ForEach(meterOptions, id: \.self) { n in
                            Button("\(n)/4") { player.beatsPerBar = n }
                        }
                    } label: {
                        Text("\(player.beatsPerBar)/4").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.accent)
                    }
                }
                Row(label: "Accent the one") {
                    Toggle("", isOn: $player.accent).labelsHidden().tint(Theme.accent)
                }
                VStack(spacing: 8) {
                    SectionLabel("Clicks per beat")
                    Segmented(options: subdivisionOptions, selection: $player.subdivision)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 16)

            HStack(spacing: 12) {
                QuietButton(title: "Tap", systemImage: "hand.tap") { player.tap() }
                    .frame(maxWidth: 120)
                PrimaryButton(title: running ? "Stop" : "Start", systemImage: running ? "stop.fill" : "play.fill") {
                    player.toggleMetronome()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
