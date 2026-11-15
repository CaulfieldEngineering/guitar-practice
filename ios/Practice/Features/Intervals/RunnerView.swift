import SwiftUI

/// A routine running, made to be glanced at with a guitar in hand: what to do now, the time left in it (the biggest
/// thing on the screen), the tempo, and what comes next. Tapping anywhere on the numbers pauses and resumes.
struct RunnerView: View {
    let routine: Routine
    @EnvironmentObject var player: Player
    @EnvironmentObject var store: RoutineStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Routine?

    private var running: Bool { player.mode == .routine && !player.paused }
    private var active: Bool { running || player.paused || player.introPlaying }
    private var plan: RoutinePlan { routine.plan }

    var body: some View {
        let s = player.status ?? plan.status(at: 0)
        VStack(spacing: 0) {
            NavBar(title: routine.name, onBack: { dismiss() }) {
                BarIcon(systemImage: "pencil", label: "Edit the routine") { editing = routine }
            }
            if let s {
                content(s)
            } else {
                Spacer()
                Text("This routine has no intervals. The pencil adds some.")
                    .font(Typo.callout).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, Space.xl)
                Spacer()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(running ? .hidden : .visible, for: .tabBar)
        .onAppear { if player.routine != routine { player.load(routine) } }
        .onChange(of: routine) { _, r in player.load(r) }
        .sheet(item: $editing) { r in RoutineEditor(routine: r) { store.upsert($0) } }
    }

    @ViewBuilder
    private func content(_ s: RoutinePlan.Status) -> some View {
        let seg = s.segment
        let isPlay = seg.kind == .play || seg.kind == .countIn
        let colour: Color = s.finished ? Theme.accentText : (seg.kind == .play ? Theme.accentText : (seg.kind == .countIn ? Theme.warn : Theme.muted))

        // Everything to glance at; a tap on it pauses or resumes.
        VStack(spacing: 0) {
            VStack(spacing: Space.xxs) {
                Text(s.finished ? "Done" : seg.title)
                    .font(Typo.number(34))
                    .foregroundStyle(colour)
                    .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
                Text(plan.rounds > 1 && !s.finished ? "Round \(seg.round + 1) of \(plan.rounds)" : " ")
                    .font(Typo.callout).foregroundStyle(Theme.muted)
            }
            .padding(.top, Space.md)

            Spacer(minLength: Space.xs)

            Text(formatClock(s.timeLeft))
                .font(Typo.number(120))
                .foregroundStyle(Theme.text)
                .minimumScaleFactor(0.4).lineLimit(1)
                .accessibilityLabel("Time left")
                .accessibilityValue(formatClock(s.timeLeft))

            Text(isPlay && !s.finished ? "\(Int(seg.bpm)) bpm" : " ")
                .font(Typo.number(36, weight: .medium))
                .foregroundStyle(Theme.text)

            ProgressLine(fraction: s.progress, colour: seg.kind == .play || s.finished ? Theme.accent : (seg.kind == .countIn ? Theme.warn : Theme.lineStrong), height: 6)
                .padding(.horizontal, Space.xs)
                .padding(.top, Space.lg)

            BeatDots(beats: routine.beatsPerBar, current: running && seg.kind == .play ? player.currentBeat : -1)
                .padding(.top, Space.lg)

            Spacer(minLength: Space.xs)

            VStack(spacing: Space.xxs) {
                if let n = s.next {
                    HStack(spacing: Space.xs) {
                        Text("Next").foregroundStyle(Theme.muted)
                        Text(n.title + ", " + formatClock(n.duration) + (n.kind == .play ? " at \(Int(n.bpm))" : ""))
                            .foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .font(Typo.body)
                }
                Text(s.finished ? "All done. Start again any time." : formatClock(s.totalLeft) + " left in all")
                    .font(Typo.foot).foregroundStyle(Theme.muted)
                if !routine.notes.isEmpty && !running {
                    Text(routine.notes).font(Typo.foot).foregroundStyle(Theme.faint)
                        .multilineTextAlignment(.center).lineLimit(3).padding(.top, Space.xxs)
                }
            }
            Spacer(minLength: Space.sm)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.page)
        .contentShape(Rectangle())
        .onTapGesture {
            guard active else { return }
            Haptics.tap()
            player.toggleRoutine()
        }
        .accessibilityAction(named: running ? "Pause" : "Resume") { if active { player.toggleRoutine() } }

        HStack(spacing: Space.sm) {
            IconButton(systemImage: "backward.end", size: 54, label: "Back an interval") { player.skip(forward: false) }
            PrimaryButton(title: player.introPlaying ? "Stop" : (running ? "Pause" : (player.paused ? "Resume" : "Start")),
                          systemImage: running ? "pause.fill" : "play.fill") { player.toggleRoutine() }
                .accessibilityIdentifier("routine.start")
            IconButton(systemImage: "forward.end", size: 54, label: "On to the next interval") { player.skip(forward: true) }
        }
        .padding(.horizontal, Space.page)

        HStack(spacing: Space.md) {
            if player.introPlaying {
                TextButton(title: "Skip the intro") { player.skipIntro() }
            } else if running {
                Text("Tap anywhere to pause").font(Typo.sub).foregroundStyle(Theme.faint).frame(minHeight: Space.touch)
            } else {
                TextButton(title: "Hear the intro") { player.repeatIntro() }
            }
            if player.paused || running { TextButton(title: "Start over") { player.restartRoutine() } }
        }
        .padding(.bottom, Space.xxs)
    }
}
