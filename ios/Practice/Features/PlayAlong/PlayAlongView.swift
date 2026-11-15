import SwiftUI

struct PlayAlongView: View {
    @EnvironmentObject var pa: PlayAlong
    @State private var showStats = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Play along") {
                Button { showStats = true } label: {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 17)).foregroundStyle(Theme.muted).frame(width: 36, height: 36)
                }.buttonStyle(.plain)
            }
            switch pa.phase {
            case .ready: setup
            case .intro: introView
            case .running, .calibrating: live
            case .result: resultView
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showStats) { StatsView() }
        .task { await pa.refresh() }
    }

    // MARK: Setup

    private var setup: some View {
        ScrollView {
            VStack(spacing: 12) {
                Segmented(options: [(true, "Guided"), (false, "Solo")], selection: $pa.guided)
                Text(pa.guided ? "The exercise plays with the click; play along with it." : "Just the click. Same scoring.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)

                SectionLabel("Exercise").padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(pa.exercises) { ex in exerciseRow(ex) }
                }
                if let note = pa.catalogNote {
                    Text(note).font(.system(size: 12)).foregroundStyle(Theme.faint).frame(maxWidth: .infinity, alignment: .leading)
                }

                if !pa.exercise.levels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(pa.exercise.levels, id: \.self) { lv in
                                Button { pa.apply(lv) } label: {
                                    Text("\(lv.name), \(lv.bpm)").font(.system(size: 13, weight: .medium))
                                        .padding(.horizontal, 12).frame(height: 30)
                                        .background(Theme.hover, in: Capsule()).foregroundStyle(Theme.text)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                SectionLabel("Tempo").padding(.top, 8)
                HStack(spacing: 16) {
                    IconButton(systemImage: "minus") { pa.bpm -= 2 }
                    VStack(spacing: 0) {
                        Text("\(pa.bpm)").font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.text)
                        Text(bestLine).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    IconButton(systemImage: "plus") { pa.bpm += 2 }
                }

                SectionLabel("Run").padding(.top, 8)
                Segmented(options: [(SessionSettings.Kind.cycles, "Cycles"), (SessionSettings.Kind.duration, "Time"), (SessionSettings.Kind.endurance, "Endurance")],
                          selection: $pa.session.kind)
                VStack(spacing: 0) {
                    switch pa.session.kind {
                    case .cycles:
                        Row(label: "Cycles") { Stepper("\(pa.session.cycles)", value: $pa.session.cycles, in: 1...100).fixedSize() }
                    case .duration:
                        Row(label: "Length") { Stepper(formatClock(Double(pa.session.seconds)), value: $pa.session.seconds, in: 15...1800, step: 15).fixedSize() }
                    case .endurance:
                        Row(label: "Over the last") { Stepper("\(pa.session.windowCycles) cycles", value: $pa.session.windowCycles, in: 1...8).fixedSize() }
                    }
                    Row(label: "A cycle passes at") { Stepper("\(pa.session.targetPercent)%", value: $pa.session.targetPercent, in: 50...100, step: 5).fixedSize() }
                    Row(label: "Within") { Stepper("\(Int(pa.session.toleranceMs)) ms", value: $pa.session.toleranceMs, in: 10...80, step: 5).fixedSize() }
                    Row(label: "Faster each passed cycle") {
                        Stepper(pa.session.ladderStep == 0 ? "Off" : "+\(pa.session.ladderStep)", value: $pa.session.ladderStep, in: 0...20, step: 2).fixedSize()
                    }
                    Row(label: "Click while playing") { Toggle("", isOn: $pa.gridClicks).labelsHidden().tint(Theme.accent) }
                }
                Text(modeLine).font(.system(size: 13)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("In: \(pa.route.input). Out: \(pa.route.output).").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    if pa.route.phoneSpeakerAndMic {
                        Text("On the speaker the phone hears its own sound. Headphones or an interface work best.")
                            .font(.system(size: 13)).foregroundStyle(Theme.warn)
                    }
                    HStack {
                        Text(pa.offset.map { "Timing offset \(Int(($0 * 1000).rounded())) ms, calibrated." } ?? "Not calibrated yet.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        Spacer()
                        Button("Calibrate") { pa.calibrate() }.font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent)
                    }
                    if let m = pa.message { Text(m).font(.system(size: 13)).foregroundStyle(Theme.text) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                PrimaryButton(title: "Start, \(pa.guided ? "guided" : "solo")", systemImage: "play.fill") { pa.start() }
                    .padding(.top, 8)
                Button { pa.repeatIntro() } label: {
                    Label("Hear the intro", systemImage: "speaker.wave.2").font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await pa.refresh() }
    }

    private func exerciseRow(_ ex: Exercise) -> some View {
        VStack(spacing: 0) {
            Button { pa.exerciseID = ex.id } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: pa.exerciseID == ex.id ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(pa.exerciseID == ex.id ? Theme.accent : Theme.faint)
                        .font(.system(size: 18)).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                        Text(ex.detail).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if let f = pa.fastestPass(ex.id) {
                        Text("\(f)").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private var bestLine: String {
        guard let b = pa.best() else { return "bpm" }
        return pa.session.kind == .endurance ? "Held \(formatClock(b)) here" : "Best here: \(Int(b))"
    }

    private var modeLine: String {
        let s = pa.session
        switch s.kind {
        case .cycles: return "\(s.cycles) times through the pattern."
        case .duration: return "\(formatClock(Double(s.seconds))) in all."
        case .endurance: return "Keep going until fewer than \(s.targetPercent)% of notes land within \(Int(s.toleranceMs)) ms over \(s.windowCycles) cycles. Your score is the time you held it."
        }
    }

    // MARK: Intro

    private var introView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "speaker.wave.2").font(.system(size: 34)).foregroundStyle(Theme.accent)
            Text(pa.exercise.name).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Text("\(pa.bpm) bpm, \(pa.guided ? "guided" : "solo")").font(.system(size: 15)).foregroundStyle(Theme.muted)
            Spacer()
            HStack(spacing: 12) {
                QuietButton(title: "Stop", systemImage: "stop.fill") { pa.stop() }
                PrimaryButton(title: "Skip intro", systemImage: "forward.fill") { pa.skipIntro() }
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Running

    private var live: some View {
        VStack(spacing: 10) {
            HStack {
                Text(pa.phase == .calibrating ? "Calibrating" : (pa.lastRunWasGuided ? "Guided" : "Solo"))
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Theme.accentSoft, in: Capsule()).foregroundStyle(Theme.accent)
                Spacer()
                Text("\(Int(pa.currentBPM)) bpm").font(.system(size: 15, weight: .medium)).monospacedDigit().foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 16)

            Text(pa.phase == .calibrating ? "Play one note on each click." : pa.exercise.name)
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)

            HStack(alignment: .firstTextBaseline) {
                Text(clockText)
                    .font(.system(size: 52, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(pa.now < pa.countInEnd ? Theme.warn : Theme.text)
                Spacer()
                if pa.phase == .running {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(pa.rolling.map { "\(Int(($0 * 100).rounded()))%" } ?? "--")
                            .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(accuracyColour)
                        Text("within \(Int(pa.session.toleranceMs)) ms").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(.horizontal, 16)

            if let cue = pa.groupCue {
                HStack(spacing: 12) {
                    Text(cue.now == 3 ? "Triplets" : (cue.now == 4 ? "Sixteenths" : "\(cue.now) a beat"))
                        .font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                    Text(cue.beatsUntil == 1 ? "Next beat: \(cue.next)" : "\(cue.next) in \(cue.beatsUntil)")
                        .font(.system(size: 15)).monospacedDigit()
                        .foregroundStyle(cue.beatsUntil == 1 ? Theme.warn : Theme.muted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(cue.beatsUntil == 1 ? Theme.warn.opacity(0.12) : Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
            }

            LaneView(notes: pa.notes, played: pa.played, states: pa.states, now: pa.now, beat: 60 / max(1, pa.currentBPM))
                .frame(height: 170)
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                Text("Input").font(.system(size: 12)).foregroundStyle(Theme.muted)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule().fill(Theme.accent).frame(width: g.size.width * CGFloat(min(1, max(0, (20 * log10(Double(max(pa.level, 1e-5))) + 60) / 60))))
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 16)

            Spacer()
            QuietButton(title: "Stop", systemImage: "stop.fill") { pa.stop() }
                .padding(.horizontal, 16).padding(.bottom, 16)
        }
    }

    private var clockText: String {
        if pa.now < pa.countInEnd { return "Count-in" }
        if let end = pa.plannedEnd { return formatClock(max(0, end - pa.now)) }
        return formatClock(max(0, pa.now - pa.countInEnd))
    }

    private var accuracyColour: Color {
        guard let r = pa.rolling else { return Theme.muted }
        return r * 100 >= Double(pa.session.targetPercent) ? Theme.accent : Theme.warn
    }

    // MARK: Result

    private var resultView: some View {
        ScrollView {
            if let r = pa.score, let s = pa.saved {
                VStack(spacing: 14) {
                    Text(pa.lastRunWasGuided ? "Guided" : "Solo")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Theme.accentSoft, in: Capsule()).foregroundStyle(Theme.accent)
                        .padding(.top, 12)
                    if s.mode == "endurance" {
                        Text(formatClock(s.sustainedSeconds ?? 0))
                            .font(.system(size: 96, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Theme.accent)
                        Text("held at \(s.targetPercent)% within \(Int(s.toleranceMs)) ms").font(.system(size: 14)).foregroundStyle(Theme.muted)
                    } else {
                        Text("\(r.score)")
                            .font(.system(size: 104, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(r.passed ? Theme.accent : Theme.text)
                    }
                    if pa.newBest { Text("A new best at this tempo.").font(.system(size: 14)).foregroundStyle(Theme.accent) }

                    VStack(spacing: 0) {
                        if s.topBPM > s.startBPM { Row(label: "Tempo") { stat("\(s.startBPM) to \(s.topBPM) bpm") } }
                        Row(label: "Within \(Int(s.toleranceMs)) ms") { stat("\(s.accuracyPercent)%") }
                        Row(label: "Within \(Int(s.tightMs)) ms") { stat("\(r.pct20)%") }
                        Row(label: "Within \(Int(s.closeMs)) ms") { stat("\(r.pct40)%") }
                        Row(label: "Missed") { stat("\(r.missed) of \(r.expected)") }
                        Row(label: "Extra notes") { stat("\(r.extra)") }
                        Row(label: "On average") {
                            stat(abs(r.meanError) < 3 ? "right on the click" : "\(Int(abs(r.meanError).rounded())) ms \(r.meanError > 0 ? "behind" : "ahead")")
                        }
                        Row(label: "Spread") { stat("\(Int(r.spread.rounded())) ms") }
                        if let a = s.accentsPercent { Row(label: "Accents that stood out") { stat("\(a)%") } }
                    }
                    .padding(.horizontal, 16)

                    ErrorStrip(errors: r.errors).frame(height: 60).padding(.horizontal, 16)

                    if pa.lastRunWasGuided {
                        PrimaryButton(title: "Now solo", systemImage: "play.fill") { pa.nowSolo() }.padding(.horizontal, 16)
                    } else {
                        PrimaryButton(title: "Again at \(pa.bpm)", systemImage: "arrow.clockwise") { pa.start() }.padding(.horizontal, 16)
                    }
                    QuietButton(title: "Done", height: 48) { pa.clearResult() }.padding(.horizontal, 16).padding(.bottom, 16)
                }
            } else {
                VStack(spacing: 12) {
                    Text("No notes were counted.").font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.top, 40)
                    QuietButton(title: "Done", height: 48) { pa.clearResult() }.padding(.horizontal, 16)
                }
            }
        }
    }

    private func stat(_ s: String) -> some View {
        Text(s).font(.system(size: 15).monospacedDigit()).foregroundStyle(Theme.muted)
    }
}

/// Every note of the run, early above the line and late below, so a drift shows at a glance.
struct ErrorStrip: View {
    let errors: [Double?]
    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            ctx.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(Theme.lineStrong))
            guard !errors.isEmpty else { return }
            let step = size.width / CGFloat(errors.count)
            for (i, e) in errors.enumerated() {
                let x = (CGFloat(i) + 0.5) * step
                guard let e else {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: mid - 1.5, width: 3, height: 3)), with: .color(Theme.danger))
                    continue
                }
                let y = mid + CGFloat(max(-60, min(60, e)) / 60) * (mid - 2)
                let c = abs(e) <= 20 ? Theme.accent : (abs(e) <= 40 ? Theme.accent.opacity(0.55) : Theme.warn)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(c))
            }
        }
    }
}
