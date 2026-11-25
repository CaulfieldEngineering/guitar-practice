import Foundation

// The words of 0.3.0 (the new look, ascending tempo, Challenge, routines, the tuning, X notes). Sentence case, one
// to three words a label, the standard verbs, no full stops on labels. "Loop" is the word for one pass of a drill's
// pattern (Joe, 2026-11-24: "ascend either per loop").
extension L {
    // Common
    static let cancel = "Cancel"
    static let delete = "Delete"
    static let duplicate = "Duplicate"
    static let rename = "Rename"
    static let save = "Save"
    static let name = "Name"
    static let more = "More"
    static let custom = "Custom"
    static let defaultWord = "Default"
    static let notYet = "Not yet"
    static let upToDate = "Up to date"
    static let today = "Today"
    static let total = "total"
    static let date = "Date"
    static let best = "Best"
    static let device = "Device"
    static let showMore = "Show more"
    static let sessions = "Sessions"
    static let routines = "Routines"
    static let screen = "Screen"
    static let guitar = "Guitar"
    static let tuning = "Tuning"
    static let strings = "Strings"
    static let copyFrom = "Copy from a preset"
    static let customTuning = "Custom tuning"
    static func stringNumber(_ n: Int) -> String { "String \(n)" }
    static func defaultTuning(_ name: String) -> String { "Default, \(name)" }
    static func bpmValue(_ n: Int) -> String { "\(n) bpm" }
    static func plusBPM(_ n: Int) -> String { "+\(n) bpm" }
    static func secondsValue(_ n: Int) -> String { n < 60 ? "\(n) s" : formatClock(Double(n)) }
    static func minutes(_ seconds: Double) -> String { "\(max(1, Int((seconds / 60).rounded()))) min" }
    static func routeShort(_ input: String, _ output: String) -> String { "In \(input), out \(output)" }

    // Metronome
    static let accent = "Accent"
    static let accentOne = "Beat 1"
    static let accentGroups = "Group starts"
    static let clickSound = "Click sound"
    static let clickLevel = "Click level"
    static func soundName(_ s: SessionSettings.ClickSound) -> String {
        switch s { case .click: return "Click"; case .wood: return "Wood block"; case .beep: return "Beep"; case .rim: return "Rim" }
    }
    static func accentName(_ a: SessionSettings.Accent) -> String {
        switch a { case .one: return accentOne; case .groups: return accentGroups; case .off: return off }
    }

    // Drills and setup
    static let noDrills = "No drills. Pull down to update"
    static let tempoZone = "Tempo zone"
    static let manual = "Manual"
    static let noMaxYet = "No max yet"
    static func percentOfMaxLine(_ pct: Int, _ max: Int) -> String { "\(pct)% of max \(max)" }
    static let ascendingTempo = "Ascending tempo"
    static let length = "Length"
    static let guideNotes = "Guide notes"
    static let clickOn = "Click on"
    static let scoring = "Scoring"
    static func patternLine(_ runs: [(Int, Int)]) -> String {
        let parts = runs.map { r -> String in
            let what: String
            switch r.0 { case 0: what = "rest"; case 1: what = "quarters"; case 2: what = "eighths"; case 3: what = "triplets"; case 4: what = "16ths"; default: what = "\(r.0) a beat" }
            return r.1 == 1 ? "1 beat of \(what)" : "\(r.1) beats of \(what)"
        }
        guard let first = parts.first else { return "" }
        let s = parts.count == 1 ? first : parts.dropLast().joined(separator: ", ") + ", then " + parts.last!
        return s.prefix(1).uppercased() + s.dropFirst()
    }
    static func groupName(_ n: Int) -> String {
        switch n { case 0: return rest; case 2: return eighths; case 3: return triplets; case 4: return "16ths"; default: return perBeat(n) }
    }

