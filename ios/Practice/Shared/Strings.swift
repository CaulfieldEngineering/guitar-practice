import Foundation

/// Every word the app shows, in one place, so it can be read through and changed in one sitting (Joe, on 0.1.6:
/// "Weird labels like 'Done, keep this'"). The rules: a button is one or two plain words, the standard iOS ones
/// where there is one (Start, Stop, Pause, Resume, End, Done, Next, Skip, Calibrate, Search); no commas and no
/// explanation inside a button; helper text only where it is needed, and one short line. A drill's own name,
/// description and levels come from the catalog, not from here.
enum L {
    // MARK: Shared
    static let done = "Done"
    static let start = "Start"
    static let stop = "Stop"
    static let pause = "Pause"
    static let resume = "Resume"
    static let end = "End"
    static let next = "Next"
    static let skip = "Skip"
    static let again = "Again"
    static let back = "Back"
    static let update = "Update"
    static let settings = "Settings"
    static let calibrate = "Calibrate"
    static let search = "Search"
    static let off = "Off"
    static let bpm = "bpm"
    static let tempo = "Tempo"
    static let slower = "Slower"
    static let faster = "Faster"
    static let none = "–"
    static func beatsPerMinute(_ n: Int) -> String { "\(n) beats per minute" }

    // MARK: Tabs
    static let metronome = "Metronome"
    static let drills = "Drills"
    static let progress = "Progress"

    // MARK: Metronome
    static let timeSignature = "Time Signature"
    static let accentFirstBeat = "Accent First Beat"
    static let subdivision = "Subdivision"
    static let tap = "Tap"
    static let tapTempo = "Tap tempo"
    static let couldNotStartAudio = "Couldn't Start Audio"
    static let ok = "OK"

    // MARK: What is playing
    static let drillRunning = "Drill running"
    static let drillPaused = "Drill paused"
    static let routineRunning = "Routine running"
    static let playing = "Playing"
    static func metronomeAt(_ bpm: Int) -> String { "Metronome · \(bpm) bpm" }

    // MARK: The Drills table
    static let sort = "Sort"
    static let sortDefault = "Default"
    static let sortRecent = "Last Played"
    static let sortMax = "Max Tempo"
    static let sortName = "Name"
    static let columnDrill = "Drill"
    static let columnPattern = "Pattern"
    static let notesPerBeat = "notes per beat"
    static let columnMax = "Max"
    static let columnLast = "Last"
    static func lastPlayed(_ ago: String) -> String { ago == "now" ? "just now" : "\(ago) ago" }
    static let columnBest = "Best"
    static let noDrills = "No drills. Pull to refresh."
    static let noResults = "No results"

    // MARK: A drill's setup
    static let hearIntro = "Play intro"
    static let levels = "Levels"
    static let guide = "Guide"
    static let guided = "Guided"
    static let solo = "Solo"
    static let guidedHelp = "Plays the pattern with the click."
    static let soloHelp = "Click only."
    static let run = "Run"
    static let cycles = "Cycles"
    static let time = "Time"
    static let endurance = "Endurance"
    static let open = "Open"
    static let rounds = "Rounds"
    static let duration = "Duration"
    static let targetAccuracy = "Target Accuracy"
    static let audioInput = "Audio Input"
    static let scored = "Scored"
    static let notScored = "Not scored"
    static let options = "Options"
    static let accuracyWindow = "Accuracy Window"
    static let passMark = "Pass Mark"
    static let ladder = "Ladder"
    static let ladderScoredHelp = "Speeds up after each passed cycle"
    static let ladderUnscoredHelp = "Speeds up after each cycle"
    static let click = "Click"
    static let voiceIntro = "Voice Intro"
    static let audioRoute = "Audio Route"
    static let chooseOutput = "Choose output"
    static let timing = "Timing"
    static let ladderOff = "Ladder off"
    static let noClick = "no click"
    static let noIntro = "no intro"
    static let manual = "manual"
    static func cycleCount(_ n: Int) -> String { "\(n) cycle\(n == 1 ? "" : "s")" }
    static func bpmStep(_ n: Int) -> String { "+\(n) bpm" }
    static func ladderSummary(_ n: Int) -> String { "Ladder +\(n)" }
    static func levelItem(_ name: String, _ bpm: Int) -> String { "\(name) · \(bpm) bpm" }
    static func route(_ input: String, _ output: String) -> String { "In: \(input) · Out: \(output)" }
    static func zoneCaption(_ zone: String, _ low: Int, _ high: Int, _ lowPct: Int, _ highPct: Int, _ max: Int) -> String {
        "\(zone) · \(low)–\(high) bpm\n\(lowPct)–\(highPct)% of max \(max)"
    }
    static func manualCaption(_ pct: Int, _ max: Int) -> String { "bpm · manual\n\(pct)% of max \(max)" }
    static func bestHere(_ value: String) -> String { "bpm · best \(value)" }
    static func modeCycles(_ n: Int) -> String { "\(n) cycle\(n == 1 ? "" : "s") of the pattern." }
    static func modeTime(_ clock: String) -> String { "\(clock) total." }
    static func modeRounds(_ n: Int) -> String { "\(n) round\(n == 1 ? "" : "s")." }
    static func modeEndurance(_ pct: Int) -> String { "Runs until accuracy drops below \(pct)%. Score is time held." }
    static let modeOpen = "Runs until you stop it."
    static func timingLine(display: Int, input: Int?, calibrated: Bool) -> String {
        let d = "Display \(display >= 0 ? "+" : "")\(display) ms"
        guard let input else { return d }
        return "\(d) · Input \(input) ms" + (calibrated ? "" : " (not calibrated)")
    }
    static func zoneSpoken(_ name: String, _ title: String, _ low: Int, _ high: Int) -> String {
        "\(name), \(title), \(low) to \(high) beats per minute"
    }

