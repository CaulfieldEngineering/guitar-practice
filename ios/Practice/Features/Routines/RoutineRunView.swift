import SwiftUI

/// A routine as a guided session, one frame for every state so nothing jumps: along the top, which block of how many
/// and a line of the blocks; in the middle the block (a drill's run screen, or the block's name and its time left
/// big), or between blocks the next one with 3, 2, 1; at the bottom what is next, and Back, Pause, Skip. Finished:
/// the routine as one session, each block with its tempo and accuracy.
struct RoutineRunView: View {
    @EnvironmentObject var runner: RoutineRunner
    @EnvironmentObject var pa: PlayAlong
    @EnvironmentObject var player: Player
    @State private var confirmEnd = false

    var body: some View {
        Group {
            if let rec = runner.record { finished(rec) } else { running }
        }
        .background(Theme.bg.ignoresSafeArea())
        .confirmationDialog(L.endRoutineQuestion, isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(L.end, role: .destructive) { runner.endNow() }
            Button(L.cancel, role: .cancel) {}
        }
    }

    // MARK: Running

    private var running: some View {
        let st = runner.state
        let paused = st.paused || (runner.block?.kind == .drill && pa.phase == .paused)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L.blockOf(min(st.index + 1, runner.routine?.blocks.count ?? 0), runner.routine?.blocks.count ?? 0) + "  " + (runner.routine?.name ?? ""))
                    .font(Typo.sub).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                RoutePicker().frame(width: 44, height: 44).accessibilityLabel(L.chooseOutput)
            }
            .frame(height: 44)
            .padding(.horizontal, Space.page)
            segments.padding(.horizontal, Space.page)

            ZStack {
                middle(st)
                    .opacity(paused ? 0.4 : 1)
                if paused {
                    VStack(alignment: .leading) {
                        Spacer()
                        Text(L.paused).font(Typo.cue).foregroundStyle(Theme.text)
                        if let m = pa.message, runner.block?.kind == .drill {
                            Text(m).font(Typo.sub).foregroundStyle(Theme.warn).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, Space.page)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                if let n = runner.nextBlock {
                    Text(L.nextWord).foregroundStyle(Theme.muted)
                    Text(n.title(drills: runner.drills)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer()
                    Text(lengthText(n)).font(Typo.figure(.subheadline)).foregroundStyle(Theme.muted)
                } else {
                    Text(L.lastBlock).foregroundStyle(Theme.muted)
                    Spacer()
                }
            }
            .font(Typo.sub)
            .frame(height: 28)
            .padding(.horizontal, Space.page)

            if paused {
                VStack(spacing: Space.xs) {
                    PrimaryButton(title: L.resume, systemImage: "play.fill") { resume() }
                        .accessibilityIdentifier("runner.resume")
                    HStack {
                        TextButton(title: L.restartBlock, colour: Theme.text) { runner.back() }
                        Spacer()
                        TextButton(title: L.endRoutine, colour: Theme.danger) { confirmEnd = true }
                            .accessibilityIdentifier("runner.end")
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.xs)
            } else {
                HStack(spacing: Space.xs) {
                    IconButton(systemImage: "backward.end.fill", label: L.back) { runner.back() }
                    QuietButton(title: L.pause, systemImage: "pause.fill") { pause() }
                        .accessibilityIdentifier("runner.pause")
                    IconButton(systemImage: "forward.end.fill", label: L.skip) { runner.skip() }
                        .accessibilityIdentifier("runner.skip")
                }
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.xs)
            }
        }
    }

    private func pause() {
        if runner.block?.kind == .drill && pa.phase == .resting { return }
        runner.pause()
    }

    private func resume() {
        if runner.state.paused { runner.resume() } else if pa.phase == .paused { pa.resumeRun() }
    }

    /// One segment a block, as wide as its share of the routine; done ones muted, the current one filling.
    private var segments: some View {
        let est = runner.estimates
        let total = max(1, est.reduce(0, +))
        return GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(est.indices, id: \.self) { i in
                    let w = max(4, (g.size.width - CGFloat(est.count - 1) * 2) * CGFloat(est[i] / total))
                    ZStack(alignment: .leading) {
                        Rectangle().fill(i < runner.clock.index ? Theme.muted : Theme.lineStrong)
                        if i == runner.clock.index {
                            Rectangle().fill(Theme.accent).frame(width: w * CGFloat(runner.fraction(of: i)))
                        }
                    }
                    .frame(width: w, height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func middle(_ st: RoutineClock.State) -> some View {
        if st.countdownTick != nil {
            countdown(st)
        } else if let b = runner.block {
            if b.kind == .drill {
                drillMiddle
            } else {
                plainMiddle(b, left: st.left ?? 0)
            }
        }
    }

    private func countdown(_ st: RoutineClock.State) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Spacer()
            Text(L.nextWord).font(Typo.foot).foregroundStyle(Theme.muted)
            Text(runner.block?.title(drills: runner.drills) ?? "").font(Typo.cue).foregroundStyle(Theme.text)
            if let b = runner.block { Text(summary(b)).font(Typo.sub).foregroundStyle(Theme.muted) }
            Text("\(st.countdownTick ?? 0)").font(Typo.tempoHero).foregroundStyle(Theme.text)
                .contentTransition(.numericText())
                .accessibilityIdentifier("runner.countdown")
            Spacer()
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var drillMiddle: some View {
        switch pa.phase {
        case .running, .paused:
            RunView(d: RunDisplay.from(pa, beat: player.currentBeat), paused: false, showsControls: false,
                    onPause: {}, onResume: {}, onEnd: {})
        case .resting:
            BreakView(left: pa.breakLeft, length: pa.breakLength, resumeBPM: pa.resumeBPM, showsControls: true,
                      onSkip: { pa.endBreak() }, onStop: { runner.skip() })
        case .intro:
            Text(L.countInWord).font(Typo.cue).foregroundStyle(Theme.muted).padding(Space.page)
        default:
            VStack(alignment: .leading, spacing: Space.xs) {
                Spacer()
                Text(runner.block?.title(drills: runner.drills) ?? "").font(Typo.cue)
                if let m = pa.message { Text(m).font(Typo.sub).foregroundStyle(Theme.warn) }
                Spacer()
            }
            .padding(.horizontal, Space.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func plainMiddle(_ b: RoutineBlock, left: Double) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Spacer()
            Text(b.title(drills: runner.drills)).font(Typo.cue).foregroundStyle(Theme.text)
            Text(formatClock(left.rounded(.up))).font(Typo.tempoHero).foregroundStyle(Theme.text)
                .contentTransition(.numericText())
                .accessibilityIdentifier("runner.clock")
            if b.kind != .rest && b.click {
                Text(L.bpmValue(b.bpm)).font(Typo.stat).foregroundStyle(Theme.text)
                BeatBar(beats: 4, current: player.blockClickBPM != nil ? player.currentBeat : -1).padding(.top, Space.xs)
            }
            Spacer()
        }
        .padding(.horizontal, Space.page)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(_ b: RoutineBlock) -> String {
        if b.kind == .drill, let d = b.drill {
            let p = d.session.tempoPlan
            let tempo: String
            if p.mode != .off, let ex = runner.drills.first(where: { $0.id == b.drillID }) {
                tempo = L.tempoRange(d.bpm, p.normalized.bounds(start: d.bpm, rule: ex.tempo).top) + " " + L.bpm
            } else {
                tempo = L.bpmValue(d.bpm)
            }
            return tempo + ", " + lengthText(b)
        }
        if b.click { return L.bpmValue(b.bpm) + ", " + formatClock(Double(b.seconds)) }
        return formatClock(Double(b.seconds))
    }

    private func lengthText(_ b: RoutineBlock) -> String {
        guard b.kind == .drill, let s = b.drill?.session else { return formatClock(Double(b.seconds)) }
        switch s.kind {
        case .cycles, .routine: return L.loopCount(s.cycles)
        case .duration, .challenge: return formatClock(Double(s.seconds))
        case .endurance: return L.holdShort
        }
    }

    // MARK: Finished

    private func finished(_ rec: RoutineRunRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Text(rec.routineName).font(Typo.title)
                Spacer()
            }
            .frame(height: 44)
            .overlay(alignment: .trailing) {
                Button(L.done) { runner.close() }.font(Typo.bodyStrong).foregroundStyle(Theme.accentText)
                    .padding(.trailing, Space.page)
                    .accessibilityIdentifier("runner.done")
            }
            ScrollView {
                RoutineRunSummary(record: rec).padding(.horizontal, Space.page)
            }
            PrimaryButton(title: L.again, systemImage: "arrow.clockwise") {
                if let r = runner.routine { runner.start(r, drills: runner.drills) }
            }
            .padding(.horizontal, Space.page).padding(.bottom, Space.xs)
        }
    }
}

/// A routine run, as one session: when, how long, the accuracy and top tempo of its drill blocks, and each block.
struct RoutineRunSummary: View {
    let record: RoutineRunRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.routineSummaryLine(record.blocks.count, record.blocks.filter { !$0.skipped }.count, record.date))
                .font(Typo.sub).foregroundStyle(Theme.muted).padding(.top, Space.sm)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(formatClock(record.seconds)).font(Typo.statLarge).foregroundStyle(Theme.text)
                Text(L.total).font(Typo.body).foregroundStyle(Theme.muted)
            }
            .padding(.top, Space.xs)
            let scored = record.blocks.compactMap(\.accuracy)
            if !scored.isEmpty {
                Text(L.routineScoreLine(scored.reduce(0, +) / scored.count, record.blocks.compactMap(\.topBPM).max()))
                    .font(Typo.body).foregroundStyle(Theme.text).padding(.top, Space.xs)
            }
            ColumnHeads(first: L.columnBlock, columns: [(L.tempo, 84), (L.accuracy, 72)])
                .padding(.horizontal, -Space.page).padding(.top, Space.lg)
            Hairline()
            ForEach(record.blocks.indices, id: \.self) { i in
                let b = record.blocks[i]
                let tempo = b.startBPM.map { s in L.tempoRange(s, b.topBPM ?? s) } ?? ""
                TableRow(name: b.name, values: [(b.skipped ? "" : tempo, 84), (b.skipped ? L.skipped : (b.accuracy.map { L.percent($0) } ?? "–"), 72)],
                         faintValues: true)
                    .padding(.horizontal, -Space.page)
                Hairline()
            }
        }
    }
}