    // Ascending tempo
    static let perLoop = "Per loop"
    static let byAccuracy = "By accuracy"
    static let usesAudioInput = "Uses audio input"
    static let range = "Range"
    static let startTempo = "Start"
    static let endTempo = "End"
    static let step = "Step"
    static let atTheTop = "At the top"
    static let hold = "Hold"
    static let restart = "Restart"
    static let steps = "Steps"
    static let count = "Count"
    static let loops = "Loops"
    static let seconds = "Seconds"
    static let every = "Every"
    static let speedUp = "Speed up"
    static let slowDown = "Slow down"
    static let atOrAbove = "At or above"
    static let below = "Below"
    static let forWindow = "For"
    static let lowest = "Lowest"
    static let breakTitle = "Break"
    static let autoBreak = "Auto break"
    static let breakLength = "Break length"
    static let resumeSlower = "Resume one step slower"
    static let stability = "Stability"
    static let waitAfterChange = "Wait after a change"
    static let stabilityFooter = "The thresholds stay at least 5 points apart"
    static func loopCount(_ n: Int) -> String { n == 1 ? "1 loop" : "\(n) loops" }
    static func barCount(_ n: Int) -> String { n == 1 ? "1 bar" : "\(n) bars" }
    static func planSummary(_ p: TempoPlan, start: Int, top: Int) -> String {
        switch p.mode {
        case .off: return off
        case .perLoop:
            let every = p.everyUnit == .loops ? (p.every == 1 ? "loop" : "\(p.every) loops") : secondsValue(p.every)
            return "+\(p.step) every \(every) to \(top)"
        case .accuracy: return "By accuracy to \(top)"
        }
    }

    // Length
    static let loopsTitle = "Loops"
    static let holdAccuracy = "Hold accuracy"
    static let untilStopped = "Until stopped"
    static let challenge = "Challenge"
    static let challengeFooter = "The clock counts only while the accuracy holds"
    static let earn = "Earn"
    static let over = "Over"
    static let cap = "Most time"
    static let holdShort = "Hold"
    static func lengthSummary(_ s: SessionSettings, scored: Bool) -> String {
        switch s.kind {
        case .cycles, .routine: return loopCount(s.cycles)
        case .duration: return formatClock(Double(s.seconds))
        case .endurance: return scored ? "Hold \(s.targetPercent)%" : untilStopped
        case .challenge: return "\(formatClock(Double(s.seconds))) at \(s.targetPercent)%"
        }
    }