    // MARK: Messages about the audio
    static let connectInterface = "Connect an audio interface to score."
    static let allowMicrophone = "Allow microphone access in Settings to score."
    static let callMode = "Headphones are in call mode. Reconnect them."
    static let newAudioSetup = "New audio setup. Calibrate for accurate timing."
    static let noAudioInput = "No audio input. Connect an interface."
    /// When the interface has taken the sound as well as the guitar.
    static let outputOnInterface = "Sound is on the interface. Pick your headphones here, or use the interface's headphone out."
    static func routeChanged(_ name: String) -> String { "Audio changed to \(name)." }
    static func calibrated(ms: Int, notes: Int, spread: Int) -> String {
        "Calibrated: \(ms) ms (\(notes) notes, ±\(spread) ms)." + (spread > 25 ? " Uneven. Try again." : "")
    }
    static let calibrationTooFew = "Not enough notes. Try again."

    // MARK: The catalog
    static let drillsUpdated = "Drills updated"
    static let drillsOffline = "Offline. Using saved drills."
    static let drillsUnreadable = "Couldn't read drills. Using saved drills."

    // MARK: The intro
    static func introLine(guided: Bool, scored: Bool) -> String {
        "bpm · \(guided ? "Guided" : "Solo")" + (scored ? "" : " · Not scored")
    }

    // MARK: A run
    static let countIn = "Count-in"
    static let rest = "Rest"
    static let eighths = "Eighths"
    static let triplets = "Triplets"
    static let sixteenths = "Sixteenths"
    static func perBeat(_ n: Int) -> String { "\(n) per beat" }
    static func nextBeat(_ what: String) -> String { "\(what) next beat" }
    static func inBeats(_ what: String, _ beats: Int) -> String { "\(what) in \(beats)" }
    static func upNext(_ what: String) -> String { "Next: \(what)" }
    static let accuracy = "accuracy"
    static let cycle = "cycle"
    static let round = "round"
    static let left = "left"
    static let held = "held"
    static let elapsed = "elapsed"
    static let input = "Input"
    static let early = "early"
    static let late = "late"
    static let tapToPause = "Tap anywhere to pause"
    static let paused = "Paused"
    static let pausedHelp = "Resumes after a one-bar count-in."
    static let chipNotScored = "Not scored"
    static func percentOfMax(_ pct: Int) -> String { "\(pct)% of max" }
    static func ofTotal(_ n: Int, _ total: Int) -> String { "\(n) of \(total)" }
    static let timingLabel = "Timing"
    static let noNotesYet = "No notes yet"
    static let onTheBeat = "On the beat"
    static func msLate(_ ms: Int) -> String { "\(ms) ms late" }
    static func msEarly(_ ms: Int) -> String { "\(ms) ms early" }

