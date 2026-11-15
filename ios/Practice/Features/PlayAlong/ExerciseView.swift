import SwiftUI

/// One drill. Ready: what it is and how the run is set up, with one Start. Running: the run screen (RunView).
/// After: the result (ResultView).
struct ExerciseView: View {
    @EnvironmentObject var pa: PlayAlong
    @Environment(\.dismiss) private var dismiss
    @State private var optionsOpen = false

    private var live: Bool { pa.phase == .running || pa.phase == .calibrating || pa.phase == .syncing }
    private var busy: Bool { live || pa.phase == .intro }

    var body: some View {
        VStack(spacing: 0) {
            if !live {
                NavBar(title: pa.exercise.name, backEnabled: !busy, onBack: { pa.clearResult(); dismiss() }) {
                    if pa.phase == .ready {
                        BarIcon(systemImage: "speaker.wave.2", label: "Hear the intro") { pa.repeatIntro() }
                    }
                }
            }
            switch pa.phase {
            case .ready: setup
            case .intro: introView
            case .syncing, .calibrating: CalibrationView()
            case .running: RunView(d: runDisplay) { pa.stop() }
            case .result: resultView
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(busy ? .hidden : .visible, for: .tabBar)
    }

    // MARK: Setup

    private var setup: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    about
                    tempoBlock
                    guideBlock
                    runBlock
                    VStack(spacing: 0) {
                        inputBlock
                        optionsBlock
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.top, Space.xxs)
                .padding(.bottom, Space.xl)
            }
            VStack(spacing: Space.xs) {
                if let m = pa.message {
                    Text(m).font(Typo.sub).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("message")
                }
                PrimaryButton(title: "Start", systemImage: "play.fill") { pa.start() }
                    .accessibilityIdentifier("start")
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.sm)
            .background(alignment: .top) { Hairline() }
        }
    }

    /// What the drill is, without saying its name again, and its pattern.
    private var about: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if !aboutText.isEmpty {
                Text(aboutText).font(Typo.callout).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PatternStrip(exercise: pa.exercise)
        }
    }

    private var aboutText: String {
        let ex = pa.exercise
        if !ex.detail.isEmpty { return ex.detail }
        // The spoken intro opens with the drill's name; the screen already shows it.
        let parts = ex.intro.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 { return parts[1].trimmingCharacters(in: .whitespaces) }
        return ex.intro
    }

    // MARK: Tempo

    private var tempoBlock: some View {
        VStack(spacing: Space.sm) {
            if let max = pa.level() {
                ZoneBar(zones: pa.zones.zones, max: max,
                        chosen: pa.resume ? pa.activeZone?.id : nil,
                        holding: pa.zones.zone(forBPM: Double(pa.startTempo), max: max)?.id) { pa.chooseZone($0) }
            }
            TempoDial(value: pa.startTempo, caption: tempoCaption, size: 88, vertical: false) { pa.nudgeTempo(to: $0) }
            if !pa.exercise.levels.isEmpty { levelMenu }
        }
    }

    /// Under the tempo: what the zone means ("Z3 Tempo · 120–135 bpm"), or where a tempo set by hand sits.
    private var tempoCaption: String {
        if let max = pa.level() {
            if pa.resume, let z = pa.activeZone {
                let r = TempoZones.range(z, max: max)
                return "\(z.name) \(z.title) · \(r.lowerBound)–\(r.upperBound) bpm\n\(Int(z.low))–\(Int(z.high))% of your max, \(max)"
            }
            let pct = Int((Double(pa.startTempo) / Double(max) * 100).rounded())
            return "bpm, set by hand\n\(pct)% of your max, \(max)"
        }
        guard let b = pa.best() else { return "bpm" }
        return pa.session.kind == .endurance ? "bpm · held \(formatClock(b)) here" : "bpm · best \(Int(b))% here"
    }

    /// The drill's own levels, in one menu (they ran off the edge as a row of chips).
    private var levelMenu: some View {
        Menu {
            ForEach(pa.exercise.levels, id: \.self) { lv in
                Button("\(lv.name) · \(lv.bpm) bpm") { pa.apply(lv) }
            }
        } label: {
            HStack(spacing: Space.xxs) {
                Text(currentLevel ?? "Levels")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .font(Typo.subStrong)
            .foregroundStyle(Theme.accentText)
            .frame(minHeight: Space.touch)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Levels")
        .accessibilityValue(currentLevel ?? "None chosen")
        .accessibilityIdentifier("levels")
    }

    private var currentLevel: String? {
        guard !pa.resume || pa.level() == nil else { return nil }
        return pa.exercise.levels.first { $0.bpm == pa.bpm }?.name
    }

    // MARK: Guide and run

    private var guideBlock: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel("Guide")
            Segmented(options: [(true, "Guided"), (false, "Solo")], selection: $pa.guided)
            Text(pa.guided ? "The drill plays with the click; play along with it." : "Just the click.")
                .font(Typo.foot).foregroundStyle(Theme.muted)
        }
    }

    private var runBlock: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel("Run")
            Segmented(options: [(SessionSettings.Kind.cycles, "Cycles"), (SessionSettings.Kind.duration, "Time"),
                                (SessionSettings.Kind.endurance, pa.audioInput ? "Endurance" : "Open")],
                      selection: $pa.session.kind)
            amountRow
            Text(modeLine).font(Typo.foot).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xxs)
        }
    }

    @ViewBuilder
    private var amountRow: some View {
        let s = pa.session
        switch s.kind {
        case .cycles:
            StepperRow(label: "Cycles", value: "\(s.cycles)", canDecrement: s.cycles > 1, canIncrement: s.cycles < 100) {
                pa.session.cycles = min(100, max(1, s.cycles + $0))
            }
        case .duration:
            StepperRow(label: "Length", value: formatClock(Double(s.seconds)), canDecrement: s.seconds > 30, canIncrement: s.seconds < 1800) {
                pa.session.seconds = min(1800, max(30, s.seconds + $0 * 30))
            }
        case .endurance:
            if pa.audioInput {
                StepperRow(label: "Hold your accuracy at", value: "\(s.targetPercent)%", canDecrement: s.targetPercent > 50, canIncrement: s.targetPercent < 100) {
                    pa.session.targetPercent = min(100, max(50, s.targetPercent + $0 * 5))
                }
            }
        }
    }

    private var modeLine: String {
        let s = pa.session
        switch s.kind {
        case .cycles: return "\(s.cycles) time\(s.cycles == 1 ? "" : "s") through the pattern."
        case .duration: return "\(formatClock(Double(s.seconds))) in all."
        case .endurance:
            return pa.audioInput
                ? "Keeps going until your accuracy drops under \(s.targetPercent)%. The score is how long you held it."
                : "Keeps going until you stop it."
        }
    }

    // MARK: Audio input and options

    /// Audio input on: the guitar comes in and the run is scored. Off: the input is never opened and nothing is scored.
    private var inputBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            ToggleRow(label: "Audio input", detail: pa.audioInput ? "Scored" : "Not scored. Only the minutes are kept.",
                      isOn: $pa.audioInput)
            if pa.audioInput, let note = pa.routeNote {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(note).font(Typo.foot).foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if pa.calibration == nil && (pa.interfacePresent || pa.allowPhoneMic) {
                        TextButton(title: "Calibrate", colour: Theme.accentText) { pa.startCalibration() }
                    }
                }
                .padding(.vertical, Space.xs)
                Hairline()
            }
        }
    }

    private var optionsBlock: some View {
        Disclosure(title: "Options", summary: optionsSummary, open: $optionsOpen) {
            let s = pa.session
            if pa.audioInput {
                if s.kind == .endurance {
                    StepperRow(label: "Judged over the last", value: "\(s.windowCycles) cycle\(s.windowCycles == 1 ? "" : "s")",
                               canDecrement: s.windowCycles > 1, canIncrement: s.windowCycles < 8) {
                        pa.session.windowCycles = min(8, max(1, s.windowCycles + $0))
                    }
                } else {
                    StepperRow(label: "A cycle passes at", value: "\(s.targetPercent)%", canDecrement: s.targetPercent > 50, canIncrement: s.targetPercent < 100) {
                        pa.session.targetPercent = min(100, max(50, s.targetPercent + $0 * 5))
                    }
                }
            }
            StepperRow(label: "Ladder", detail: pa.audioInput ? "Faster after each passed cycle" : "Faster after each cycle",
                       value: s.ladderStep == 0 ? "Off" : "+\(s.ladderStep) bpm", canDecrement: s.ladderStep > 0, canIncrement: s.ladderStep < 20) {
                pa.session.ladderStep = min(20, max(0, s.ladderStep + $0 * 2))
            }
            ToggleRow(label: "Click while playing", isOn: $pa.gridClicks)
            ToggleRow(label: "Spoken intro", isOn: $pa.intro)
            if pa.audioInput {
                Row(label: "Sound", detail: "In: \(pa.route.input). Out: \(pa.route.output).") {
                    RoutePicker().frame(width: 36, height: 36)
                        .accessibilityLabel("Choose where the sound goes")
                }
            }
            Row(label: "Timing", detail: offsetLine) {
                TextButton(title: "Calibrate", colour: Theme.accentText) { pa.startCalibration() }
                    .accessibilityIdentifier("calibrate")
            }
        }
    }

    private var optionsSummary: String {
        var parts: [String] = []
        parts.append(pa.session.ladderStep > 0 ? "Ladder +\(pa.session.ladderStep)" : "Ladder off")
        if !pa.gridClicks { parts.append("no click") }
        if !pa.intro { parts.append("no intro") }
        return parts.joined(separator: ", ")
    }

    private var offsetLine: String {
        let sight = Int((pa.displayOffset * 1000).rounded())
        let picture = "Picture \(sight >= 0 ? "+" : "")\(sight) ms."
        guard pa.audioInput else { return picture }
        let ms = Int((pa.currentOffset * 1000).rounded())
        if let c = pa.calibration {
            let steady = c.spreadMs.map { ", steady to \(Int($0.rounded())) ms" } ?? ""
            return "\(picture) Guitar \(ms) ms, calibrated for this setup\(steady)."
        }
        return "\(picture) Guitar about \(ms) ms; calibrate once for this setup."
    }

    // MARK: Intro

    private var introView: some View {
        VStack(spacing: Space.md) {
            Spacer()
            Image(systemName: "speaker.wave.2").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.accentText)
                .accessibilityHidden(true)
            Text("\(pa.startTempo)").font(Typo.number(72)).foregroundStyle(Theme.text)
            Text("bpm, \(pa.guided ? "guided" : "solo")\(pa.audioInput ? "" : ", not scored")")
                .font(Typo.body).foregroundStyle(Theme.muted)
            Spacer()
            HStack(spacing: Space.sm) {
                QuietButton(title: "Stop", systemImage: "stop.fill") { pa.stop() }
                    .frame(maxWidth: 128)
                PrimaryButton(title: "Skip the intro", systemImage: "forward.fill") { pa.skipIntro() }
            }
            .padding(.horizontal, Space.page).padding(.bottom, Space.sm)
        }
    }

    // MARK: Running

    private var runDisplay: RunDisplay {
        let counting = pa.now < pa.countInEnd
        let calibrating = pa.phase == .calibrating
        let scored = pa.lastRunWasScored
        let accuracy = pa.rolling.map { Int(($0 * 100).rounded()) }
        return RunDisplay(
            chip: calibrating ? "Calibrating" : runChip,
            cue: cueText(counting: counting, calibrating: calibrating),
            cueDetail: cueDetail(counting: counting, calibrating: calibrating),
            cueWarn: counting || pa.groupCue?.beatsUntil == 1,
            bpm: Int(pa.currentBPM),
            scored: scored,
            accuracy: accuracy,
            accuracyGood: (accuracy ?? 0) >= pa.runTarget,
            cycle: cycleText(counting: counting),
            clock: clockText(counting: counting),
            clockLabel: clockLabel(counting: counting, scored: scored),
            countingIn: counting,
            calibrating: calibrating,
            notes: pa.notes, played: pa.played, states: pa.states, now: pa.laneNow, beat: 60 / max(1, pa.currentBPM),
            recentErrors: pa.recentErrors, spanMs: pa.timingSpanMs, inputLevel: pa.level)
    }

    /// "Solo · Z3 Tempo · 88% of max"
    private var runChip: String {
        var parts = [pa.lastRunWasGuided ? "Guided" : "Solo"]
        if let m = pa.runZoneMax, m > 0, let z = pa.zones.zone(forBPM: pa.currentBPM, max: m) {
            parts.append("\(z.name) \(z.title)")
            parts.append("\(Int((pa.currentBPM / Double(m) * 100).rounded()))% of max")
        }
        if !pa.lastRunWasScored { parts.append("not scored") }
        return parts.joined(separator: " · ")
    }

    private func cueText(counting: Bool, calibrating: Bool) -> String {
        if counting { return "Count-in" }
        if calibrating { return "One note a click" }
        guard let cue = pa.groupCue else { return pa.exercise.name }
        return groupName(cue.now)
    }

    private func cueDetail(counting: Bool, calibrating: Bool) -> String {
        if calibrating { return "Twelve clicks, one note on each" }
        guard !counting, let cue = pa.groupCue else { return " " }
        return cue.beatsUntil == 1 ? "\(groupName(cue.next)) next beat" : "\(groupName(cue.next)) in \(cue.beatsUntil)"
    }

    private func groupName(_ n: Int) -> String {
        switch n { case 0: return "Rest"; case 2: return "Eighths"; case 3: return "Triplets"; case 4: return "Sixteenths"; default: return "\(n) a beat" }
    }

    private func cycleText(counting: Bool) -> String {
        guard !counting, let n = pa.cycleNumber else { return "--" }
        return pa.runKind == .cycles ? "\(n) of \(max(1, pa.runCycles))" : "\(n)"
    }

    private func clockText(counting: Bool) -> String {
        if counting { return "--" }
        if let end = pa.plannedEnd { return formatClock(max(0, end - pa.now)) }
        return formatClock(max(0, pa.now - pa.countInEnd))
    }

    private func clockLabel(counting: Bool, scored: Bool) -> String {
        if pa.plannedEnd != nil || counting { return "left" }
        return scored && pa.runKind == .endurance ? "held" : "played"
    }

    // MARK: Result

    @ViewBuilder
    private var resultView: some View {
        if let r = pa.score, let s = pa.saved {
            ResultView(score: r, saved: s, guided: pa.lastRunWasGuided, newBest: pa.newBest,
                       maxUp: pa.levelUp.map { ($0.from, $0.to) },
                       primaryTitle: pa.lastRunWasGuided ? "Now solo" : "Again at \(pa.startTempo)",
                       primaryImage: pa.lastRunWasGuided ? "play.fill" : "arrow.clockwise",
                       onPrimary: { if pa.lastRunWasGuided { pa.nowSolo() } else { pa.start() } },
                       onDone: { pa.clearResult() })
        } else if let u = pa.unscored {
            UnscoredResultView(run: u, total: pa.unscoredSeconds[pa.exercise.id] ?? u.seconds,
                               againTitle: "Again at \(pa.startTempo)", onAgain: { pa.start() }, onDone: { pa.clearResult() })
        } else {
            VStack(spacing: Space.md) {
                Spacer()
                Text("No notes were counted.").font(Typo.body).foregroundStyle(Theme.muted)
                Spacer()
                QuietButton(title: "Done") { pa.clearResult() }
                    .padding(.horizontal, Space.page).padding(.bottom, Space.sm)
            }
        }
    }
}