    // Options
    static let gapTrainer = "Gap trainer"
    static let gapFooter = "The click is muted on that bar; the notes still count"
    static func gapName(_ n: Int) -> String {
        switch n { case 0: return off; case 2: return "Every 2nd bar"; case 3: return "Every 3rd bar"; default: return "Every \(n)th bar" }
    }
    static func optionsSummary(_ s: SessionSettings, intro: Bool) -> String {
        var parts: [String] = []
        if s.countInBars != 1 { parts.append(s.countInBars == 0 ? "No count-in" : "Count-in \(barCount(s.countInBars))") }
        if s.gapEvery > 0 { parts.append("gaps") }
        if s.clickSound != .click { parts.append(soundName(s.clickSound).lowercased()) }
        if s.accent != .one { parts.append(s.accent == .off ? "no accent" : "group accents") }
        if let t = s.tuning { parts.append(t.name) }
        if !intro { parts.append("no intro") }
        guard let first = parts.first else { return "" }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + parts.dropFirst()).joined(separator: ", ")
    }

    // Run
    static let countInWord = "Count-in"
    static func targetBPM(_ n: Int) -> String { "Target \(n)" }
    static func nextBPM(_ n: Int) -> String { "Next \(n)" }
    static func loopOf(_ n: Int, _ total: Int) -> String { "Loop \(n) of \(total)" }
    static func loopN(_ n: Int) -> String { "Loop \(n)" }
    static func leftClock(_ clock: String) -> String { "\(clock) left" }
    static func ofLoops(_ n: Int, _ total: Int) -> String { "\(n) of \(loopCount(total))" }
    static func clockOf(_ a: Double, _ b: Double) -> String { "\(formatClock(a)) of \(formatClock(b))" }
    static func zoneWord(_ z: TempoPlan.Zone) -> String {
        switch z { case .up: return "Up"; case .hold: return "Hold"; case .down: return "Down"; case .rest: return "Break" }
    }
    static func stepState(_ s: PlayAlong.StepInfo.State) -> String {
        switch s {
        case .perLoop: return "Next step"
        case .up: return "Speeding up"
        case .hold: return "Holding"
        case .down: return "Slowing down"
        case .rest: return "Break"
        case .settling: return "Settling"
        case .top: return "Top tempo"
        }
    }
    static func earnedOf(_ a: String, _ b: String) -> String { "\(a) of \(b)" }
    static let clockRunning = "Clock running"
    static let clockHeld = "Clock held, accuracy under the line"
    static func inZoneShare(_ elapsed: String, _ pct: Int) -> String { "\(elapsed) elapsed, \(pct)% in the zone" }
    static let restYourHand = "Rest your hand"
    static func resumesAt(_ bpm: Int) -> String { "Resumes at \(bpm) bpm" }

    // Result
    static func resultSummary(guided: Bool, start: Int, top: Int, seconds: Double) -> String {
        "\(guided ? "Guided" : "Solo"), \(tempoRange(start, top)) bpm, \(formatMinutes(seconds))"
    }
    static func accuracyPassMarkLine(_ pass: Int) -> String { "accuracy, pass mark \(pass)%" }
    static func earnedAt(_ pct: Int) -> String { "earned at \(pct)%" }
    static let aboutNumbers = "About the numbers"
    static let timingAnchorsLong = "Timing is how far each pick lands from the note, in milliseconds. The average is the calibration's: near 0 means the latency is right. The spread is yours: session players hold 10 to 15 ms, good amateurs 20 to 30, beginners 40 to 60. A note earns full credit inside a tight window and less the further off it is, both windows a share of the gap to the next note. A missed note earns nothing; each extra note counts as one more note that earned nothing. A pitched note played on the wrong pitch earns nothing; a × note takes any pitch."
    static let spread = "Spread"
    static func spreadValue(_ ms: Int, _ band: String) -> String { "\(ms) ms, \(band.lowercased())" }
    static let extraNotes = "Extra notes"
    static let missed = "Missed"
    static let wrongNotes = "Wrong notes"
    static let accents = "Accents"
    static let topTempo = "Top tempo"
    static let breaksRow = "Breaks"
    static let inZone = "In the zone"
    static let bestStreak = "Best streak"
    static let notScoredLine = "Audio input off, not scored"

    // Calibration
    static func stepOf(_ n: Int, _ total: Int) -> String { "Step \(n) of \(total)" }
    static let lineUpMarks = "Line up the marks"
    static let lineUpHelp = "Move the slider until each mark crosses the line on the click"
    static let playOnTheLine = "Play on the line"
    static let playOnLineHelp = "Play one note as each mark crosses the line"
    static let heard = "Heard"

    // Routines
    static let columnRoutine = "Routine"
    static let columnBlocks = "Blocks"
    static let columnBlock = "Block"
    static let columnSession = "Session"
    static let noRoutines = "No routines. Tap + to make one"
    static let newRoutine = "New routine"
    static let deleteRoutineQuestion = "Delete this routine?"
    static let deleteBlockQuestion = "Delete this block?"
    static let addBlock = "Add block"
    static let warmUp = "Warm-up"
    static let drill = "Drill"
    static let openPractice = "Open practice"
    static let customBlock = "Custom"
    static func blockKind(_ k: RoutineBlock.Kind) -> String {
        switch k { case .warmup: return warmUp; case .drill: return drill; case .rest: return breakTitle; case .free: return openPractice; case .custom: return customBlock }
    }
    static func blocksAbout(_ n: Int, _ time: String) -> String { "\(n == 1 ? "1 block" : "\(n) blocks"), about \(time)" }
    static func blockCount(_ n: Int) -> String { n == 1 ? "1 block" : "\(n) blocks" }
    static func blockOf(_ n: Int, _ total: Int) -> String { "\(n) of \(total)" }
    static let nextWord = "Next"
    static let lastBlock = "Last block"
    static let restartBlock = "Restart block"
    static let endRoutine = "End routine"
    static let endRoutineQuestion = "End the routine? What is done is saved."
    static let skipped = "Skipped"
    static func routineSummaryLine(_ blocks: Int, _ played: Int, _ date: Date) -> String {
        "\(blockCount(blocks)), \(played) played, \(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }
    static func routineScoreLine(_ acc: Int, _ top: Int?) -> String {
        top.map { "Accuracy \(acc)%, top tempo \($0) bpm" } ?? "Accuracy \(acc)%"
    }

    // Progress
    static let noSessions = "No sessions yet. Run a drill and it shows here"
    static let allDevices = "All devices"
    static let thisPhoneOnly = "This phone only. The drill server could not be reached"
    static let bpmMax = "bpm max"
    static let unscoredTime = "Unscored time"

    // Settings
    static let phoneMicrophone = "Phone microphone"
    static let phoneMicFooter = "Phone microphone is for testing without an interface"
    static let blockChime = "Block chime"
    static let countdownTicks = "Countdown ticks"
    static let runsWaiting = "Runs waiting"
}
