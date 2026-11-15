import SwiftUI

/// One drill. Ready: what it is and how the run is set up, with one Start. Running: the run screen (RunView).
/// After: the result (ResultView). The words are in Shared/Strings.swift.
struct ExerciseView: View {
    @EnvironmentObject var pa: PlayAlong
    @Environment(\.dismiss) private var dismiss
    @State private var optionsOpen = false

    private var live: Bool { pa.phase == .running || pa.phase == .paused || pa.phase == .calibrating || pa.phase == .syncing }
    private var busy: Bool { live || pa.phase == .intro }

    var body: some View {
        VStack(spacing: 0) {
            if !live {
                NavBar(title: pa.exercise.name, backEnabled: !busy, onBack: { pa.clearResult(); dismiss() }) {
                    if pa.phase == .ready {
                        BarIcon(systemImage: "speaker.wave.2", label: L.hearIntro) { pa.repeatIntro() }
                    }
                }
            }
            switch pa.phase {
            case .ready: setup
            case .intro: introView
            case .syncing, .calibrating: CalibrationView()
            case .running, .paused:
                RunView(d: runDisplay, paused: pa.phase == .paused, message: pa.message, route: routeText,
                        onPause: { pa.pause() }, onResume: { pa.resumeRun() }, onEnd: { pa.endRun() })
            case .result: resultView
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(busy ? .hidden : .visible, for: .tabBar)
        // Leaving the drill ends what is going on in it: nothing keeps playing behind another screen.
        .onDisappear { pa.leave() }
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
                        routeBlock
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
                PrimaryButton(title: L.start, systemImage: "play.fill") { pa.start() }
                    .accessibilityIdentifier("start")
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.sm)
            .background(alignment: .top) { Hairline() }
        }
    }