    // MARK: A result
    static let accuracyPassed = "Accuracy · Passed"
    static func accuracyPassMark(_ pct: Int) -> String { "Accuracy · Pass mark \(pct)%" }
    static func heldAt(_ pct: Int) -> String { "Held at \(pct)% accuracy" }
    static let newBest = "New best at this tempo"
    static func newMax(_ to: Int, from: Int) -> String { from > 0 ? "New max: \(to) bpm (was \(from))" : "New max: \(to) bpm" }
    static let timingPerNote = "Timing per note"
    static let statAccuracy = "Accuracy"
    static let statOnBeat = "On the Beat"
    static let statAverage = "Average"
    static let statSpread = "Spread"
    static let statMissed = "Missed"
    static let statExtra = "Extra"
    static let statAccents = "Accents"
    static let statDuration = "Duration"
    static func ms(_ n: Int) -> String { "\(n) ms" }
    static func percent(_ n: Int) -> String { "\(n)%" }
    static func durationAndCycles(_ clock: String, _ cycles: Int) -> String {
        cycles > 0 ? "\(clock) · \(cycles) cycle\(cycles == 1 ? "" : "s")" : clock
    }
    static let playSolo = "Play Solo"
    static let noNotes = "No notes detected"
    static func tempoRange(_ from: Int, _ to: Int) -> String { to > from ? "\(from)–\(to) bpm" : "\(from) bpm" }
    static func chip(guided: Bool, tempo: String) -> String { "\(guided ? "Guided" : "Solo") · \(tempo)" }
    static func unscoredTotal(_ minutes: String) -> String { "Not scored · \(minutes) total" }

    // MARK: Calibration
    static func calibrationStep(_ n: Int) -> String { "Calibration · \(n) of 2" }
    static let displaySync = "Display Sync"
    static let inputSync = "Input"
    static let displaySyncHelp = "Adjust until each mark crosses the line on the click."
    static let inputSyncHelp = "Play one note as each mark crosses the line."
    static func output(_ name: String) -> String { "Output: \(name)" }
    static let earlier = "Earlier"
    static let later = "Later"
    static let displayOffset = "Display offset"
    static func milliseconds(_ n: Int) -> String { "\(n) milliseconds" }
    static func signedMs(_ n: Int) -> String { "\(n >= 0 ? "+" : "")\(n) ms" }
    static let notes = "notes"

    // MARK: Progress
    static let syncing = "Syncing…"
    static func synced(pending: Int) -> String { pending == 0 ? "Synced" : "Synced · \(pending) pending" }
    static func offline(pending: Int) -> String { pending == 0 ? "Offline" : "Offline · \(pending) pending" }
    static let noRuns = "No runs yet"
    static func maxBPM(_ n: Int) -> String { "max \(n) bpm" }
    static func tempoTrend(_ low: Int, _ high: Int) -> String { "Tempo: \(low)–\(high) bpm" }
    static let tempoTrendLabel = "Tempo by run"
    static let unscoredPractice = "Unscored practice"
    static let recent = "Recent"
    static func runCount(_ n: Int) -> String { "\(n) run\(n == 1 ? "" : "s")" }
    static func modeName(_ mode: String) -> String {
        switch mode {
        case "endurance": return "Endurance"
        case "duration": return "Time"
        case "routine": return "Rounds"
        default: return "Cycles"
        }
    }

    // MARK: Settings
    static let sound = "Sound"
    static let clickVolume = "Click Volume"
    static let keepScreenOn = "Keep Screen On"
    static let lockScreenControls = "Lock Screen Controls"
    static let soundFooter = "Lock Screen Controls pause other apps' audio while Practice plays."
    static let voice = "Voice"
    static let voiceCues = "Voice Cues"
    static let preview = "Preview"
    static let previewParts = [IntroText.Part(key: "say.trip16x4", text: "Triplets to sixteenths. Four and four."),
                               IntroText.Part(key: "bpm.120", text: "120."), IntroText.Part(key: "cycles.8", text: "8 cycles.")]
    static let voiceFooter = "Intros and cues use a recorded voice. The voice chosen here speaks anything it has no recording for."
    static let timingFooter = "Calibrate once for each audio setup."
    static let sync = "Sync"
    static let updateDrills = "Update Drills"
    static let pendingRuns = "Pending Runs"
    static let syncNow = "Sync Now"
    static let syncFooter = "Drills and runs sync with the mini PC over Tailscale."
    static let about = "About"
    static let version = "Version"
    static func updateTo(_ v: String) -> String { "Update to \(v)" }
    static let checkForUpdates = "Check for Updates"
    static let advanced = "Advanced"
    static let useMicrophone = "Use iPhone Microphone"
    static let microphoneFooter = "For testing without an interface."
}
