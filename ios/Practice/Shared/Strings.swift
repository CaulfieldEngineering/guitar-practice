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
    static let timeSignature = "Time signature"
    static let accentFirstBeat = "Accent first beat"
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
    static func metronomeAt(_ bpm: Int) -> String { "Metronome at \(bpm) bpm" }

    // MARK: The Drills table
    static let sort = "Sort"
    static let sortDefault = "Default"
    static let sortRecent = "Last played"
    static let sortMax = "Max tempo"
    static let sortName = "Name"
    static let columnDrill = "Drill"
    static let columnPattern = "Pattern"
    static let notesPerBeat = "notes per beat"
    static let columnMax = "Max"
    static let columnLast = "Last"
    static func lastPlayed(_ ago: String) -> String { ago == "now" ? "just now" : "\(ago) ago" }
    static let columnBest = "Best"
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
    static let targetAccuracy = "Target accuracy"
    static let audioInput = "Audio input"
    static let scored = "Scored"
    static let notScored = "Not scored"
    static let options = "Options"
    static let accuracyWindow = "Accuracy window"
    static let passMark = "Pass mark"
    static let ladder = "Ladder"
    static let ladderScoredHelp = "Speeds up after each passed cycle"
    static let ladderUnscoredHelp = "Speeds up after each cycle"
    static let click = "Click"
    static let voiceIntro = "Voice intro"
    static let audioRoute = "Audio route"
    static let chooseOutput = "Choose output"
    static let timing = "Timing"
    static let ladderOff = "Ladder off"
    static let noClick = "no click"
    static let noIntro = "no intro"
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
    static let accuracy = "Accuracy"
    static let cycle = "cycle"
    static let round = "round"
    static let left = "left"
    static let held = "held"
    static let elapsed = "Elapsed"
    static let input = "Input"
    static let early = "Early"
    static let late = "Late"
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
    static func heldAt(_ pct: Int) -> String { "held at \(pct)%" }
    static let newBest = "New best at this tempo"
    static func newMax(_ to: Int, from: Int) -> String { from > 0 ? "New max \(to) bpm, up from \(from)" : "New max \(to) bpm" }
    static let timingPerNote = "Timing per note"
    static let statAccuracy = "Accuracy"
    static let statOnBeat = "On the Beat"
    static let statAverage = "Average"
    static func resultTiming(average: String, spread: Int, band: String) -> String { "\(average) · spread \(spread) ms · \(band)" }
    static let bandLocked = "Locked", bandTight = "Tight", bandGood = "Good", bandLoose = "Loose", bandRough = "Rough"
    static func extraCost(_ n: Int, points: Int) -> String { "\(n) extra notes took \(points) points off" }
    /// What the spread means (Scoring.band): the anchors from timing research, so the number reads against players.
    static let timingAnchors = "Spread: session players 10–15 ms, good amateurs 20–30, beginners 40–60. At 90 bpm sixteenths, 15 ms scores about 99%, 25 about 91%, 40 about 74%."
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
    static let playSolo = "Play solo"
    static let noNotes = "No notes detected"
    static func tempoRange(_ from: Int, _ to: Int) -> String { to > from ? "\(from) to \(to)" : "\(from)" }
    static func chip(guided: Bool, tempo: String) -> String { "\(guided ? "Guided" : "Solo") · \(tempo)" }
    static func unscoredTotal(_ minutes: String) -> String { "Not scored · \(minutes) total" }

    // MARK: Calibration
    static func calibrationStep(_ n: Int) -> String { "Calibration · \(n) of 2" }
    static let displaySync = "Display sync"
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
    static let syncing = "Syncing"
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
    static let clickVolume = "Click volume"
    static let keepScreenOn = "Keep screen on"
    static let lockScreenControls = "Lock screen controls"
    static let soundFooter = "Lock screen controls pause other apps' audio while Practice plays."
    static let voice = "Voice"
    static let voiceCues = "Voice cues"
    static let preview = "Preview"
    static let previewParts = [IntroText.Part(key: "say.trip16x4", text: "Triplets to sixteenths. Four and four."),
                               IntroText.Part(key: "bpm.120", text: "120."), IntroText.Part(key: "cycles.8", text: "8 cycles.")]
    static let voiceFooter = "Intros and cues use a recorded voice. The voice chosen here speaks anything it has no recording for."
    static let timingFooter = "Calibrate once for each audio setup."
    static let sync = "Sync"
    static let updateDrills = "Update drills"
    static let pendingRuns = "Pending runs"
    static let syncNow = "Sync now"
    static let server = "Server"
    static let syncFooter = "Drills and runs sync with the mini PC over Tailscale."
    static let about = "About"
    static let version = "Version"
    static func updateTo(_ v: String) -> String { "Update to \(v)" }
    static let checkForUpdates = "Check for Updates"
    static let advanced = "Advanced"
    static let useMicrophone = "Use iPhone Microphone"
    static let microphoneFooter = "For testing without an interface."

    // MARK: Audio (Settings > Audio, and the drill's Input and Output rows)
    static let audio = "Audio"
    static let inputDevice = "Input"
    static let outputDevice = "Output"
    static let noInputName = "No input"
    static let noOutputName = "No output"
    static let pickedDevice = "The device you picked"
    static let phoneSpeaker = "iPhone Speaker"
    static let otherOutput = "Other output"
    static func inputOf(_ name: String, _ n: Int) -> String { "\(name) · Input \(n)" }
    static func inputsBoth(_ name: String) -> String { "\(name) · Inputs 1 and 2" }
    static let micPosition = "Mic"
    static let channel = "Channel"
    static func channelName(_ c: InputChannel) -> String {
        switch c { case .both: return "Inputs 1 and 2"; case .first: return "Input 1"; case .second: return "Input 2" }
    }
    static let inputGain = "Input gain"
    static let level = "Level"
    static func verdict(_ v: LevelVerdict) -> String {
        switch v { case .noSignal: return "No signal"; case .tooQuiet: return "Too quiet"; case .good: return "Good"; case .clipping: return "Clipping" }
    }
    static let notListening = "Not listening"
    static let testTone = "Test tone"
    static let clickTest = "Click test"
    static let appSounds = "App sounds"
    static let appSoundsFooter = "Clicks, guide and voice, against the guitar. Kept for each output."
    static let monitoring = "Monitoring"
    static let hearGuitar = "Hear guitar"
    static let guitarLevel = "Guitar level"
    static let monitorBluetooth = "Bluetooth adds delay. Listen through the interface's own headphone out."
    static let monitorSpeaker = "Off on the iPhone speaker and mic, which would feed back."
    static let latency = "Latency"
    static let latencyInput = "Input"
    static let latencyOutput = "Output"
    static let latencyBuffer = "Buffer"
    static let latencyTotal = "Total"
    static let calibration = "Calibration"
    static let notCalibrated = "Not calibrated"
    static func calibratedOn(_ ms: Int, _ date: String) -> String { "\(ms) ms, \(date)" }
    static let check = "Check"
    static let sessionDetails = "Session details"
    static let category = "Category"
    static let mode = "Mode"
    static let sessionOptions = "Options"
    static let microphone = "Microphone"
    static let allowed = "Allowed"
    static let denied = "Denied"
    static let notAsked = "Not asked"
    static let interface = "Interface"
    static let notFound = "Not found"
    static let inputsListed = "Inputs"
    static let outputsListed = "Outputs"
    static let sampleRate = "Sample rate"
    static let channels = "Channels"
    static let openSettings = "Open settings"
    static let allow = "Allow"
    static func useInput(_ n: Int) -> String { "Use input \(n)" }
    static func deviceChanged(_ name: String) -> String { "Audio device changed: \(name)" }
    static func hz(_ rate: Double) -> String { "\(Int(rate.rounded())) Hz" }

    // The choice, and why iOS used something else (one line each).
    static func fallbackInputMissing(_ want: String, _ now: String) -> String { "\(want) isn't connected. Using \(now)." }
    static let audioKeptSwitching = "Audio kept switching, so the output pick was cleared."
    static func replugInput(_ name: String) -> String { "iOS won't switch to \(name). Unplug it and plug it in again." }
    static func fallbackInputRefused(_ want: String, _ now: String) -> String { "iOS kept \(now) instead of \(want)." }
    static func fallbackSpeaker(_ now: String) -> String { "iOS kept the sound on \(now)." }
    static func fallbackSpeakerClosed(_ now: String) -> String { "The speaker is used once the input opens. Now on \(now)." }
    static func fallbackOutput(_ want: String, _ now: String) -> String { "Sound is on \(now). Pick \(want) in the list again." }
    static func fallbackBluetoothUSB(_ want: String, _ now: String) -> String {
        "iOS won't send sound to \(want) while recording from the interface, so it's on \(now)."
    }

    // What is wrong, in plain words.
    static let diagPermissionOff = "Microphone access is off"
    static let diagPermissionStep = "Settings > Practice > Microphone"
    static let diagPermissionAsk = "Allow microphone access to hear the guitar"
    static let diagNoInterface = "No interface found"
    static let diagStepPower = "Power it: most interfaces need a powered USB-C hub on iPhone"
    static let diagStepClassCompliant = "It has to work without a driver (class compliant)"
    static let diagStepReplug = "Unplug it and plug it back in"
    static let diagBluetoothLimit = "iOS moved the input off the interface for Bluetooth"
    static let diagStepTransmitter = "Pair a Bluetooth transmitter on the interface's headphone out with the Shokz"
    static let diagOnInterface = "Sound goes to the interface"
    static let diagStepPickShokz = "Pick the Shokz under Output"
    static let diagGainZero = "Input gain is at zero"
    static let diagStepRaiseGain = "Raise the input gain above"
    static func diagOtherInput(_ n: Int) -> String { "The guitar is on Input \(n)" }
    static let diagNoSignal = "No guitar signal"
    static let diagStepPlay = "Play a few notes"
    static let diagStepBoth = "Set Channel to inputs 1 and 2"
    static let diagStepGain = "Turn up the gain knob on the interface"
    static let diagStepInst = "Use the instrument (Inst or Hi-Z) input"
    static let diagStepCable = "Check the cable and the guitar's volume knob"
    static let diagStepPickInterface = "Pick the interface under Input"
    static let diagTooQuiet = "The guitar is quiet"
    static let diagClipping = "The guitar is clipping"
    static let diagStepLower = "Turn down the gain knob on the interface"
}