    /// What the drill is (the catalog's own words), and its pattern.
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
                return L.zoneCaption("\(z.name) \(z.title)", r.lowerBound, r.upperBound, Int(z.low), Int(z.high), max)
            }
            return L.manualCaption(Int((Double(pa.startTempo) / Double(max) * 100).rounded()), max)
        }
        guard let b = pa.best() else { return L.bpm }
        return L.bestHere(pa.session.kind == .endurance ? formatClock(b) : L.percent(Int(b)))
    }

    /// The drill's own levels, in one menu.
    private var levelMenu: some View {
        Menu {
            ForEach(pa.exercise.levels, id: \.self) { lv in
                Button(L.levelItem(lv.name, lv.bpm)) { pa.apply(lv) }
            }
        } label: {
            HStack(spacing: Space.xxs) {
                Text(currentLevel ?? L.levels)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .font(Typo.subStrong)
            .foregroundStyle(Theme.accentText)
            .frame(minHeight: Space.touch)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(L.levels)
        .accessibilityValue(currentLevel ?? L.none)
        .accessibilityIdentifier("levels")
    }

    private var currentLevel: String? {
        guard !pa.resume || pa.level() == nil else { return nil }
        return pa.exercise.levels.first { $0.bpm == pa.bpm }?.name
    }

    // MARK: Guide and run

    private var guideBlock: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(L.guide)
            Segmented(options: [(true, L.guided), (false, L.solo)], selection: $pa.guided)
            Text(pa.guided ? L.guidedHelp : L.soloHelp)
                .font(Typo.foot).foregroundStyle(Theme.muted)
        }
    }

    private var runBlock: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(L.run)
            Segmented(options: [(SessionSettings.Kind.cycles, L.cycles), (SessionSettings.Kind.duration, L.time),
                                (SessionSettings.Kind.endurance, pa.audioInput ? L.endurance : L.open)],
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
            StepperRow(label: L.cycles, value: "\(s.cycles)", canDecrement: s.cycles > 1, canIncrement: s.cycles < 100) {
                pa.session.cycles = min(100, max(1, s.cycles + $0))
            }
        case .duration:
            StepperRow(label: L.duration, value: formatClock(Double(s.seconds)), canDecrement: s.seconds > 30, canIncrement: s.seconds < 1800) {
                pa.session.seconds = min(1800, max(30, s.seconds + $0 * 30))
            }
        case .routine:
            StepperRow(label: L.rounds, value: "\(s.cycles)", canDecrement: s.cycles > 1, canIncrement: s.cycles < 50) {
                pa.session.cycles = min(50, max(1, s.cycles + $0))
            }
        case .endurance:
            if pa.audioInput {
                StepperRow(label: L.targetAccuracy, value: L.percent(s.targetPercent), canDecrement: s.targetPercent > 50, canIncrement: s.targetPercent < 100) {
                    pa.session.targetPercent = min(100, max(50, s.targetPercent + $0 * 5))
                }
            }
        }
    }

    private var modeLine: String {
        let s = pa.session
        switch s.kind {
        case .cycles: return L.modeCycles(s.cycles)
        case .duration: return L.modeTime(formatClock(Double(s.seconds)))
        case .routine: return L.modeRounds(s.cycles)
        case .endurance: return pa.audioInput ? L.modeEndurance(s.targetPercent) : L.modeOpen
        }
    }

    // MARK: Audio input, where the sound goes, and options

    /// Audio input on: the guitar comes in and the run is scored. Off: the input is never opened and nothing is scored.
    private var inputBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            ToggleRow(label: L.audioInput, detail: pa.audioInput ? L.scored : L.notScored, isOn: $pa.audioInput)
            if pa.audioInput, let note = pa.routeNote {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(note).font(Typo.foot).foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if pa.calibration == nil && (pa.interfacePresent || pa.allowPhoneMic) {
                        TextButton(title: L.calibrate, colour: Theme.accentText) { pa.startCalibration() }
                    }
                }
                .padding(.vertical, Space.xs)
                Hairline()
            }
        }
    }

    /// Where the sound comes in and goes out, said plainly, with the system's own picker to send it to the
    /// headphones, the interface or the speaker (an interface that is plugged in takes the sound unless told
    /// otherwise). One line more when iOS has put the sound on the interface.
    private var routeBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Row(label: L.audioRoute, detail: routeText, divider: pa.outputNote == nil) {
                RoutePicker().frame(width: 40, height: 40)
                    .accessibilityLabel(L.chooseOutput)
                    .accessibilityIdentifier("route")
            }
            if let note = pa.outputNote {
                Text(note).font(Typo.foot).foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Space.xs)
                Hairline()
            }
        }
    }

    private var routeText: String {
        pa.audioInput ? L.route(pa.route.input, pa.route.output) : L.output(pa.route.output)
    }

    private var optionsBlock: some View {
        Disclosure(title: L.options, summary: optionsSummary, open: $optionsOpen) {
            let s = pa.session
            if pa.audioInput {
                if s.kind == .endurance {
                    StepperRow(label: L.accuracyWindow, value: L.cycleCount(s.windowCycles),
                               canDecrement: s.windowCycles > 1, canIncrement: s.windowCycles < 8) {
                        pa.session.windowCycles = min(8, max(1, s.windowCycles + $0))
                    }
                } else {
                    StepperRow(label: L.passMark, value: L.percent(s.targetPercent), canDecrement: s.targetPercent > 50, canIncrement: s.targetPercent < 100) {
                        pa.session.targetPercent = min(100, max(50, s.targetPercent + $0 * 5))
                    }
                }
            }
            StepperRow(label: L.ladder, detail: pa.audioInput ? L.ladderScoredHelp : L.ladderUnscoredHelp,
                       value: s.ladderStep == 0 ? L.off : L.bpmStep(s.ladderStep), canDecrement: s.ladderStep > 0, canIncrement: s.ladderStep < 20) {
                pa.session.ladderStep = min(20, max(0, s.ladderStep + $0 * 2))
            }
            ToggleRow(label: L.click, isOn: $pa.gridClicks)
            ToggleRow(label: L.voiceIntro, isOn: $pa.intro)
            Row(label: L.timing, detail: timingLine) {
                TextButton(title: L.calibrate, colour: Theme.accentText) { pa.startCalibration() }
                    .accessibilityIdentifier("calibrate")
            }
        }
    }

    private var optionsSummary: String {
        var parts: [String] = []
        parts.append(pa.session.ladderStep > 0 ? L.ladderSummary(pa.session.ladderStep) : L.ladderOff)
        if !pa.gridClicks { parts.append(L.noClick) }
        if !pa.intro { parts.append(L.noIntro) }
        return parts.joined(separator: ", ")
    }

    private var timingLine: String {
        L.timingLine(display: Int((pa.displayOffset * 1000).rounded()),
                     input: pa.audioInput ? Int((pa.currentOffset * 1000).rounded()) : nil,
                     calibrated: pa.calibration != nil)
    }

    // MARK: Intro

    private var introView: some View {
        VStack(spacing: Space.md) {
            Spacer()
            Image(systemName: "speaker.wave.2").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.accentText)
                .accessibilityHidden(true)
            Text("\(pa.startTempo)").font(Typo.number(72)).foregroundStyle(Theme.text)
            Text(L.introLine(guided: pa.guided, scored: pa.audioInput))
                .font(Typo.body).foregroundStyle(Theme.muted)
            Spacer()
            HStack(spacing: Space.sm) {
                QuietButton(title: L.stop, systemImage: "stop.fill") { pa.stop() }
                    .frame(maxWidth: 128)
                    .accessibilityIdentifier("intro.stop")
                PrimaryButton(title: L.skip, systemImage: "forward.fill") { pa.skipIntro() }
                    .accessibilityIdentifier("intro.skip")
            }
            .padding(.horizontal, Space.page).padding(.bottom, Space.sm)
        }
    }

    // MARK: Running

    private var runDisplay: RunDisplay {
        let counting = pa.countingIn
        let scored = pa.lastRunWasScored
        let accuracy = pa.rolling.map { Int(($0 * 100).rounded()) }
        let block = pa.blockNow
        return RunDisplay(
            chip: runChip,
            cue: block?.title ?? cueText(counting: counting),
            cueDetail: block.map { $0.next.map(L.upNext) ?? " " } ?? cueDetail(counting: counting),
            cueWarn: counting || pa.groupCue?.beatsUntil == 1,
            bpm: Int(pa.currentBPM),
            scored: scored,
            accuracy: accuracy,
            accuracyGood: (accuracy ?? 0) >= pa.runTarget,
            cycle: block.map { L.ofTotal($0.round, $0.rounds) } ?? cycleText(counting: counting),
            cycleLabel: block == nil ? L.cycle : L.round,
            clock: block.map { formatClock($0.left) } ?? clockText(counting: counting),
            clockLabel: block == nil ? clockLabel(counting: counting, scored: scored) : L.left,
            countingIn: counting,
            calibrating: false,
            notes: pa.notes, played: pa.played, states: pa.states, now: pa.laneNow, beat: 60 / max(1, pa.currentBPM),
            recentErrors: pa.recentErrors, spanMs: pa.timingSpanMs, inputLevel: pa.level)
    }

    /// "Solo · Z3 Tempo · 88% of max"
    private var runChip: String {
        var parts = [pa.lastRunWasGuided ? L.guided : L.solo]
        if let m = pa.runZoneMax, m > 0, let z = pa.zones.zone(forBPM: pa.currentBPM, max: m) {
            parts.append("\(z.name) \(z.title)")
            parts.append(L.percentOfMax(Int((pa.currentBPM / Double(m) * 100).rounded())))
        }
        if !pa.lastRunWasScored { parts.append(L.chipNotScored) }
        return parts.joined(separator: " · ")
    }

    private func cueText(counting: Bool) -> String {
        if counting { return L.countIn }
        guard let cue = pa.groupCue else { return pa.exercise.short.isEmpty ? pa.exercise.name : pa.exercise.short }
        return groupName(cue.now)
    }

    private func cueDetail(counting: Bool) -> String {
        guard !counting, let cue = pa.groupCue else { return " " }
        return cue.beatsUntil == 1 ? L.nextBeat(groupName(cue.next)) : L.inBeats(groupName(cue.next), cue.beatsUntil)
    }

    private func groupName(_ n: Int) -> String {
        switch n {
        case 0: return L.rest
        case 2: return L.eighths
        case 3: return L.triplets
        case 4: return L.sixteenths
        default: return L.perBeat(n)
        }
    }

    private func cycleText(counting: Bool) -> String {
        guard !counting, let n = pa.cycleNumber else { return "--" }
        return pa.runKind == .cycles ? L.ofTotal(n, max(1, pa.runCycles)) : "\(n)"
    }

    private func clockText(counting: Bool) -> String {
        if counting { return "--" }
        if let end = pa.plannedEnd { return formatClock(max(0, end - pa.now)) }
        return formatClock(max(0, pa.now - pa.countInEnd))
    }

    private func clockLabel(counting: Bool, scored: Bool) -> String {
        if pa.plannedEnd != nil || counting { return L.left }
        return scored && pa.runKind == .endurance ? L.held : L.elapsed
    }

    // MARK: Result

    @ViewBuilder
    private var resultView: some View {
        if let r = pa.score, let s = pa.saved {
            ResultView(score: r, saved: s, guided: pa.lastRunWasGuided, newBest: pa.newBest,
                       maxUp: pa.levelUp.map { ($0.from, $0.to) },
                       primaryTitle: pa.lastRunWasGuided ? L.playSolo : L.again,
                       primaryImage: pa.lastRunWasGuided ? "play.fill" : "arrow.clockwise",
                       onPrimary: { if pa.lastRunWasGuided { pa.nowSolo() } else { pa.start() } },
                       onDone: { pa.clearResult() })
        } else if let u = pa.unscored {
            UnscoredResultView(run: u, total: pa.unscoredSeconds[pa.exercise.id] ?? u.seconds,
                               againTitle: L.again, onAgain: { pa.start() }, onDone: { pa.clearResult() })
        } else {
            VStack(spacing: Space.md) {
                Spacer()
                Text(L.noNotes).font(Typo.body).foregroundStyle(Theme.muted)
                Spacer()
                QuietButton(title: L.done) { pa.clearResult() }
                    .accessibilityIdentifier("result.done")
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
                .accessibilityLabel(L.zoneSpoken(z.name, z.title, range.lowerBound, range.upperBound))
                .accessibilityAddTraits(on ? [.isSelected] : [])
                .accessibilityIdentifier("zone.\(z.id)")
            }
        }
        .sensoryFeedback(.selection, trigger: chosen)
    }
}
