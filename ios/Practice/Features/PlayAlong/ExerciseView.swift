import SwiftUI

/// One drill: what it is, how the run is set up (guide, mode, tempo, ladder, intro), one Start. While it runs, the
/// same screen shows the live numbers and the lane; after, the result.
struct ExerciseView: View {
    @EnvironmentObject var pa: PlayAlong
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    if pa.phase == .ready || pa.phase == .result { pa.clearResult(); dismiss() }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .opacity(pa.phase == .ready || pa.phase == .result ? 1 : 0.3)
                .accessibilityLabel("Back")
                Text(pa.exercise.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 48)

            switch pa.phase {
            case .ready: setup
            case .intro: introView
            case .running, .calibrating: live
            case .result: resultView
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Setup

    private var setup: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(pa.exercise.intro.isEmpty ? pa.exercise.detail : pa.exercise.intro)
                        .font(.system(size: 15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if !pa.exercise.levels.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(pa.exercise.levels, id: \.self) { lv in
                                    Button { pa.apply(lv) } label: {
                                        Text(lv.name).font(.system(size: 13, weight: .medium))
                                            .padding(.horizontal, 12).frame(height: 30)
                                            .background(lv.bpm == pa.bpm ? Theme.accentSoft : Theme.hover, in: Capsule())
                                            .foregroundStyle(lv.bpm == pa.bpm ? Theme.accent : Theme.text)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    tempo

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Guide")
                        Segmented(options: [(true, "Guided"), (false, "Solo")], selection: $pa.guided)
                        Text(pa.guided ? "The drill plays with the click; play along with it." : "Just the click. Same scoring.")
                            .font(.system(size: 13)).foregroundStyle(Theme.faint)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Run")
                        Segmented(options: [(SessionSettings.Kind.cycles, "Cycles"), (SessionSettings.Kind.duration, "Time"),
                                            (SessionSettings.Kind.endurance, "Endurance")], selection: $pa.session.kind)
                        VStack(spacing: 0) {
                            switch pa.session.kind {
                            case .cycles:
                                Row(label: "Cycles") { Stepper("\(pa.session.cycles)", value: $pa.session.cycles, in: 1...100).fixedSize() }
                            case .duration:
                                Row(label: "Length") { Stepper(formatClock(Double(pa.session.seconds)), value: $pa.session.seconds, in: 30...1800, step: 30).fixedSize() }
                            case .endurance:
                                Row(label: "Hold") { Stepper("\(pa.session.targetPercent)%", value: $pa.session.targetPercent, in: 50...100, step: 5).fixedSize() }
                                Row(label: "Over the last") { Stepper("\(pa.session.windowCycles) cycles", value: $pa.session.windowCycles, in: 1...8).fixedSize() }
                            }
                            Row(label: "Within") { Stepper("\(Int(pa.session.toleranceMs)) ms", value: $pa.session.toleranceMs, in: 10...80, step: 5).fixedSize() }
                            Row(label: "Faster each passed cycle") {
                                Stepper(pa.session.ladderStep == 0 ? "Off" : "+\(pa.session.ladderStep)", value: $pa.session.ladderStep, in: 0...20, step: 2).fixedSize()
                            }
                            Row(label: "Click while playing") { Toggle("", isOn: $pa.gridClicks).labelsHidden().tint(Theme.accent) }
                            Row(label: "Spoken intro") { Toggle("", isOn: $pa.intro).labelsHidden().tint(Theme.accent) }
                        }
                        Text(modeLine).font(.system(size: 13)).foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    audioSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            PrimaryButton(title: "Start", systemImage: "play.fill") { pa.start() }
                .accessibilityIdentifier("start")
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var tempo: some View {
        if pa.level() != nil {
            Segmented(options: [(true, "Zones"), (false, "Manual")], selection: $pa.resume)
            if pa.resume {
                HStack(spacing: 6) {
                    ForEach(pa.zones.zones) { z in
                        let on = pa.activeZone?.id == z.id
                        Button { pa.zoneChoice = z.id } label: {
                            Text(z.name).font(.system(size: 13, weight: on ? .semibold : .regular))
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .background(on ? Theme.accentSoft : Theme.hover, in: Capsule())
                                .foregroundStyle(on ? Theme.accent : Theme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                VStack(spacing: 2) {
                    Text("\(pa.startTempo)").font(.system(size: 72, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text(pa.zoneLine ?? "").font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            } else {
                manualTempo
            }
        } else {
            manualTempo
        }
    }

    private var manualTempo: some View {
        HStack(spacing: 20) {
            IconButton(systemImage: "minus", size: 48) { pa.setBPM(pa.bpm - 2) }
            VStack(spacing: 2) {
                Text("\(pa.bpm)").font(.system(size: 72, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.text).contentTransition(.numericText())
                Text(bestLine).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            IconButton(systemImage: "plus", size: 48) { pa.setBPM(pa.bpm + 2) }
        }
        .padding(.vertical, 4)
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Sound")
            HStack(spacing: 8) {
                Text("In: \(pa.route.input). Out: \(pa.route.output).").font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                RoutePicker().frame(width: 32, height: 32)
            }
            if let note = pa.routeNote { Text(note).font(.system(size: 13)).foregroundStyle(Theme.warn) }
            HStack {
                Text(offsetLine).font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                Button("Calibrate") { pa.calibrate() }.font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent)
            }
            if let m = pa.message {
                Text(m).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).accessibilityIdentifier("message")
            }
        }
    }

    private var offsetLine: String {
        let ms = Int((pa.currentOffset * 1000).rounded())
        return pa.calibration != nil ? "Timing offset \(ms) ms, calibrated." : "Timing offset about \(ms) ms; calibrate once."
    }

    private var bestLine: String {
        guard let b = pa.best() else { return "bpm" }
        return pa.session.kind == .endurance ? "bpm, held \(formatClock(b)) here" : "bpm, best \(Int(b)) here"
    }

    private var modeLine: String {
        let s = pa.session
        switch s.kind {
        case .cycles: return "\(s.cycles) times through the pattern. A cycle passes at \(s.targetPercent)% within \(Int(s.toleranceMs)) ms."
        case .duration: return "\(formatClock(Double(s.seconds))) in all."
        case .endurance: return "Keep going until fewer than \(s.targetPercent)% of notes land within \(Int(s.toleranceMs)) ms over \(s.windowCycles) cycles. Your score is the time you held it."
        }
    }

    // MARK: Intro

    private var introView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "speaker.wave.2").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.accent)
            Text("\(pa.startTempo) bpm, \(pa.guided ? "guided" : "solo")").font(.system(size: 17)).foregroundStyle(Theme.muted)
            Spacer()
            HStack(spacing: 12) {
                QuietButton(title: "Stop", systemImage: "stop.fill") { pa.stop() }
                PrimaryButton(title: "Skip intro", systemImage: "forward.fill") { pa.skipIntro() }
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    // MARK: Running

    private var live: some View {
        VStack(spacing: 18) {
            Text(pa.phase == .calibrating ? "Calibrating: one note on each of the twelve clicks" : runChip)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 26)
                .background(Theme.accentSoft, in: Capsule()).foregroundStyle(Theme.accent)

            Text(cueText)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(cueWarn ? Theme.warn : Theme.text)
                .contentTransition(.opacity)
                .frame(height: 48)
            Text(cueDetail).font(.system(size: 15)).monospacedDigit().foregroundStyle(Theme.muted).frame(height: 18)

            HStack(spacing: 0) {
                bigStat("\(Int(pa.currentBPM))", "bpm", Theme.text)
                bigStat(pa.rolling.map { "\(Int(($0 * 100).rounded()))%" } ?? "--", "within \(Int(pa.session.toleranceMs)) ms", accuracyColour)
                bigStat(clockText, pa.plannedEnd == nil && pa.now >= pa.countInEnd ? "held" : "left", pa.now < pa.countInEnd ? Theme.warn : Theme.text)
            }

            LaneView(notes: pa.notes, played: pa.played, states: pa.states, now: pa.now, beat: 60 / max(1, pa.currentBPM))
                .frame(height: 150)

            HStack(spacing: 8) {
                Text("Input").font(.system(size: 12)).foregroundStyle(Theme.faint)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule().fill(Theme.accent).frame(width: g.size.width * meterFraction(pa.level))
                    }
                }
                .frame(height: 3)
            }

            Spacer()
            QuietButton(title: "Stop", systemImage: "stop.fill") { pa.stop() }
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// "Solo · Z3 Tempo · 88% of max"
    private var runChip: String {
        var parts = [pa.lastRunWasGuided ? "Guided" : "Solo"]
        if let m = pa.runZoneMax, m > 0, let z = pa.zones.zone(forBPM: pa.currentBPM, max: m) {
            parts.append("\(z.name) \(z.title)")
            parts.append("\(Int((pa.currentBPM / Double(m) * 100).rounded()))% of max")
        }
        return parts.joined(separator: " · ")
    }

    private func bigStat(_ value: String, _ label: String, _ colour: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(colour).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var cueText: String {
        if pa.now < pa.countInEnd { return "Count-in" }
        guard let cue = pa.groupCue else { return pa.phase == .calibrating ? "Play on the click" : pa.exercise.name }
        return groupName(cue.now)
    }

    private var cueWarn: Bool { pa.now < pa.countInEnd || (pa.groupCue?.beatsUntil == 1) }

    private var cueDetail: String {
        guard pa.now >= pa.countInEnd, let cue = pa.groupCue else { return " " }
        return cue.beatsUntil == 1 ? "\(groupName(cue.next)) next beat" : "\(groupName(cue.next)) in \(cue.beatsUntil)"
    }

    private func groupName(_ n: Int) -> String {
        switch n { case 0: return "Rest"; case 2: return "Eighths"; case 3: return "Triplets"; case 4: return "Sixteenths"; default: return "\(n) a beat" }
    }

    private var clockText: String {
        if pa.now < pa.countInEnd { return "--" }
        if let end = pa.plannedEnd { return formatClock(max(0, end - pa.now)) }
        return formatClock(max(0, pa.now - pa.countInEnd))
    }

    private var accuracyColour: Color {
        guard let r = pa.rolling else { return Theme.muted }
        return r * 100 >= Double(pa.session.targetPercent) ? Theme.accent : Theme.warn
    }

    /// The input level as a fraction of a 60 dB scale.
    private func meterFraction(_ level: Float) -> CGFloat {
        let db = 20 * log10(Double(max(level, 1e-5)))
        let f = (db + 60) / 60
        return CGFloat(min(1, max(0, f)))
    }

    // MARK: Result

    private var resultView: some View {
        VStack(spacing: 0) {
            ScrollView {
                if let r = pa.score, let s = pa.saved {
                    VStack(spacing: 12) {
                        Text(pa.lastRunWasGuided ? "Guided" : "Solo")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12).frame(height: 26)
                            .background(Theme.accentSoft, in: Capsule()).foregroundStyle(Theme.accent)
                            .padding(.top, 8)
                        if s.mode == "endurance" {
                            Text(formatClock(s.sustainedSeconds ?? 0))
                                .font(.system(size: 88, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.accent)
                            Text("held at \(s.targetPercent)% within \(Int(s.toleranceMs)) ms").font(.system(size: 14)).foregroundStyle(Theme.muted)
                        } else {
                            Text("\(r.score)")
                                .font(.system(size: 96, weight: .semibold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(r.passed ? Theme.accent : Theme.text)
                        }
                        if pa.newBest { Text("A new best at this tempo.").font(.system(size: 14)).foregroundStyle(Theme.accent) }
                        if let up = pa.levelUp {
                            Text(up.from > 0 ? "Your max is now \(up.to), up from \(up.from)." : "Your max is now \(up.to).")
                                .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.accent)
                        }

                        VStack(spacing: 0) {
                            if s.topBPM > s.startBPM { Row(label: "Tempo") { stat("\(s.startBPM) to \(s.topBPM) bpm") } }
                            Row(label: "Within \(Int(s.toleranceMs)) ms") { stat("\(s.accuracyPercent)%") }
                            Row(label: "Within \(Int(s.tightMs)) ms") { stat("\(r.pct20)%") }
                            Row(label: "Within \(Int(s.closeMs)) ms") { stat("\(r.pct40)%") }
                            Row(label: "Missed") { stat("\(r.missed) of \(r.expected)") }
                            Row(label: "Extra notes") { stat("\(r.extra)") }
                            Row(label: "On average") { stat(averageText(r.meanError)) }
                            Row(label: "Spread") { stat("\(Int(r.spread.rounded())) ms") }
                            if let a = s.accentsPercent { Row(label: "Accents that stood out") { stat("\(a)%") } }
                        }
                        ErrorStrip(errors: r.errors).frame(height: 56)
                    }
                    .padding(.horizontal, 20)
                } else {
                    Text("No notes were counted.").font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.top, 40)
                }
            }
            VStack(spacing: 8) {
                if pa.lastRunWasGuided {
                    PrimaryButton(title: "Now solo", systemImage: "play.fill") { pa.nowSolo() }
                } else {
                    PrimaryButton(title: "Again at \(pa.startTempo)", systemImage: "arrow.clockwise") { pa.start() }
                }
                Button("Done") { pa.clearResult() }.font(.system(size: 15)).foregroundStyle(Theme.muted).frame(height: 36)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
    }

    private func averageText(_ e: Double) -> String {
        abs(e) < 3 ? "right on the click" : "\(Int(abs(e).rounded())) ms \(e > 0 ? "behind" : "ahead")"
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