/// The zones of his max, like heart-rate zones: five that always fit, each with the tempos it means. The chosen one
/// is filled; with the tempo set by hand, the zone that tempo sits in is outlined.
struct ZoneBar: View {
    let zones: [TempoZones.Zone]
    let max: Int
    let chosen: String?
    let holding: String?
    let onChoose: (String) -> Void

    var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(zones) { z in
                let on = chosen == z.id
                let range = TempoZones.range(z, max: max)
                Button { onChoose(z.id) } label: {
                    VStack(spacing: 1) {
                        Text(z.name).font(on ? Typo.subStrong : Typo.sub)
                        Text("\(range.lowerBound)–\(range.upperBound)").font(Typo.figure(.caption2))
                            .foregroundStyle(on ? Theme.accentText : Theme.faint)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(on ? Theme.accentSoft : Theme.hover, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(!on && chosen == nil && holding == z.id ? Theme.lineStrong : Color.clear, lineWidth: 1))
                    .foregroundStyle(on ? Theme.accentText : Theme.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("\(z.name), \(z.title), \(range.lowerBound) to \(range.upperBound) beats per minute")
                .accessibilityAddTraits(on ? [.isSelected] : [])
                .accessibilityIdentifier("zone.\(z.id)")
            }
        }
        .sensoryFeedback(.selection, trigger: chosen)
    }
}
