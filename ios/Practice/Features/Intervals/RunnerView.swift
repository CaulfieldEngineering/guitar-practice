import SwiftUI

/// A routine running: what to do now, big; the time left in it, bigger; what comes next.
struct RunnerView: View {
    let routine: Routine
    @EnvironmentObject var player: Player
    @EnvironmentObject var store: RoutineStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Routine?

    private var running: Bool { player.mode == .routine && !player.paused }
    private var plan: RoutinePlan { routine.plan }

    var body: some View {
        let s = player.status ?? plan.status(at: 0)
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 36, height: 36)
                }.buttonStyle(.plain)
                Text(routine.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                Button { editing = routine } label: {
                    Image(systemName: "pencil").font(.system(size: 17)).foregroundStyle(Theme.muted).frame(width: 36, height: 36)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)

            if let s {
                content(s)
            } else {
                Spacer()
                Text("This routine has no intervals. Edit it to add some.").font(.system(size: 15)).foregroundStyle(Theme.muted)
                Spacer()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if player.routine != routine { player.load(routine) } }
        .onChange(of: routine) { _, r in player.load(r) }
        .sheet(item: $editing) { r in RoutineEditor(routine: r) { store.upsert($0) } }
    }

    @ViewBuilder
    private func content(_ s: RoutinePlan.Status) -> some View {
        let seg = s.segment
        let isPlay = seg.kind == .play || seg.kind == .countIn
        let colour: Color = s.finished ? Theme.accent : (seg.kind == .play ? Theme.accent : (seg.kind == .countIn ? Theme.warn : Theme.muted))

        VStack(spacing: 6) {
            Text(s.finished ? "Done" : seg.title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(colour)
                .lineLimit(2).multilineTextAlignment(.center)
            if plan.rounds > 1 && !s.finished {
                Text("Round \(seg.round + 1) of \(plan.rounds)").font(.system(size: 15)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, 16)

        Spacer(minLength: 8)

        Text(formatClock(s.timeLeft))
            .font(.system(size: 112, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            .minimumScaleFactor(0.5).lineLimit(1)
            .padding(.horizontal, 16)

        if isPlay && !s.finished {
            Text("\(Int(seg.bpm)) bpm").font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(Theme.text)
        } else {
            Text(" ").font(.system(size: 34))
        }

        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(colour).frame(width: g.size.width * CGFloat(min(1, max(0, s.progress))))
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 24)
        .padding(.top, 16)

        BeatDots(beats: routine.beatsPerBar, current: running && seg.kind == .play ? player.currentBeat : -1)
            .padding(.top, 20)

        Spacer(minLength: 8)

        VStack(spacing: 4) {
            if let n = s.next {
                HStack(spacing: 6) {
                    Text("Next").foregroundStyle(Theme.muted)
                    Text(n.title + ", " + formatClock(n.duration) + (n.kind == .play ? " at \(Int(n.bpm))" : "")).foregroundStyle(Theme.text)
                }
                .font(.system(size: 17))
            }
            Text(s.finished ? "All done. Start again any time." : formatClock(s.totalLeft) + " left in all")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            if !routine.notes.isEmpty {
                Text(routine.notes).font(.system(size: 13)).foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center).padding(.top, 6).padding(.horizontal, 24)
            }
        }

        Spacer(minLength: 12)

        HStack(spacing: 12) {
            IconButton(systemImage: "backward.end.fill", size: 54) { player.skip(forward: false) }
            PrimaryButton(title: player.introPlaying ? "Stop" : (running ? "Pause" : (player.paused ? "Resume" : "Start")),
                          systemImage: running ? "pause.fill" : "play.fill") { player.toggleRoutine() }
            IconButton(systemImage: "forward.end.fill", size: 54) { player.skip(forward: true) }
        }
        .padding(.horizontal, 16)

        HStack(spacing: 24) {
            if player.introPlaying {
                Button("Skip intro") { player.skipIntro() }
            } else {
                Button { player.repeatIntro() } label: { Label("Intro", systemImage: "speaker.wave.2") }
            }
            if player.paused || running { Button("Start over") { player.restartRoutine() } }
        }
        .font(.system(size: 14)).foregroundStyle(Theme.muted)
        .buttonStyle(.plain)
        .padding(.vertical, 12)
    }
}
